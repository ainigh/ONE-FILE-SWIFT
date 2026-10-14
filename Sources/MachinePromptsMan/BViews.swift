import MPMCore
import SwiftUI

/// B's screen (screen-b.js): one view at a time (intake, Ready?, the round, the plan) with the
/// request strip above it, and the board beside it when it is open.
struct BScreen: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let v = s.bView()
        let boardOn = v == .plan || ((v == .round || v == .ready) && app.boardOpen)
        VStack(spacing: 0) {
            StripView()
            if v == .plan {
                PlanHeadView()
                Rectangle().fill(Color.line).frame(height: 1)
                BoardView()
            } else {
                HStack(spacing: 0) {
                    Group {
                        switch v {
                        case .intake: IntakeView()
                        case .ready: ReadyView()
                        default: RoundView()
                        }
                    }
                    .frame(width: boardOn ? 400 : nil)
                    .frame(maxWidth: boardOn ? 400 : .infinity, maxHeight: .infinity)
                    if boardOn {
                        Rectangle().fill(Color.line).frame(width: 1)
                        BoardView()
                    }
                }
            }
        }
    }
}

/// The strip: the request while B keeps working, or a reminder that fades.
struct StripView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        if let m = s.stripModel() {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.color(m.tone)).frame(width: 4, height: 22)
                Text(m.heading).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.ink)
                if !m.line.isEmpty { Text(m.line).font(Theme.body).foregroundStyle(Color.ink2).lineLimit(2) }
                Spacer()
                ForEach(Array(m.buttons.enumerated()), id: \.offset) { _, b in
                    if let a = b.action {
                        Button(b.label) { s.performScreen(a) }.buttonStyle(MPMButtonStyle(kind: b.style == .primary ? .smallPrimary : .small))
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Color.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
            .opacity(m.kind == .reminder && s.stripFading() ? 0.35 : 1)
        }
    }
}

/// The intake: a name (once, optional), the minutes per round, then the steps.
struct IntakeView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let s = app.session
        let ids = s.intake.ids.filter { s.nodes[$0] != nil }
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                if s.intake.stage != .name, !s.names.b.isEmpty, ids.isEmpty {
                    Text("Hi, \(s.names.b).").font(.system(size: 15)).foregroundStyle(Color.ink2)
                }
                ForEach(ids, id: \.self) { id in
                    Text(s.title(id) ?? "").font(.system(size: 15)).foregroundStyle(Color.ink2)
                }
            }
            Text(s.intakeQuestion()).font(Theme.display(26)).foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                TextField(placeholder(s), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line2, lineWidth: 1))
                    .focused($focused)
                    .onSubmit { submit(s) }
                    .onAppear { focused = true; if s.intake.stage == .time { text = String(Int(s.cfg.R / 60)) } }
                Button { submit(s) } label: { Image(systemName: "return").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(MPMButtonStyle(kind: .plain))
                    .help("Return")
                DictateButton { heard in text = heard; focused = true }
            }
            Text(s.intakeHint()).font(Theme.fine).foregroundStyle(Color.ink3)
            if s.intake.stage == .name {
                Button("or skip this") { s.intakeSkipName(); text = String(Int(s.cfg.R / 60)); focused = true }.buttonStyle(LinkishStyle(big: true))
            }
            if s.intake.stage == .ask, ids.isEmpty, s.hasSteps() {
                Button("or continue where you left off") { s.intakeContinue(); app.setBoard(true, .map) }.buttonStyle(LinkishStyle(big: true))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ s: Session) -> String {
        switch s.intake.stage {
        case .name: return "Your name"
        case .time: return String(Int(s.cfg.R / 60))
        default: return "One step, in a few words"
        }
    }

    private func submit(_ s: Session) {
        let stage = s.intake.stage
        if let err = s.intakeSubmit(text) { app.showToast(err, error: true); return }
        text = stage == .name ? String(Int(s.cfg.R / 60)) : ""
        focused = true
    }
}

