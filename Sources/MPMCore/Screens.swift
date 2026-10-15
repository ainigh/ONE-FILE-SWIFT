import Foundation

// B's screen as data (screen-b.js): which view shows, and the request component in its four
// states, as a strip (B keeps working) or a cover (nothing underneath is reachable). The app draws
// these; the core decides them, so the Mac and the page agree.

public enum BView { case intake, ready, round, plan }

public enum ScreenAction: Equatable {
    case accept(String)
    case ack(String)
    case raiseSnooze
    case dismissReminder
}

public struct ScreenButton: Equatable {
    public enum Style { case primary, plain, none }
    public var label: String
    public var style: Style
    public var action: ScreenAction?
}

public struct ScreenModel: Equatable {
    public enum Kind { case waiting, approved, refused, ended, reminder, checkup }
    public var kind: Kind
    public var tone: Tone
    public var heading: String
    public var digits: String?
    public var line: String
    public var question: String?
    public var buttons: [ScreenButton]
    public var meta: String?
    /// The digits count down live.
    public var tick = false
    /// Shows "Ask to move on" (the check-up).
    public var ask = false
    /// What the voice says when this screen appears (the request lines, fixed by the guide).
    public var spoken: String?
}

extension Session {
    public func bView() -> BView {
        guard let st = state, st != .idle else { return intake.stage == .ready ? .ready : .intake }
        if st == .strategy || st == .break { return .plan }
        return .round
    }

    /// The colour of the moment (tone()).
    public func tone() -> Tone {
        if frozen { return .stop }
        switch state {
        case .work, .snooze: return .doing
        case .status: return .ink2
        case .strategy: return .next
        case .break: return .rest
        default: return .ink2
        }
    }

    public func approvedLine(_ to: Target) -> String {
        let p = pairNow()
        let n: Int? = to == .work ? round + 1 : to == .snooze ? z + 1 : to == .strategy ? round + 1 : nil
        var c = ctxBase()
        c.toPhase = to.word; c.n = n; c.doing = title(p.d); c.next = title(p.n); c.len = cfg.awayFor(z: z, x: roundCleared())
        return Announce.phrase("request_approved", c, voice: .fixed).text
    }

    /// The request screen: one component, four states (screen guide §3.3).
    public func reqScreen(_ r: Request) -> ScreenModel {
        if r.verdict == nil {
            var c = ctxBase(); c.what = reqWhat(r)
            let l = Announce.phrase("request_waiting", c, voice: .fixed).text
            return ScreenModel(kind: .waiting, tone: .ink3, heading: "Hang tight.", digits: nil, line: l, question: nil, buttons: [],
                               meta: auto ? nil : "You answer as \(aName): open A, at the top of the window, to decide.", spoken: "Hang tight. " + l)
        }
        if r.verdict == .approved {
            let l = approvedLine(r.to)
            return ScreenModel(kind: .approved, tone: .done, heading: "Ready when you are.", digits: nil, line: l, question: nil,
                               buttons: [ScreenButton(label: "Go", style: .primary, action: .accept(r.id))], spoken: "Ready when you are. " + l)
        }
        var c = ctxBase(); c.reason = r.reason
        let l = Announce.phrase("request_refused", c, voice: .fixed).text
        return ScreenModel(kind: .refused, tone: .blocked, heading: "Not yet.", digits: nil, line: l, question: nil,
                           buttons: [ScreenButton(label: "OK", style: .primary, action: .ack(r.id))], spoken: "Not yet. " + l)
    }

