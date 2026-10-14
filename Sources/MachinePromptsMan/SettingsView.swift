import MPMCore
import SwiftUI

/// The Settings sheet (settings.js): session, assistant, general and schedule. Saved on this Mac.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var cfg = SessionConfig.default
    @State private var minutes = "10"
    @State private var model = true
    @State private var voice: VoiceStyle = .rich
    @State private var nameB = ""
    @State private var nameA = ""
    @State private var clearArmed = false
    @State private var newAt = "09:00"
    @State private var newWhy = ""

    var body: some View {
        let s = app.session
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink)
                Spacer()
                Button("Close") { app.settingsOpen = false }.buttonStyle(LinkishStyle())
            }
            .padding(16)
            Seg(items: [(SettingsTab.session, "Session"), (.model, "Assistant"), (.general, "General"), (.schedule, "Schedule")], selection: $app.settingsTab)
                .padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch app.settingsTab {
                    case .session: sessionTab(s)
                    case .model: modelTab
                    case .general: generalTab(s)
                    case .schedule: scheduleTab
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Color.line).frame(height: 1)
            HStack {
                Spacer()
                if app.settingsTab == .schedule {
                    Button("Done") { app.settingsOpen = false }.buttonStyle(MPMButtonStyle(kind: .small))
                } else {
                    Button("Revert") { load(s) }.buttonStyle(MPMButtonStyle(kind: .small))
                    Button("Save") {
                        s.saveSettings(cfg: cfg, model: model, voice: voice, namesB: nameB, namesA: nameA)
                        app.saveSettings()
                        app.settingsOpen = false
                    }.buttonStyle(MPMButtonStyle(kind: .smallPrimary))
                }
            }
            .padding(12)
        }
        .frame(width: 620, height: 560)
        .background(Color.bg)
        .onAppear { load(s) }
    }

    private func load(_ s: Session) {
        cfg = s.nextCfg ?? s.cfg
        minutes = String(Int(cfg.R / 60))
        model = s.modelOn
        voice = s.voice
        nameB = s.names.b
        nameA = s.names.a
        clearArmed = false
    }

    @ViewBuilder
    private func sessionTab(_ s: Session) -> some View {
        kv("Round length", "Whole minutes of work before a check-up, 1 to 120. Also asked at the intake.") {
            TextField("10", text: $minutes).textFieldStyle(.roundedBorder).frame(width: 60)
                .onSubmit { if let m = Int(minutes), m >= 1, m <= 120 { cfg.R = Double(m * 60) } else { minutes = String(Int(cfg.R / 60)) } }
                .onChange(of: minutes) { _, v in if let m = Int(v), m >= 1, m <= 120 { cfg.R = Double(m * 60) } }
        }
        kv("Reminders per round", "Also the number of snoozes a round allows.") { Seg(items: [(2, "2"), (3, "3"), (4, "4")], selection: $cfg.r) }
        kv("Sitting limit", "Minutes seated before a movement break is due.") { Seg(items: [(1800.0, "30"), (2700, "45"), (3600, "60")], selection: $cfg.Ls) }
        kv("Movement break", "Minutes away from the desk.") { Seg(items: [(120.0, "2"), (180, "3"), (300, "5")], selection: $cfg.Lb) }
        Rectangle().fill(Color.line).frame(height: 1)
        Text("What follows").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        kv("Snooze and plan length", "The base unit: the round split in half, \(cfg.r) times.") { Text(Format.digits(cfg.q)).font(Theme.mono(13)).foregroundStyle(Color.ink) }
        kv("Reminders at", "Time left when each one shows. The last covers the screen.") { Text(cfg.remTimes.map(Format.digits).joined(separator: ", ")).font(Theme.mono(13)).foregroundStyle(Color.ink) }
        VStack(alignment: .leading, spacing: 4) {
            Text("Check-up length, by snoozes taken (rows) and steps cleared (columns)").font(Theme.fine).foregroundStyle(Color.ink2)
            Grid(horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow { Label2("snoozes \\ cleared"); ForEach(0..<4, id: \.self) { Label2("\($0)") } }
                ForEach(0...cfg.r, id: \.self) { z in
                    GridRow {
                        Label2("\(z)")
                        ForEach(0..<4, id: \.self) { x in Text(Format.fmt(cfg.awayFor(z: z, x: x))).font(Theme.mono(12)).foregroundStyle(Color.ink) }
                    }
                }
            }
        }
        Text("There is no grace window: at time's up the clock holds until you press Go or Snooze. " + (s.state != nil ? "Changes apply at the next session." : "Changes apply when the next session opens."))
            .font(Theme.fine).foregroundStyle(Color.ink3)
    }

    private var modelTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            radio("Built-in assistant", "At each check-up it reads your plan: a note and a few suggestions for you at planning, and a short brief for A.", on: model) { model = true }
            radio("None", "Rounds run exactly the same, with no notes or suggestions.", on: !model) { model = false }
            Text("The assistant takes one turn per round, during the check-up, and never decides a request or starts a clock. Steps you lock are never suggested.").font(Theme.fine).foregroundStyle(Color.ink3)
        }
    }

    @ViewBuilder
    private func generalTab(_ s: Session) -> some View {
        Text("Announcements").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        radio("Rich", "A different sentence now and then, and often a second one on what the numbers mean for you right now. The request screen never varies.", on: voice == .rich) { voice = .rich }
        radio("Varied", "Same facts and numbers, a different sentence now and then; one sentence at a time.", on: voice == .varied) { voice = .varied }
        radio("Fixed", "Always the same wording, word for word.", on: voice == .fixed) { voice = .fixed }
        Rectangle().fill(Color.line).frame(height: 1)
        Text("Sound and voice").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        Toggle(isOn: Binding(get: { app.muted }, set: { app.setMuted($0) })) {
            VStack(alignment: .leading) { Text("Mute sounds").font(Theme.body).foregroundStyle(Color.ink); Text("Four short tones: round start, each reminder, time's up and the check-up.").font(Theme.fine).foregroundStyle(Color.ink3) }
        }
        Toggle(isOn: Binding(get: { app.voiceOn }, set: { app.setVoiceOn($0) })) {
            VStack(alignment: .leading) { Text("Spoken confirmations").font(Theme.body).foregroundStyle(Color.ink); Text("Every confirmation for B is spoken out loud (also under Admin). On by default.").font(Theme.fine).foregroundStyle(Color.ink3) }
        }
        HStack(spacing: 10) {
            Text("Voice").font(Theme.body).foregroundStyle(Color.ink)
            Picker("", selection: Binding(get: { VoiceSettings.voice.id }, set: { VoiceSettings.voice = NeuralVoice.named($0) })) {
                ForEach(NeuralVoice.all, id: \.id) { v in Text(VoiceSettings.label(v)).tag(v.id) }
            }.labelsHidden().frame(width: 180)
            Button("Hear it") { Speaker.preview() }.buttonStyle(MPMButtonStyle(kind: .small))
            if let st = Neural.status(Neural.shared.voices, what: "the voices") { Text(st).font(Theme.fine).foregroundStyle(Color.ink3) }
        }
        Rectangle().fill(Color.line).frame(height: 1)
        Text("Names").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        kv("B", "The one working. The screens say this instead of B.") { TextField("B", text: $nameB).textFieldStyle(.roundedBorder).frame(width: 160) }
        kv("A", "The one answering. The screens say this instead of A.") { TextField("A", text: $nameA).textFieldStyle(.roundedBorder).frame(width: 160) }
        Rectangle().fill(Color.line).frame(height: 1)
        Text("Your plan").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        let steps = s.nodes.values.filter { !$0.root }.count
        kv("Stored on this Mac", steps > 0 ? "\(Format.n(steps, "step", "steps")). Clearing cannot be undone." : "Your steps are kept here between launches.") {
            if s.state != nil { Text("End the session first.").font(Theme.fine).foregroundStyle(Color.ink3) }
            else if steps == 0 { Text("Nothing to clear.").font(Theme.fine).foregroundStyle(Color.ink3) }
            else if !clearArmed { Button("Clear the plan…") { clearArmed = true }.buttonStyle(MPMButtonStyle(kind: .small)) }
            else {
                HStack {
                    Button("Remove \(Format.n(steps, "step", "steps"))") { s.clearPlan(); clearArmed = false; app.folded = [] }.buttonStyle(MPMButtonStyle(kind: .danger))
                    Button("Keep") { clearArmed = false }.buttonStyle(MPMButtonStyle(kind: .small))
                }
            }
        }
        Rectangle().fill(Color.line).frame(height: 1)
        Text("This copy").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
        Text(Updater.versionLine).font(Theme.fine).foregroundStyle(Color.ink2)
        if let u = app.updater, Updater.isInstalledApp {
            HStack(spacing: 8) {
                switch u.state {
                case .idle, .upToDate: Button("Check for Updates…") { u.check(userInitiated: true) }.buttonStyle(MPMButtonStyle(kind: .small))
                case .checking: Text("Checking for Updates…").font(Theme.fine).foregroundStyle(Color.ink3)
                case .available(let plan):
                    let title: String = {
                        switch plan {
                        case let .prebuilt(c, r): return "Update to \(r.tag) — \(c.title)"
                        case let .buildHere(c): return "Update (build here) — \(c.short): \(c.title)"
                        case .upToDate: return "Check for Updates…"
                        }
                    }()
                    Button(title) { if s.state == nil { u.install() } }.buttonStyle(MPMButtonStyle(kind: .smallPrimary)).disabled(s.state != nil)
                    if s.state != nil { Text("End the session first: updating restarts the app.").font(Theme.fine).foregroundStyle(Color.ink3) }
                case .installing(let step): Text(step).font(Theme.fine).foregroundStyle(Color.ink3)
                case .failed(let m):
                    Text(m).font(Theme.fine).foregroundStyle(Color.stop)
                    Button("Check again") { u.check(userInitiated: true) }.buttonStyle(MPMButtonStyle(kind: .small))
                }
            }
        }
    }

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Look-ins").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
            Text("At the time set, a note shows on screen and in the log while the app runs. Entries apply at once.").font(Theme.fine).foregroundStyle(Color.ink3)
            if app.schedule.isEmpty { Text("Nothing scheduled.").font(Theme.body).foregroundStyle(Color.ink2) }
            ForEach(Array(app.schedule.enumerated()), id: \.offset) { i, e in
                HStack {
                    Text(e.at).font(Theme.mono(12)).foregroundStyle(Color.ink)
                    Text(e.why).font(Theme.body).foregroundStyle(Color.ink)
                    Spacer()
                    Button("Remove") { app.removeSchedule(i) }.buttonStyle(MPMButtonStyle(kind: .small))
                }
            }
            HStack {
                TextField("09:00", text: $newAt).textFieldStyle(.roundedBorder).frame(width: 70)
                TextField("What to look at", text: $newWhy).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let at = newAt.trimmingCharacters(in: .whitespaces), why = newWhy.trimmingCharacters(in: .whitespaces)
                    guard at.range(of: "^\\d{2}:\\d{2}$", options: .regularExpression) != nil, !why.isEmpty else { app.showToast("A time like 09:00 and what to look at.", error: true); return }
                    app.addSchedule(at: at, why: why); newWhy = ""
                }.buttonStyle(MPMButtonStyle(kind: .smallPrimary))
            }
        }
    }

    private func kv<V: View>(_ k: String, _ sub: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(k).font(Theme.body).foregroundStyle(Color.ink)
                Text(sub).font(Theme.fine).foregroundStyle(Color.ink3)
            }
            Spacer()
            v()
        }
    }

    private func radio(_ k: String, _ sub: String, on: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Color.doing : Color.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(k).font(Theme.body).foregroundStyle(Color.ink)
                    Text(sub).font(Theme.fine).foregroundStyle(Color.ink3)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