/// Ready?: Doing, Next, the extra steps; OK asks to open the session and start round 1.
struct ReadyView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let list = s.readyList()
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                pairRow(list.doing ?? "Nothing yet", "doing", .doing)
                pairRow(list.next ?? "Nothing yet", "next", .next)
                ForEach(list.extra, id: \.self) { t in pairRow(t, "step", .ink3) }
            }
            Text("Ready to start?").font(Theme.display(26)).foregroundStyle(Color.ink)
            HStack(spacing: 12) {
                Button("OK") { s.okReady() }.buttonStyle(MPMButtonStyle(kind: .primary, big: true)).disabled(s.openReq != nil)
                HStack(spacing: 4) {
                    Text("or").foregroundStyle(Color.ink2)
                    Button("add more") { s.intakeMore() }.buttonStyle(LinkishStyle())
                }
                Button(app.boardOpen ? "Close the board ‹" : "Open the board ›") { app.setBoard(!app.boardOpen) }.buttonStyle(LinkishStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func pairRow(_ title: String, _ k: String, _ tone: Tone) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.color(tone)).frame(width: 8, height: 8)
            Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.ink)
            Label2(k)
        }
    }
}

/// The round: the ring, the two slots, Next phase.
struct RoundView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let st = s.state
        let len = s.phaseLen(), lf = s.left()
        let low = st == .work && lf > 0 && lf <= 60
        VStack(spacing: 22) {
            HStack {
                Text(st == .snooze ? "Snooze \(s.z) of \(s.cfg.zMax)" : "Round \(s.round)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                Spacer()
                Text("Seated \(Format.seatedMin(s.seated))").font(Theme.mono(12)).foregroundStyle(Color.ink2)
            }
            .frame(maxWidth: 300)
            ZStack {
                Ring(fraction: len > 0 ? 1 - lf / len : 1, color: st == .status ? .ink2 : .doing)
                VStack(spacing: 2) {
                    Text(Format.digits(lf)).font(Theme.mono(56, .medium)).foregroundStyle(low ? Color.stop : Color.ink)
                    Text("left").font(Theme.fine).foregroundStyle(Color.ink3)
                }
            }
            .frame(width: 240, height: 240)
            VStack(alignment: .leading, spacing: 8) {
                slot("Doing", s.title(s.slot(.doing)) ?? "—", .doing)
                slot("Next", s.title(s.slot(.next)) ?? "—", .next)
            }
            .frame(maxWidth: 300, alignment: .leading)
            HStack(spacing: 14) {
                Button("Next phase") { s.nextPhase() }
                    .buttonStyle(MPMButtonStyle(kind: .primary, big: true))
                    .disabled(s.openReq != nil || !s.running() || (st != .work && st != .snooze))
                Button(app.boardOpen ? "Close the board ‹" : "Open the board ›") { app.setBoard(!app.boardOpen) }.buttonStyle(LinkishStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func slot(_ k: String, _ v: String, _ tone: Tone) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.color(tone)).frame(width: 8, height: 8)
            Text(k).font(Theme.fine).foregroundStyle(Color.ink2).frame(width: 44, alignment: .leading)
            Text(v).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
        }
    }
}

/// Above the board while planning (and during the break): the clock and Start round n.
struct PlanHeadView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let s = app.session
        let brk = s.state == .break
        let lf = s.frozen ? 0 : s.left()
        HStack(spacing: 14) {
            Text(brk ? "Movement break" : "Plan round \(s.round + 1)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.ink)
            Text(Format.digits(lf)).font(Theme.mono(18)).foregroundStyle(!brk && !s.frozen && s.running() && lf <= 15 ? Color.stop : Color.ink2)
            Spacer()
            if !brk {
                Button("Start round \(s.round + 1)") { s.raise(.work) }
                    .buttonStyle(MPMButtonStyle(kind: .primary))
                    .disabled(s.openReq != nil || s.frozen)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Dictate a line: the microphone, written down on this Mac (Parakeet), into the field.
struct DictateButton: View {
    var onText: (String) -> Void
    @State private var listening = false
    @State private var stopWork: DispatchWorkItem?
    @State private var poll: Timer?
    @ObservedObject private var listener = DictateButton.shared

    private static let shared = Listener()

    var body: some View {
        Button {
            toggle()
        } label: {
            Image(systemName: listening ? "mic.fill" : "mic").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(listening ? Color.stop : Color.ink)
        }
        .buttonStyle(MPMButtonStyle(kind: .plain))
        .help(listening ? "Listening… click to stop" : "Dictate (the microphone; written down on this Mac)")
    }

    private func toggle() {
        let l = DictateButton.shared
        if listening { finish(); return }
        l.pauseToEnd = nil
        l.clear()
        l.start()
        listening = true
    }

    private func finish() {
        let l = DictateButton.shared
        l.stop()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            if l.on { l.stop(); return }
            if l.finishing { return }
            t.invalidate()
            let heard = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
            l.clear()
            listening = false
            if !heard.isEmpty { onText(heard) }
        }
    }
}