    /// The clock ended: the System's request, approved by policy, waits for Go.
    public func endedScreen() -> ScreenModel? {
        guard let st = state, let r = sys else { return nil }
        var m = ScreenModel(kind: .ended, tone: .stop, heading: "", digits: Format.digits(reading), line: "", question: nil,
                            buttons: [ScreenButton(label: "Go", style: .primary, action: .accept(r.id))])
        if st == .work || st == .snooze {
            m.heading = "Time's up."; m.question = "Move on to check-up?"
            if z < cfg.zMax { m.buttons.append(ScreenButton(label: "Snooze · \(Format.fmt(cfg.q)) · \(cfg.zMax - z) left", style: .plain, action: .raiseSnooze)) }
            else { m.buttons.append(ScreenButton(label: "No snoozes left", style: .none, action: nil)) }
        } else if st == .status {
            m.tone = .next; m.heading = "Check-up over."; m.question = "Start planning round \(round + 1)?"
        } else if st == .strategy {
            m.tone = .next; m.heading = "Planning over."
            if r.to == .break {
                m.question = "Start your movement break?"
                m.line = "Seated \(Format.seatedMin(seated)). Movement break, \(Format.fmt(cfg.Lb)), then round \(round + 1)."
            } else {
                m.question = "Start round \(round + 1)?"
            }
            if !planChosen { m.line = "Keeping \(title(slot(.doing)) ?? "nothing") doing, \(title(slot(.next)) ?? "nothing") next." + (m.line.isEmpty ? "" : " " + m.line) }
        } else if st == .break {
            m.tone = .rest; m.heading = "Break over."; m.question = "Start round \(round + 1)?"
        }
        // The engine already said "Time's up." and the rest; the voice adds the question B is asked.
        m.spoken = [m.line, m.question ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return m
    }

    /// Strip or cover? B keeps working under a strip during work, snooze and plan; everywhere else
    /// (idle, check-up, the break, every freeze) the request screen covers B's whole screen.
    public func stripMode() -> Bool { (state == .work || state == .snooze || state == .strategy) && !frozen }

    public func coverModel() -> ScreenModel? {
        let st = state
        if let r = openReq, !stripMode() {
            var m = reqScreen(r)
            if frozen { m.digits = Format.digits(reading) } else if running() { m.digits = Format.digits(left()); m.tick = true }
            return m
        }
        if frozen, sys != nil { return endedScreen() }
        if st == .work, running(), let rem = lastRem {
            return ScreenModel(kind: .reminder, tone: .doing, heading: "\(Format.fmt(rem)) left.", digits: Format.digits(left()), line: "", question: nil,
                               buttons: [ScreenButton(label: "OK", style: .primary, action: .dismissReminder)], tick: true)
        }
        if st == .status, running() {
            let l = (strip != nil && mono() < strip!.until) ? strip!.text : ""
            return ScreenModel(kind: .checkup, tone: .ink2, heading: "Check-up", digits: Format.digits(left()), line: l, question: "Step away from the desk.",
                               buttons: [], tick: true, ask: true)
        }
        return nil
    }

    /// The strip at the top of B's screen: the request while B keeps working, or a reminder that fades.
    public func stripModel() -> ScreenModel? {
        let now = mono()
        if let r = openReq, stripMode() { return reqScreen(r) }
        if running(), let s = strip, now < s.until {
            return ScreenModel(kind: .reminder, tone: tone(), heading: s.text, digits: nil, line: "", question: nil, buttons: [])
        }
        return nil
    }

    /// A strip reminder about to fade (the last 700 ms).
    public func stripFading() -> Bool {
        guard let s = strip else { return false }
        return mono() > s.until - 700
    }

    public func performScreen(_ a: ScreenAction) {
        switch a {
        case .accept(let id): accept(id)
        case .ack(let id): ack(id)
        case .raiseSnooze: raise(.snooze)
        case .dismissReminder: lastRem = nil
        }
    }

    /// The one thing the screen asks for (Space).
    public func primary() {
        if let m = coverModel() {
            if let b = m.buttons.first(where: { $0.action != nil }), let a = b.action { performScreen(a) }
            return
        }
        if let s = stripModel(), let b = s.buttons.first, let a = b.action { performScreen(a); return }
        switch bView() {
        case .intake: break
        case .ready: okReady()
        case .round: nextPhase()
        case .plan: if state == .strategy { raise(.work) }
        }
    }

    /// What a step reads as on the board (board.js mapStatus): while B may pick, the picks show as
    /// Doing and Next before they are committed; otherwise the stored status.
    public func mapStatus(_ id: NodeID) -> DisplayStatus {
        guard let n = nodes[id] else { return .new }
        if n.root { return .open }
        if canPick() && !isClosed(id) {
            let p = commitPair()
            if p.d == id { return .doing }
            if p.n == id { return .next }
            return isBlocked(id) ? .blocked : .open
        }
        return displayStatus(id)
    }

    // MARK: The intake (what B types first)

    public enum IntakeStage { case name, time, ask, ready }

    public struct Intake {
        public var stage: IntakeStage
        public var ids: [NodeID]
        public init(stage: IntakeStage, ids: [NodeID]) { self.stage = stage; self.ids = ids }
    }

    public func firstStage() -> IntakeStage { names.b.isEmpty ? .name : .time }

    public func intakeQuestion() -> String {
        let ids = intake.ids.filter { nodes[$0] != nil }
        switch intake.stage {
        case .name: return "What should we call you?"
        case .time: return "How many minutes per round?"
        default: return ids.isEmpty ? "What would you like to do now?" : ids.count == 1 ? "What would you like to do next?" : "What else is on your list?"
        }
    }

    public func intakeHint() -> String {
        switch intake.stage {
        case .name: return "Optional. The screens use it where they would say B."
        case .time: return "Whole minutes, 1 to 120. Reminders come at a half, a quarter and an eighth of it; \(Int(cfg.R / 60)) is what you had."
        default: return "Press Return after each step. The first becomes Doing, the second Next."
        }
    }

    /// Return on the intake: a name (optional), the minutes, then one step per line.
    public func intakeSubmit(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        switch intake.stage {
        case .name:
            if !v.isEmpty { setName(.b, v); ev(.man, .engine, .info, "B's name: \(names.b)", "used wherever the screens speak of B") }
            intake.stage = .time
            return nil
        case .time:
            let mins = v.isEmpty ? Int(cfg.R / 60) : Int((Double(v) ?? 0).rounded())
            if !(mins >= 1 && mins <= 120) { return "Whole minutes, 1 to 120." }
            if Double(mins * 60) != cfg.R {
                cfg = SessionConfig(R: Double(mins * 60), r: cfg.r, Ls: cfg.Ls, Lb: cfg.Lb)
                nextCfg = nil
                onSaveSettings?()
                ev(.man, .engine, .info, "round length: \(Format.fmt(cfg.R))", "set at the intake; reminders at " + cfg.remTimes.map(Format.digits).joined(separator: ", ") + " left")
            }
            intake.stage = .ask
            return nil
        default:
            if v.isEmpty { return nil }
            guard let id = addChild(goal(), v) else { return nil }
            intake.ids.append(id)
            let count = intake.ids.count
            if count == 1 { picks.d = id } else if count == 2 { picks.n = id }
            if count >= 2 { intake.stage = .ready }
            ev(.man, .engine, .info, "intake line \(count): \(v)", count == 1 ? "will be Doing" : count == 2 ? "will be Next" : "an open step")
            return nil
        }
    }

    public func intakeSkipName() { intake.stage = .time }

    /// "or continue where you left off": the plan's own pair, and the Ready screen.
    public func intakeContinue() {
        let p = autoPair()
        picks = p
        intake.stage = .ready
        ev(.man, .engine, .info, "continue where you left off", "pair preselected: \(title(p.d) ?? "nothing"), \(title(p.n) ?? "nothing")")
    }

    /// "add more" on the Ready screen.
    public func intakeMore() {
        if intake.ids.count < 2 { intake.ids = [commitPair().d, commitPair().n].compactMap { $0 } }
        intake.stage = .ask
    }

    /// The Ready screen's list: Doing, Next, and the extra steps typed at the intake.
    public func readyList() -> (doing: String?, next: String?, extra: [String]) {
        let p = commitPair()
        let extra = intake.ids.dropFirst(2).filter { nodes[$0] != nil && $0 != p.d && $0 != p.n }.compactMap(title)
        return (title(p.d), title(p.n), extra)
    }

    public enum Role { case b, a }

    public func setName(_ role: Role, _ v: String) {
        let clean = v.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let cut = String(clean.prefix(30))
        if role == .b { names.b = cut } else { names.a = cut }
        onSaveSettings?()
    }
}
