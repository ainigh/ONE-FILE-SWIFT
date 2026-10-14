import Foundation

// The session (state.js, engine.js, voice.js): one object drives everything: the session engine,
// the store and its patch log, the assistant's turn, the request log, and the host events the
// Monitor and the Log show. Every phase change is a Request: B asks (or the System raises one when
// a clock runs out), policy or a person in the A role decides, and B presses Go. Only two things
// change a clock: the System reaching the end of a phase, and B's Go on an approved request.

public struct RoundInfo {
    public var start: [NodeID: DisplayStatus]
    public var end: [NodeID: DisplayStatus]?
}

public struct Strip: Equatable {
    public var text: String
    /// Monotonic milliseconds.
    public var until: Double
}

public struct Names: Equatable {
    public var b = ""
    public var a = ""
    public init(b: String = "", a: String = "") { self.b = b; self.a = a }
}

public enum SoundKind { case tick, start, timeup, stop }

public final class Session {
    // MARK: Settings the engine reads
    public var cfg: SessionConfig
    public var nextCfg: SessionConfig?
    /// A: the policy answers at once (autopilot), or a person decides.
    public var auto = true
    public var voice: VoiceStyle = .rich
    public var names = Names()
    public var modelOn = true
    /// Clocks run in real time; a developer may run them faster while testing.
    public var speed = 1.0
    /// How long B has already been sitting when a session opens, in seconds.
    public var seatStart = 0.0

    // MARK: Hooks the app fills
    /// What the engine says, and the detail the log keeps.
    public var onSay: ((String, String) -> Void)?
    public var onSound: ((SoundKind) -> Void)?
    public var onFeed: ((FeedMessage) -> Void)?
    public var onSavePlan: ((PlanSnapshot) -> Bool)?
    public var onSaveSettings: (() -> Void)?
    public var onEvent: ((Event) -> Void)?
    public var onToast: ((String, Bool) -> Void)?
    /// A request was decided: the app may show it to B, speak it, or notify A.
    public var onRequestDecided: ((Request) -> Void)?

    // MARK: Clocks
    /// Session time, seconds.
    public internal(set) var T = 0.0
    /// Wall-clock time, milliseconds (advances with the session, so a fast clock stays consistent).
    public internal(set) var W: Double
    public internal(set) var state: Phase?
    public internal(set) var frozen = false
    /// What the clock read when it ended.
    public internal(set) var reading = 0.0
    public internal(set) var round = 0
    public internal(set) var roundStart = 0.0
    public internal(set) var roundRun = 0.0
    public internal(set) var phaseStart = 0.0
    public internal(set) var phaseEnd = 0.0
    public internal(set) var z = 0
    public internal(set) var x: Int?
    public internal(set) var statusLen = 0.0
    public internal(set) var seated = 0.0
    var remFired = 0
    /// The last reminder, while its cover shows.
    public internal(set) var lastRem: Double?
    var halfFired = false

    // MARK: The plan
    public internal(set) var nodes: [NodeID: Node] = [:]
    var seq = 0
    var doneAt: [NodeID: Double] = [:]
    public internal(set) var pn = 0
    var undoStack: [PatchRecord] = []
    var redoStack: [PatchRecord] = []
    public var picks = Pair()
    public var selected: NodeID?
    public internal(set) var diff: [DiffLine] = []
    public internal(set) var prevPair: (d: String?, n: String?) = (nil, nil)
    public internal(set) var planChosen = false
    public internal(set) var rounds: [Int: RoundInfo] = [:]

    // MARK: The assistant
    public internal(set) var held: Held?
    public internal(set) var turn: Turn?
    var turnSeq = 0
    var propSeq = 0
    var nudged = false

    // MARK: Requests
    public internal(set) var requests: [Request] = []
    var reqSeq = 0
    var reqId: String?
    var sysId: String?
    public internal(set) var sessionId = ""
    var sessionSeq = 0

