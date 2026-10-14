import AppKit
import Combine
import Foundation
import MPMCore

// The app around the session: the view state the screens share (UI in state.js), what the Mac
// keeps between launches, the clock loop, and the hooks the engine calls: the voice, the sounds,
// the feed, saving. One object, observed by every view; it ticks ten times a second.

enum AppRole: String { case b, a, admin }
enum BoardMode: String { case map, table }
enum ATab: String { case table, grid, log }
enum AdTab: String { case monitor, log, feed }
enum SettingsTab: String { case session, model, general, schedule }

struct ScheduleEntry: Codable, Equatable {
    var at: String
    var why: String
}

struct ToastState: Equatable {
    var text: String
    var error: Bool
    var until: Double
}


final class AppModel: ObservableObject {
    static let shared = AppModel()

    let session: Session
    var updater: Updater?

    /// Bumped every frame: views that show the clocks read it.
    @Published private(set) var frame = 0

    // MARK: View state (UI)
    @Published var role: AppRole = .b
    @Published var boardOpen = false
    @Published var boardView: BoardMode = .map
    @Published var aTab: ATab?
    @Published var adTab: AdTab = .monitor
    @Published var settingsOpen = false
    @Published var settingsTab: SettingsTab = .session
    @Published var depFor: NodeID?
    @Published var renaming: NodeID?
    @Published var folded: Set<NodeID> = []
    @Published var logPart: Part?
    @Published var logProblems = false
    @Published var logSel: Int?
    @Published var monitorSel: Part?
    @Published var toast: ToastState?
    @Published var reason = ""
    @Published var reasonFor: String?
    @Published var gridRound = 0

    // MARK: Settings kept on this Mac
    @Published private(set) var voiceOn = true
    @Published private(set) var muted = false
    @Published private(set) var testMode = false
    @Published var feedURL = ""
    @Published private(set) var feedOn = false
    @Published var schedule: [ScheduleEntry] = []
    @Published private(set) var feedLog: [FeedLogLine] = []
    @Published private(set) var feedFails = 0

    struct FeedLogLine: Identifiable, Equatable {
        var id: Int
        var kind: String
        var at: String
        var ok: Bool
        var why: String
    }

    // MARK: The voice and the sounds
    let speaker = Speaker()
    let tones = Tones()
    private var lastSpokenScreen = ""
    private var scheduleFired: Set<String> = []
    private var feedQueue: [FeedMessage] = []
    private var feedBusy = false
    private var cancellables: Set<AnyCancellable> = []

    private let defaults = UserDefaults.standard

    var updateAvailable: Bool {
        if case .available = updater?.state ?? .idle { return true }
        return false
    }

    private init() {
        session = Session()
        session.speed = Launch.speed
        loadSettings()
        if let plan = Storage.loadPlan() { session.load(plan) }
        session.intake = Session.Intake(stage: session.firstStage(), ids: [])
        wire()
    }

    private func wire() {
        session.onSavePlan = { Storage.savePlan($0) }
        session.onSaveSettings = { [weak self] in self?.saveSettings() }
        session.onToast = { [weak self] t, info in self?.showToast(t, error: !info) }
        session.onSound = { [weak self] k in self?.tones.play(k, muted: self?.muted ?? false) }
        session.onSay = { [weak self] text, _ in self?.speakIfOn(text) }
        session.onFeed = { [weak self] m in self?.pushFeed(m) }
        session.onEvent = { [weak self] e in self?.monitorPulse(e) }
        session.onRequestDecided = { _ in }
    }

    // MARK: The clock loop

    func frame(real: Double) {
        session.advance(real: real)
        checkSchedule()
        speakScreens()
        if let t = toast, session.mono() > t.until { toast = nil }
        frame &+= 1
    }

    // MARK: The voice: every confirmation for B is spoken, unless turned off (Admin)

    private func speakIfOn(_ text: String) {
        guard voiceOn, !text.isEmpty else { return }
        speaker.say(text)
    }

    /// The request screen's lines, as they appear: "Ready when you are. Round 2: … Go."
    private func speakScreens() {
        let s = session
        let m = s.coverModel() ?? s.stripModel()
        let key = m.map { "\($0.kind)|\($0.heading)|\($0.line)|\($0.question ?? "")|\(s.req?.id ?? "")|\(s.sys?.id ?? "")" } ?? ""
        if key == lastSpokenScreen { return }
        lastSpokenScreen = key
        guard let m = m, let spoken = m.spoken, !spoken.isEmpty else { return }
        speakIfOn(spoken)
    }

    func setVoiceOn(_ v: Bool) {
        voiceOn = v
        if !v { speaker.stop() }
        saveSettings()
        session.logEvent(.man, .output, .info, v ? "spoken confirmations on" : "spoken confirmations off", v ? "every confirmation for B is spoken" : "the screens only")
    }

