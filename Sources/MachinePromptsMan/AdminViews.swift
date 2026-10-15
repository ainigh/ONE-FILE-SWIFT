import MPMCore
import SwiftUI

/// Admin: watches. The Monitor, the event log, A's feed, and the voice switch.
struct AdminScreen: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Seg(items: [(AdTab.monitor, "Monitor"), (.log, "Event log"), (.feed, "Feed")], selection: $app.adTab)
                Text(app.lastEventLine).font(Theme.fine).foregroundStyle(Color.ink3).lineLimit(1)
                Spacer()
                Toggle(isOn: Binding(get: { app.voiceOn }, set: { app.setVoiceOn($0) })) {
                    Text("Spoken confirmations").font(Theme.fine).foregroundStyle(Color.ink2)
                }
                .toggleStyle(.switch).controlSize(.small)
                .help("Every confirmation for B is spoken out loud. On by default.")
                Toggle(isOn: Binding(get: { !app.muted }, set: { app.setMuted(!$0) })) {
                    Text("Sounds").font(Theme.fine).foregroundStyle(Color.ink2)
                }
                .toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(Color.line).frame(height: 1)
            switch app.adTab {
            case .monitor: MonitorView()
            case .log: LogView()
            case .feed: FeedView()
            }
        }
    }
}

/// The Monitor (monitor.js): the parts as a mind map. A card says what the part last handled; its
/// dot, the outcome. Every hand-off runs its line.
struct MonitorView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let spec = MapSpec(root: Part.engine.rawValue, tops: Part.under(.engine).map(\.rawValue),
                           kids: { Part(rawValue: $0).map { Part.under($0).map(\.rawValue) } ?? [] },
                           parent: { Part(rawValue: $0)?.up?.rawValue },
                           ids: Part.allCases.map(\.rawValue),
                           side: { id, _ in Part(rawValue: id)?.side ?? "r" },
                           height: { $0 == "engine" ? 92 : 56 }, below: { _ in 0 }, folded: [], cardW: 196, hubW: 220)
        let links = Part.links.map { MapLink(a: $0.0.rawValue, b: $0.1.rawValue, color: .ink3, dashed: true, head: false, faded: false) }
        let now = s.mono()
        let pulses = app.livePulses().map { MapPulse(from: $0.from.rawValue, to: $0.to.rawValue, color: Theme.color($0.tone), k: min(1, (now - $0.start) / 480)) }
        HStack(spacing: 0) {
            MapView(spec: spec, links: links, pulses: pulses, focus: app.monitorSel?.rawValue,
                    legend: [(.doing, "Hand-off", false), (.done, "Done", false), (.blocked, "Warning", false), (.stop, "Error", false), (.ink3, "Also hands off", true)],
                    empty: "", onBackground: { app.monitorSel = nil }, onFold: { _ in }, now: nil, fitTick: app.mapFit,
                    card: { id, _ in PartCard(part: Part(rawValue: id) ?? .engine) },
                    overlay: { _, _ in EmptyView() })
            Rectangle().fill(Color.line).frame(width: 1)
            PartInspector().frame(width: 280)
        }
    }
}

struct PartCard: View {
    @EnvironmentObject var app: AppModel
    let part: Part