    // MARK: Events and what the screens show
    public internal(set) var events: [Event] = []
    var evId = 0
    public internal(set) var unseen: [Part: Int] = [:]
    public internal(set) var logsV = 0
    var notes: [Note] = []
    public internal(set) var announce = ""
    public internal(set) var strip: Strip?
    var feedSeq = 0
    public var intake = Intake(stage: .name, ids: [])

    public init(cfg: SessionConfig = .default, now: Date = Date()) {
        self.cfg = cfg
        self.W = now.timeIntervalSince1970 * 1000
        self.intake = Intake(stage: .name, ids: [])
    }

    /// Monotonic milliseconds, for things that fade.
    public func mono() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    func toast(_ t: String, info: Bool = false) { onToast?(t, info) }

    // MARK: The voice

    func say(_ t: String, _ detail: String = "") {
        announce = t
        ev(.engine, .output, .ok, t, detail)
        onSay?(t, detail)
    }

    public var bName: String { names.b.isEmpty ? "B" : names.b }
    public var aName: String { names.a.isEmpty ? "A" : names.a }

    func ctxBase() -> AnnounceContext {
        var c = AnnounceContext()
        c.sessionId = sessionId; c.round = round; c.R = cfg.R; c.q = cfg.q; c.Lb = cfg.Lb; c.Ls = cfg.Ls; c.Zmax = cfg.zMax; c.z = z; c.x = x
        c.aName = aName; c.bName = bName; c.seated = seated
        c.doing = title(slot(.doing)); c.next = title(slot(.next)); c.prevDoing = prevPair.d; c.prevNext = prevPair.n
        return c
    }

    func phrase(_ trigger: String, _ ctx: AnnounceContext, _ fallback: String, voice v: VoiceStyle? = nil) -> (text: String, detail: String) {
        var c = ctxBase()
        // The caller's fields win.
        if ctx.round != nil { c.round = ctx.round }
        if ctx.doing != nil { c.doing = ctx.doing }
        if ctx.next != nil { c.next = ctx.next }
        if ctx.prevDoing != nil { c.prevDoing = ctx.prevDoing }
        if ctx.seated != nil { c.seated = ctx.seated }
        if ctx.x != nil { c.x = ctx.x }
        c.elapsed = ctx.elapsed; c.remaining = ctx.remaining; c.statusLen = ctx.statusLen; c.reminderIndex = ctx.reminderIndex; c.reminderCount = ctx.reminderCount
        c.diff = ctx.diff; c.held = ctx.held; c.heldKnown = ctx.heldKnown; c.chosen = ctx.chosen; c.reason = ctx.reason; c.openCount = ctx.openCount
        c.what = ctx.what; c.toPhase = ctx.toPhase; c.n = ctx.n; c.len = ctx.len
        if ctx.R != nil { c.R = ctx.R }
        let use = v ?? voice
        let r = Announce.phrase(trigger, c, voice: use)
        let detail = "trigger \(trigger), variant \(r.variant)" + (r.variant == 0 ? " (the spec's wording)" : "") + (r.tail >= 0 ? "\ntail \(r.tail)" : "") + "\nvoice \(use.rawValue)"
        return (r.text, detail)
    }

    @discardableResult
    func speak(_ trigger: String, _ ctx: AnnounceContext, _ fallback: String, prefix: String? = nil) -> String {
        let r = phrase(trigger, ctx, fallback)
        say((prefix.map { $0 + " " } ?? "") + r.text, r.detail)
        return announce
    }

    public func setVoice(_ v: VoiceStyle) {
        if v == voice { return }
        voice = v
        onSaveSettings?()
        ev(.man, .output, .info, "voice: \(v.rawValue)", v == .fixed ? "the spec's wording only" : v == .varied ? "another sentence with the same facts" : "varied, with a tail on what the numbers mean")
    }

    // MARK: Phases and clocks (engine.js)

    public func running() -> Bool { state != nil && state != .idle && !frozen }