    func setMuted(_ v: Bool) { muted = v; saveSettings() }

    func setTestMode(_ v: Bool) {
        testMode = v
        session.speed = v ? 60 : Launch.speed
        showToast(v ? "Test mode: the clocks run 60× faster." : "Normal speed.", error: false)
    }

    // MARK: Roles and screens

    func setRole(_ r: AppRole) {
        role = r
        depFor = nil
        renaming = nil
    }

    func setBoard(_ open: Bool, _ view: BoardMode? = nil) {
        boardOpen = open
        if let v = view { boardView = v }
        defaults.set(["open": open, "view": boardView.rawValue] as [String: Any], forKey: "mpm.board")
    }

    func openSettings(tab: SettingsTab) {
        settingsTab = tab
        settingsOpen = true
    }

    func showToast(_ t: String, error: Bool) {
        toast = ToastState(text: t, error: error, until: session.mono() + min(8000, 2000 + Double(t.count) * 60))
    }

    /// The one thing the screen asks for (Space).
    func primary() {
        guard role == .b else { return }
        switch session.bView() {
        case .intake: return
        default: session.primary()
        }
    }

    func askToEnd() {
        if session.canEnd() { session.raise(.end); role = .b; Windows.shared.showMain() }
    }

    func willQuit() {
        saveSettings()
        _ = Storage.savePlan(session.snapshot())
    }

    // MARK: Settings on this Mac (SETTINGS_KEY and friends)

    private func loadSettings() {
        let d = defaults
        if let data = d.data(forKey: "mpm.settings"), let s = try? JSONDecoder().decode(SavedSettings.self, from: data) {
            if s.cfg.isValid { session.cfg = s.cfg }
            session.modelOn = s.model
            if let v = VoiceStyle(rawValue: s.voice) { session.voice = v }
            muted = s.muted
            voiceOn = s.voiceOn ?? true
            feedURL = String(s.feedURL.prefix(2000))
            feedOn = s.feedOn && Self.feedUrlOk(feedURL)
            schedule = s.schedule
            session.names = Names(b: s.nameB, a: s.nameA)
            session.auto = s.auto ?? true
        }
        let seat = d.double(forKey: "mpm.seated")
        session.seatStart = max(0, min(240, seat)) * 60
        if let b = d.dictionary(forKey: "mpm.board") {
            boardOpen = b["open"] as? Bool ?? false
            boardView = BoardMode(rawValue: b["view"] as? String ?? "map") ?? .map
        }
    }