    var body: some View {
        let s = app.session
        let mine = s.events.last { $0.from == part || $0.to == part }
        let last = s.events.last { ($0.from == part || $0.to == part) && $0.outcome != .info }
        let cnt = s.unseen[part] ?? 0
        let working = isWorking(s)
        let sel = app.monitorSel == part
        VStack(alignment: .leading, spacing: 3) {
            if part == .engine {
                Label2("Hub")
                Text(part.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    let len = s.running() ? s.phaseLen() : 0
                    Ring(fraction: len > 0 ? s.left() / len : 1, color: Theme.color(s.tone()), lineWidth: 3).frame(width: 18, height: 18)
                    Text(phaseLine(s)).font(Theme.fine).foregroundStyle(Color.ink2)
                }
                Text(mine?.title ?? "Quiet").font(Theme.fine).foregroundStyle(Color.ink3).lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(last.map { Theme.color($0.outcome.tone) } ?? Color.ink3).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(working ? Color.white : Color.ink)
                        Text(mine?.title ?? "Quiet").font(Theme.fine).foregroundStyle(working ? Color.white.opacity(0.85) : Color.ink3).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if cnt > 0 {
                        Text("\(cnt)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.blocked))
                    }
                }
                if part == .model, let t = s.turn, !t.done, s.state == .status, s.running() {
                    let u = min(1, (s.T - t.since) / max(1, t.deadline - t.since))
                    GeometryReader { g in
                        ZStack(alignment: .leading) { Capsule().fill(Color.white.opacity(0.3)); Capsule().fill(Color.white).frame(width: g.size.width * u) }
                    }.frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(working ? Color.doing : Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(sel ? Color.ink : cnt > 0 ? Color.blocked : Color.line2, style: StrokeStyle(lineWidth: sel ? 2 : 1.2, dash: cnt > 0 && !sel ? [4, 3] : [])))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.logPart = part; app.adTab = .log; s.markSeen(part) }
        .onTapGesture { app.monitorSel = sel ? nil : part }
        .help("\(part.title): \(part.what)")
    }

    private func isWorking(_ s: Session) -> Bool {
        if part == .model, s.state == .status, s.running(), let t = s.turn, !t.done { return true }
        if part == .a, let r = s.openReq, r.verdict == nil { return true }
        return false
    }

    private func phaseLine(_ s: Session) -> String {
        guard let st = s.state else { return "No session" }
        let w: String
        switch st {
        case .idle: w = "Idle"
        case .work: w = "Round \(s.round)"
        case .snooze: w = "Snooze \(s.z)"
        case .status: w = "Check-up"
        case .strategy: w = "Planning"
        case .break: w = "Break"
        }
        return s.frozen ? w + " · waiting for Go" : s.running() ? w + " · \(Format.digits(s.left())) left" : w
    }
}

/// The part's inspector: what it does, who it hands off to, and its latest events.
struct PartInspector: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let k = app.monitorSel {
                    let mine = s.events.filter { $0.from == k || $0.to == k }
                    let cnt = s.unseen[k] ?? 0
                    Text(k.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink)
                    Text(k.what).font(Theme.fine).foregroundStyle(Color.ink2)
                    let last = mine.last { $0.outcome != .info }
                    let working = (k == .model && s.state == .status && s.running() && s.turn?.done == false) || (k == .a && s.openReq?.verdict == nil && s.openReq != nil)
                    HStack(spacing: 6) {
                        Circle().fill(working ? Color.doing : cnt > 0 ? Color.blocked : last.map { Theme.color($0.outcome.tone) } ?? Color.ink3).frame(width: 9, height: 9)
                        Text(k == .a && working ? "Has a request to answer" : working ? "Working, on a deadline" : cnt > 0 ? Format.n(cnt, "unseen problem", "unseen problems") : last.map { "\($0.outcome.word) last" } ?? "Quiet")
                            .font(Theme.fine).foregroundStyle(Color.ink2)
                    }
                    Label2("Hands off to")
                    FlowChips(parts: Self.neighbours(k)) { app.monitorSel = $0 }
                    Label2("Events")
                    Text("\(mine.count)").font(Theme.fine).foregroundStyle(Color.ink2)
                    Label2("Latest")
                    if mine.isEmpty { Text("Nothing yet.").font(Theme.fine).foregroundStyle(Color.ink3) }
                    ForEach(mine.suffix(6).reversed()) { x in
                        Button { app.logSel = x.id; app.logPart = k; app.adTab = .log; s.markSeen(k) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Theme.color(x.outcome.tone)).frame(width: 6, height: 6)
                                Text(x.at).font(Theme.mono(10)).foregroundStyle(Color.ink3)
                                Text(x.title).font(Theme.fine).foregroundStyle(Color.ink).lineLimit(1)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    HStack {
                        Button("Open in the event log") { app.logPart = k; app.adTab = .log; s.markSeen(k) }.buttonStyle(MPMButtonStyle(kind: .small))
                        if cnt > 0 { Button("Mark seen") { s.markSeen(k) }.buttonStyle(MPMButtonStyle(kind: .small)) }
                    }
                } else {
                    Text("Nothing selected").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                    Text("Click a part for what it does and its latest hand-offs. Double-click opens its events in the log.").font(Theme.fine).foregroundStyle(Color.ink2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bg)
    }

    /// The parts this one hands off to: its parent, its branches, and its links.
    static func neighbours(_ k: Part) -> [Part] {
        var near: [Part] = []
        if let u = k.up { near.append(u) }
        near += Part.under(k)
        for l in Part.links {
            if l.0 == k { near.append(l.1) }
            if l.1 == k { near.append(l.0) }
        }
        return near
    }
}

struct FlowChips: View {
    var parts: [Part]
    var tap: (Part) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(parts, id: \.self) { p in
                Button(p.title) { tap(p) }.buttonStyle(.plain).font(Theme.fine).foregroundStyle(Color.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.surface2)).overlay(Capsule().strokeBorder(Color.line))
            }
        }
    }
}