    public func phaseLen() -> Double {
        switch state {
        case .work: return cfg.R
        case .snooze: return cfg.q
        case .status: return statusLen
        case .strategy: return cfg.q
        case .break: return cfg.Lb
        default: return 0
        }
    }

    public func left() -> Double { running() ? max(0, phaseEnd - T) : 0 }

    func enter(_ st: Phase, _ len: Double = 0) {
        state = st; frozen = false; phaseStart = T; phaseEnd = T + len; lastRem = nil; strip = nil; halfFired = false
        pushA("phase", .object(["phase": .string(st.title), "length": .number(len), "ends_at": len > 0 ? .string(Format.iso(W + len * 1000)) : .null,
                                "doing": .opt(title(slot(.doing))), "next": .opt(title(slot(.next))), "seated": .int(Int(seated.rounded()))]))
    }

    func halfLine(_ len: Double) -> String { "half-time reminder at \(Format.digits(len / 2)) left" }
    func snap() -> [NodeID: DisplayStatus] { var o: [NodeID: DisplayStatus] = [:]; for k in nodes.keys { o[k] = displayStatus(k) }; return o }
    public func sitBreak() -> Bool { seated + cfg.R > cfg.Ls }
    /// x comes from the log (§6.6.1): steps marked done between this round's Go and the Go that ended it.
    public func roundCleared() -> Int { doneAt.filter { nodes[$0.key] != nil && $0.value >= roundStart && finished($0.key) }.count }

    public func startSession() {
        if state != nil { return }
        if let n = nextCfg { cfg = n; nextCfg = nil }
        round = 0; z = 0; x = nil; held = nil; turn = nil; nudged = false; diff = []; rounds = [:]
        seated = seatStart; reqId = nil; sysId = nil; prevPair = (nil, nil)
        sessionSeq += 1
        sessionId = "s\(sessionSeq)-\(Int(W / 1000))"
        ev(.man, .engine, .info, "open session", "seated \(Format.fmt(seated)), R \(Format.fmt(cfg.R)), r \(cfg.r), Ls \(Format.fmt(cfg.Ls)), Lb \(Format.fmt(cfg.Lb))\nA: " + (auto ? "policy (autopilot)" : "a person"))
        enter(.idle)
        say("Session open.")
        pushA("session", .object(["event": .string("open"), "R": .number(cfg.R), "r": .int(cfg.r), "Ls": .number(cfg.Ls), "Lb": .number(cfg.Lb), "auto": .bool(auto)]))
    }

    public func endSession() {
        if state == nil { return }
        closeReq(reqId, .overtaken); closeReq(sysId, .overtaken)
        ev(.engine, .timers, .info, "cancel timers", "")
        say("Session ended.", "rounds \(round), requests \(requests.count)")
        pushA("session", .object(["event": .string("end"), "rounds": .int(round), "requests": .int(requests.count)]))
        state = nil; frozen = false; reqId = nil; sysId = nil; held = nil; turn = nil; picks = Pair()
        diff = []; lastRem = nil; strip = nil
        intake = Intake(stage: firstStage(), ids: [])
    }

    func startRound() {
        round += 1; roundStart = T; roundRun = 0; z = 0; x = nil; remFired = 0; picks = Pair(); diff = []; held = nil
        rounds[round] = RoundInfo(start: snap(), end: nil)
        enter(.work, cfg.R)
        ev(.engine, .timers, .info, "schedule \(cfg.r) reminders and the round end", "reminders at " + cfg.remTimes.map(Format.digits).joined(separator: ", ") + " left\nround end " + Format.stamp(W + cfg.R * 1000))
        speak("round_start", AnnounceContext(), "Round \(round). \(title(slot(.doing)) ?? "nothing") doing, \(title(slot(.next)) ?? "nothing") next. \(Format.fmt(cfg.R)), starting now.")
        prevPair = (title(slot(.doing)), title(slot(.next)))
        onSound?(.start)
    }