    func saveSettings() {
        let s = SavedSettings(cfg: session.nextCfg ?? session.cfg, model: session.modelOn, voice: session.voice.rawValue, muted: muted,
                              voiceOn: voiceOn, feedURL: feedURL, feedOn: feedOn, schedule: schedule,
                              nameB: session.names.b, nameA: session.names.a, auto: session.auto)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: "mpm.settings") }
        defaults.set(session.seatStart / 60, forKey: "mpm.seated")
    }

    struct SavedSettings: Codable {
        var cfg: SessionConfig
        var model: Bool
        var voice: String
        var muted: Bool
        var voiceOn: Bool?
        var feedURL: String
        var feedOn: Bool
        var schedule: [ScheduleEntry]
        var nameB: String
        var nameA: String
        var auto: Bool?
    }

    // MARK: Scheduled look-ins (Settings › Schedule)

    private func checkSchedule() {
        guard !schedule.isEmpty else { return }
        let d = Date()
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let hm = Format.pad2(c.hour ?? 0) + ":" + Format.pad2(c.minute ?? 0)
        let day = Calendar.current.startOfDay(for: d).timeIntervalSince1970
        for s in schedule {
            let k = "\(day) \(s.at) \(s.why)"
            if s.at == hm && !scheduleFired.contains(k) {
                scheduleFired.insert(k)
                session.schedulerNote(s.at, s.why)
            }
        }
    }

    func addSchedule(at: String, why: String) {
        schedule.append(ScheduleEntry(at: at, why: why))
        schedule.sort { $0.at < $1.at }
        saveSettings()
        session.logEvent(.man, .scheduler, .info, "schedule entry added", "\(at) \(why)")
    }

    func removeSchedule(_ i: Int) {
        guard schedule.indices.contains(i) else { return }
        let s = schedule.remove(at: i)
        saveSettings()
        session.logEvent(.man, .scheduler, .info, "schedule entry removed", "\(s.at) \(s.why)")
    }

    // MARK: A's feed (feed.js): one POST per thing A's screen shows, one way only

    static func feedUrlOk(_ u: String) -> Bool {
        u.range(of: "^https?://\\S+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    func setFeed(url: String, on: Bool) {
        let u = url.trimmingCharacters(in: .whitespaces)
        let was = "\(feedURL)|\(feedOn)"
        feedURL = u
        feedOn = on && Self.feedUrlOk(u)
        if was == "\(feedURL)|\(feedOn)" { return }
        saveSettings()
        if feedOn { session.feedHello() }
        session.logEvent(.man, .feed, .info, feedOn ? "feed on" : u.isEmpty ? "feed cleared" : "feed off", feedURL)
    }

    func feedTest() { session.feedTest() }

    private func pushFeed(_ m: FeedMessage) {
        guard feedOn, !feedURL.isEmpty else { return }
        feedQueue.append(m)
        if feedQueue.count > 50 { feedQueue.removeFirst() }
        feedDrain()
    }

    private func feedDrain() {
        guard !feedBusy, !feedQueue.isEmpty, let url = URL(string: feedURL) else { return }
        let m = feedQueue.removeFirst()
        feedBusy = true
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = m.body.data()
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400
            let why = error?.localizedDescription ?? ((response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? "")
            DispatchQueue.main.async { self?.feedDone(m, ok: ok, why: ok ? "" : why) }
        }.resume()
    }

    private func feedDone(_ m: FeedMessage, ok: Bool, why: String) {
        feedBusy = false
        feedLog.append(FeedLogLine(id: m.seq, kind: m.kind, at: m.at, ok: ok, why: why))
        if feedLog.count > 12 { feedLog.removeFirst() }
        if ok {
            if feedFails > 0 { session.logEvent(.feed, nil, .ok, "feed delivering again", "after \(feedFails) failed") }
            feedFails = 0
        } else {
            feedFails += 1
            if feedFails == 1 { session.logEvent(.a, .feed, .warning, "feed: not delivered", why + "\n" + feedURL + "\nlater failures in a row are counted, not logged") }
        }
        feedDrain()
    }

    // MARK: The Monitor's pulses

    struct Pulse: Identifiable {
        var id: Int
        var from: Part
        var to: Part
        var tone: Tone
        var start: Double
    }
    @Published private(set) var pulses: [Pulse] = []
    @Published private(set) var lastEventLine = ""

    private func monitorPulse(_ e: Event) {
        lastEventLine = e.at + " · " + e.route + " · " + e.title
        guard let to = e.to, role == .admin, adTab == .monitor else { return }
        pulses.append(Pulse(id: e.id, from: e.from, to: to, tone: e.outcome.tone, start: session.mono()))
        let now = session.mono()
        pulses.removeAll { now - $0.start > 480 }
    }

    func livePulses() -> [Pulse] {
        let now = session.mono()
        return pulses.filter { now - $0.start < 480 }
    }

    // MARK: The session transcript, saved where the user chose

    func saveTranscript() {
        let s = session
        var lines: [String] = ["# Machine Prompts Man · session transcript", "", "Saved \(Format.stamp(Date().timeIntervalSince1970 * 1000)) · \(Updater.versionLine)", ""]
        lines.append("## Requests")
        for r in s.requests {
            lines.append("- \(r.id) round \(r.round) · \(r.label) · by \(r.raisedBy.rawValue) · policy \(r.policy?.word ?? "-") · \(r.verdict?.rawValue ?? "waiting")" + (r.decidedBy.map { " by \($0.rawValue)" } ?? "") + (r.reason.isEmpty ? "" : " “\(r.reason)”") + " · \(r.outcome?.rawValue ?? "open")")
        }
        lines.append("")
        lines.append("## Events")
        for e in s.events {
            lines.append("- \(e.at) \(e.route) · \(e.outcome.word) · \(e.title)")
            if !e.detail.isEmpty { for l in e.detail.split(separator: "\n") { lines.append("    \(l)") } }
        }
        if OutputFolder.current() == nil { OutputFolder.choose() }
        do {
            let url = try OutputFolder.write(lines.joined(separator: "\n") + "\n", kind: "session", at: Date())
            showToast("Transcript saved: \(url.lastPathComponent)", error: false)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showToast("Couldn't save the transcript: \(error.localizedDescription)", error: true)
        }
    }
}

/// Where the plan lives between launches: ~/Library/Application Support/MachinePromptsMan/plan.json.
enum Storage {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MachinePromptsMan", isDirectory: true)
    }
    static var planURL: URL { folder.appendingPathComponent("plan.json") }

    static func savePlan(_ p: PlanSnapshot) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(p)
            try data.write(to: planURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func loadPlan() -> PlanSnapshot? {
        guard let data = try? Data(contentsOf: planURL) else { return nil }
        return try? JSONDecoder().decode(PlanSnapshot.self, from: data)
    }
}