/// The event log (log.js), shared by A's Log and Admin's Event log.
struct LogView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let list = s.events.filter { (app.logPart == nil || $0.from == app.logPart || $0.to == app.logPart) && (!app.logProblems || $0.outcome == .warning || $0.outcome == .error) }.reversed()
        let sel = s.events.first { $0.id == app.logSel }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Part", selection: Binding(get: { app.logPart?.rawValue ?? "" }, set: { v in app.logPart = Part(rawValue: v); if let p = app.logPart { s.markSeen(p) } })) {
                    Text("All parts").tag("")
                    ForEach(Part.allCases, id: \.rawValue) { p in Text(p.title).tag(p.rawValue) }
                }
                .labelsHidden().frame(width: 160)
                Toggle("Problems only", isOn: $app.logProblems).toggleStyle(.button).controlSize(.small)
                Button("Mark seen") { s.markSeen() }.buttonStyle(MPMButtonStyle(kind: .small))
                Text(Format.n(list.count, "event", "events")).font(Theme.fine).foregroundStyle(Color.ink3)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if list.isEmpty { Text(s.events.isEmpty ? "Nothing has happened yet." : "Nothing matches.").font(Theme.fine).foregroundStyle(Color.ink3).padding(10) }
                        ForEach(Array(list.prefix(250))) { e in
                            HStack(spacing: 8) {
                                Text(e.at).font(Theme.mono(10)).foregroundStyle(Color.ink3)
                                Circle().fill(Theme.color(e.outcome.tone)).frame(width: 6, height: 6)
                                Text(e.route).font(Theme.fine).foregroundStyle(Color.ink2).frame(width: 190, alignment: .leading).lineLimit(1)
                                Text(e.title).font(Theme.fine).foregroundStyle(e.outcome == .error ? Color.stop : Color.ink).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(app.logSel == e.id ? Color.ink.opacity(0.06) : Color.clear)
                            .overlay(alignment: .leading) { if app.logSel == e.id { Rectangle().fill(Color.doing).frame(width: 2) } }
                            .contentShape(Rectangle())
                            .onTapGesture { app.logSel = e.id }
                        }
                    }
                }
                Rectangle().fill(Color.line).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let e = sel {
                            Text(e.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                            Text(([e.route, e.outcome.word, e.at] + (e.turn.map { ["turn \($0)"] } ?? [])).joined(separator: " · ")).font(Theme.fine).foregroundStyle(Color.ink3)
                            if !e.detail.isEmpty { Text(e.detail).font(Theme.mono(11)).foregroundStyle(Color.ink2).textSelection(.enabled) }
                        } else {
                            Text("Select an event").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                            Text("Select an event to see its detail. The newest are at the top.").font(Theme.fine).foregroundStyle(Color.ink3)
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 320)
            }
        }
    }
}

/// Admin › Feed (feed.js): everything A's screen shows, pushed to a URL. One way only.
struct FeedView: View {
    @EnvironmentObject var app: AppModel
    @State private var url = ""

    var body: some View {
        let s = app.session
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("A's feed").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                Text("Everything A's screen shows is also sent to this URL: each request as it arrives, every verdict and outcome, what \(s.bName) does, the clock at each phase change, each reminder, and the assistant's brief. One way only: the app sends and never reads a reply or takes a command.")
                    .font(Theme.body).foregroundStyle(Color.ink2)
                HStack(spacing: 8) {
                    TextField("https://example.com/a-feed", text: $url).textFieldStyle(.roundedBorder).frame(maxWidth: 420).onAppear { url = app.feedURL }.onSubmit(save)
                    Button("Save", action: save).buttonStyle(MPMButtonStyle(kind: .primary))
                    Button("Turn off") { app.setFeed(url: url, on: false) }.buttonStyle(MPMButtonStyle(kind: .plain)).disabled(!app.feedOn)
                    Button("Send a test") { app.feedTest() }.buttonStyle(MPMButtonStyle(kind: .plain)).disabled(!app.feedOn)
                }
                Text(stateLine()).font(Theme.fine).foregroundStyle(Color.ink2)
                ForEach(app.feedLog.reversed()) { x in
                    HStack(spacing: 8) {
                        Text(Format.stamp(x.atMs)).font(Theme.mono(10)).foregroundStyle(Color.ink3)
                        Text(x.kind).font(Theme.fine).foregroundStyle(Color.ink)
                        Text(x.ok ? "sent" : x.why).font(Theme.fine).foregroundStyle(x.ok ? Color.done : Color.stop)
                    }
                }
                Text("Each message is one POST with a JSON body: { v, seq, kind, at, session, round, state, frozen, left, names, data }. Kinds: hello, test, session, phase, reminder, request, verdict, outcome, note, brief. The body is sent as text/plain, and the reply is not read.")
                    .font(Theme.fine).foregroundStyle(Color.ink3)
            }
            .padding(16).frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func save() {
        if !AppModel.feedUrlOk(url.trimmingCharacters(in: .whitespaces)) { app.showToast("A URL starting with http:// or https://", error: true); return }
        app.setFeed(url: url, on: true)
    }

    private func stateLine() -> String {
        if app.feedURL.isEmpty { return "No URL yet. Nothing is sent." }
        if !app.feedOn { return "Off. Nothing is sent." }
        guard let last = app.feedLog.last else { return "On. Waiting for the first thing to send." }
        return (last.ok ? "On. Last sent \(Format.stamp(last.atMs)) (\(last.kind))." : "On, but the last send failed: \(last.why).") + (app.feedFails > 1 ? " \(app.feedFails) failed in a row." : "")
    }
}