    func startSnooze() {
        z += 1
        enter(.snooze, cfg.q)
        ev(.engine, .timers, .info, "schedule snooze end", "snooze end \(Format.stamp(W + cfg.q * 1000))\nthe snooze clock starts at Go, so it is always \(Format.fmt(cfg.q))\n" + halfLine(cfg.q))
        speak("snooze_accepted", AnnounceContext(), "Snooze \(z) of \(cfg.zMax). \(Format.fmt(cfg.q)).")
    }

    func startStatus() {
        let xx = roundCleared()
        var d: [DiffLine] = []
        let base = rounds[round]?.start ?? [:]
        for j in nodes.keys.sorted() {
            let now = displayStatus(j), was = base[j] ?? .new
            if was != now { d.append(DiffLine(nodes[j]!.title, was, now)) }
        }
        x = xx; diff = d
        rounds[round]?.end = snap()
        let len = cfg.awayFor(z: z, x: xx)
        statusLen = len
        enter(.status, len)
        ev(.engine, .timers, .info, "schedule check-up end", "check-up \(Format.fmt(len)) = \(Format.fmt(cfg.q)) × 2^\(z + 1) ÷ \(xx + 1)\nends \(Format.stamp(W + len * 1000))\n" + halfLine(len))
        var c = AnnounceContext(); c.elapsed = roundRun; c.statusLen = len; c.x = xx; c.diff = d
        speak("checkup_start", c, "Round over at \(Format.fmt(roundRun)). Check-up, \(Format.fmt(len)).")
        onSound?(.stop)
        startTurn()
        // Initiative (SPEC §8.2): a nudge found while a session runs is folded into the turn, not shown.
        let stale = staleSteps()
        if !nudged && !stale.isEmpty {
            nudged = true
            ev(.scheduler, .coordinator, .warning, "nudge deferred: session running", "rule untouched_5d, " + stale.compactMap(title).joined(separator: ", ") + "; folded into this phase's projection")
        }
    }

    func startStrategy() {
        if let t = turn, !t.done { abandonTurn() }
        enter(.strategy, cfg.q)
        ev(.engine, .timers, .info, "schedule plan end", "plan end \(Format.stamp(W + cfg.q * 1000))\n" + halfLine(cfg.q))
        picks = Pair()
        if let h = held, !h.props.isEmpty || h.say != nil {
            ev(.engine, .coordinator, .info, "render held output", "", turn: turn?.id)
            ev(.coordinator, .output, .ok, "say and \(h.props.count) proposal(s) shown", h.props.map(\.text).joined(separator: "\n"), turn: turn?.id)
            if let b = h.brief {
                ev(.coordinator, .a, .ok, "brief shown to A", b.text + "\n" + b.forA, turn: turn?.id)
                pushA("brief", .object(["text": .string(b.text), "forA": .string(b.forA)]))
            }
        }
        var c = AnnounceContext()
        c.heldKnown = true
        if let h = held, !h.thinking, !h.failed { c.held = HeldInfo(say: h.say != nil, proposals: h.props.count) }
        speak("plan_start", c, "Plan round \(round + 1), \(Format.fmt(cfg.q)).")
    }

    func startBreak() {
        enter(.break, cfg.Lb)
        ev(.engine, .timers, .info, "schedule break end", "break end \(Format.stamp(W + cfg.Lb * 1000))\n" + halfLine(cfg.Lb))
        var c = AnnounceContext(); c.seated = seated
        speak("break_start", c, "Seated \(Format.fmt(seated)). Movement break, \(Format.fmt(cfg.Lb)).")
    }

    func resetIfMoved(_ len: Double) {
        if len >= cfg.Lb { seated = 0; ev(.engine, nil, .info, "seated time reset", "a check-up of \(Format.fmt(len)) counts as moving") }
    }

    /// The clock you are in stops at the instant the next one starts: at Go.
    func leave() {
        guard !frozen, let st = state, st != .idle else { return }
        let ran = T - phaseStart
        if st == .work || st == .snooze { roundRun += ran }
        else if st == .status { resetIfMoved(ran) }
        else if st == .break { seated = 0; ev(.engine, nil, .info, "seated time reset", "break") }
        ev(.engine, .timers, .info, "cancel \(st.title.lowercased()) timers", "stopped at Go after \(Format.fmt(ran))")
    }

    func commitNow() {
        var p = commitPair()
        if let why = validateCommit(p.d, p.n) {
            p = autoPair()
            ev(.engine, nil, .warning, "pair no longer valid at Go: auto-commit", why)
        }
        guard let d = p.d else { return }
        ev(.man, .engine, .info, "commit(doing: \(title(d) ?? ""), next: \(title(p.n) ?? "nothing"))", "at Go")
        apply(.engine, pairOps(d, p.n), why: "commit")
        picks = Pair()
    }

    func go(_ r: Request) {
        let to = r.to, from = state, wasFrozen = frozen
        leave()
        switch to {
        case .end: endSession()
        case .snooze: startSnooze()
        case .status: startStatus()
        case .strategy: startStrategy()
        case .work, .break:
            if (from == .idle || from == .strategy) && !wasFrozen { commitNow() }
            if to == .break { startBreak() } else { startRound() }
        }
    }

    /// The System reaches the end of a phase: the clock stops, the session freezes, and the System
    /// raises the request for what comes next, approved by policy. Nothing runs until B presses Go.
    func clockEnded() {
        guard let st = state else { return }
        let len = phaseLen()
        if st == .work || st == .snooze { roundRun += len }
        frozen = true; reading = len; lastRem = nil; strip = nil
        ev(.timers, .engine, .info, "tick: \(st.title.lowercased()) end", "the clock stops; frozen until B presses Go")
        pushA("phase", .object(["phase": .string(st.title + " ended"), "length": .number(len), "ends_at": .null, "reading": .number(len)]))
        closeReq(reqId, .overtaken); reqId = nil
        if st == .work || st == .snooze {
            speak("time_up", AnnounceContext(), "Time's up."); onSound?(.timeup)
            sysRaise(.status)
        } else if st == .status {
            resetIfMoved(statusLen)
            if let t = turn, !t.done { abandonTurn() }
            say("Check-up over.")
            sysRaise(.strategy)
        } else if st == .strategy {
            var p = commitPair()
            var chosen = picks.d != nil || picks.n != nil
            if validateCommit(p.d, p.n) != nil { p = autoPair(); chosen = false }
            guard let d = p.d else { say("No open steps left."); endSession(); return }
            ev(.engine, nil, .info, chosen ? "plan over: B's pair kept" : "auto-commit", "doing \(title(d) ?? ""), next \(title(p.n) ?? "nothing")")
            apply(.engine, pairOps(d, p.n), why: chosen ? "commit at plan end" : "auto-commit")
            picks = Pair(); planChosen = chosen
            var c = AnnounceContext(); c.chosen = chosen; c.doing = title(d); c.next = title(p.n)
            speak("plan_over", c, "Planning over.")
            sysRaise(sitCheck() ? .break : .work)
        } else if st == .break {
            seated = 0
            var c = AnnounceContext(); c.round = round + 1
            speak("break_end", c, "Sitting clock reset.")
            sysRaise(.work)
        }
    }

    /// The sit check, before every round but the first: one more round would pass the sitting limit?
    func sitCheck() -> Bool {
        let b = sitBreak()
        if b { ev(.engine, nil, .info, "sit check: break first", "seated \(Format.fmt(seated)) + round \(Format.fmt(cfg.R)) > \(Format.fmt(cfg.Ls))") }
        else { var c = AnnounceContext(); c.seated = seated; speak("continue", c, "Seated \(Format.fmt(seated)). Continue.") }
        return b
    }

    public func tick() {
        guard running(), let st = state else { return }
        if st == .work {
            let lf = phaseEnd - T, R = cfg.remTimes
            while remFired < R.count && lf <= R[remFired] {
                let t = R[remFired], i = remFired
                remFired += 1
                ev(.timers, .engine, .info, "tick: reminder \(Format.digits(t))", "")
                var c = AnnounceContext(); c.remaining = t; c.reminderIndex = i; c.reminderCount = R.count
                speak("reminder", c, "\(Format.fmt(t)) left.")
                onSound?(.tick)
                pushA("reminder", .object(["text": .string("\(Format.fmt(t)) left."), "remaining": .int(Int(t.rounded())), "index": .int(i), "count": .int(R.count), "last": .bool(i == R.count - 1)]))
                // The first r−1 reminders fade on their own; the last one covers the screen (default 32).
                if i < R.count - 1 { strip = Strip(text: "\(Format.fmt(t)) left.", until: mono() + 4000) }
                else { lastRem = t; strip = nil; ev(.engine, .output, .info, "last reminder: cover", "the clock keeps running") }
            }
        }
        if st != .work && !halfFired {
            let len = phaseLen(), half = len / 2, lh = phaseEnd - T
            if len > 0 && lh <= half && lh > 0 {
                halfFired = true
                ev(.timers, .engine, .info, "tick: half-time reminder \(Format.digits(half))", "\(st.title.lowercased()) of \(Format.fmt(len)); not from the reminder arithmetic")
                var c = AnnounceContext(); c.remaining = half; c.reminderIndex = 0; c.R = len
                speak("reminder", c, "\(Format.fmt(half)) left, halfway.")
                onSound?(.tick)
                pushA("reminder", .object(["text": .string("\(Format.fmt(half)) left, halfway."), "remaining": .int(Int(half.rounded())), "halfway": .bool(true)]))
                strip = Strip(text: "\(Format.fmt(half)) left, halfway.", until: mono() + 4000)
            }
        }
        if st == .status, let t = turn, !t.done, T >= t.answerAt { modelAnswer() }
        if T >= phaseEnd { clockEnded() }
    }

    // MARK: The clock loop

    func rate() -> Double { state == .strategy && !frozen ? min(4, speed) : speed }

    /// Real seconds have passed: step the session through them. Long gaps (the Mac slept) are
    /// stepped in chunks so every reminder and phase end fires in order.
    public func advance(real: Double) {
        guard real > 0 else { return }
        if state != nil {
            var dt = real * rate()
            while dt > 0 {
                let step = min(dt, 0.5)
                dt -= step
                T += step; W += step * 1000
                // The sitting clock is not a phase clock: it runs in every state but idle and the break, freezes included.
                if frozen || (state != .idle && state != .break) { seated += step }
                tick()
                if state == nil { W += dt * 1000; break }
            }
        } else {
            W += real * 1000
        }
    }

    /// Settings saved from the sheet: the numbers apply at the next session when one runs.
    public func saveSettings(cfg c: SessionConfig, model: Bool, voice v: VoiceStyle, namesB: String, namesA: String) {
        let changed = c != cfg
        if changed { if state != nil { nextCfg = c } else { cfg = c; nextCfg = nil } } else { nextCfg = nil }
        modelOn = model; voice = v
        if namesB != names.b { setName(.b, namesB) }
        if namesA != names.a { setName(.a, namesA) }
        if intake.stage == .name && !names.b.isEmpty { intake.stage = .time }
        onSaveSettings?()
        ev(.man, .engine, .info, "settings saved", "R \(Format.fmt(c.R)), r \(c.r), Ls \(Format.fmt(c.Ls)), Lb \(Format.fmt(c.Lb))\nassistant \(model ? "built-in" : "none"), voice \(v.rawValue)" + (changed && state != nil ? "\napplies at the next session" : ""))
    }

    public func setSeatStart(minutes: Double) {
        seatStart = max(0, min(240, minutes.rounded())) * 60
        onSaveSettings?()
    }

    public func schedulerNote(_ at: String, _ why: String) {
        ev(.scheduler, .output, .info, "scheduled: \(why)", "set for \(at)")
        toast("\(at) · \(why)", info: true)
    }
}
