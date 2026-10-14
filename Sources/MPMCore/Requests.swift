import Foundation

// Requests (requests.js, addendum §5): one record, three timestamps and a verdict. Raised by B or
// the System, decided by policy or A, accepted by B. And Doing and Next (pairs.js): picked before
// a round, committed at Go.

public enum Verdict: String, Codable { case approved, refused }
public enum RaisedBy: String, Codable { case man, system }
public enum DecidedBy: String, Codable { case policy, a }
public enum RequestOutcome: String, Codable { case accepted, overtaken, acknowledged }

public struct Policy: Equatable {
    public var verdict: Verdict
    public var reason: String
    public init(_ verdict: Verdict, _ reason: String = "") { self.verdict = verdict; self.reason = reason }
    /// "approve" / "refuse", as A's screen words it.
    public var word: String { verdict == .approved ? "approve" : "refuse" }
}

public struct Request: Identifiable, Equatable {
    public var id: String
    public var sessionId: String
    public var round: Int
    public var fromPhase: String
    public var to: Target
    public var raisedBy: RaisedBy
    /// Wall-clock milliseconds.
    public var sentAt: Double
    public var decidedAt: Double?
    public var decidedBy: DecidedBy?
    public var verdict: Verdict?
    public var reason: String = ""
    public var policy: Policy?
    public var acceptedAt: Double?
    public var outcome: RequestOutcome?
    public var label: String

    public var isOpen: Bool { outcome == nil }
    /// A's latency, in seconds; nil while it waits.
    public var aTook: Double? { decidedAt.map { ($0 - sentAt) / 1000 } }
    /// How long B took to press Go or OK, in seconds.
    public var bTook: Double? { (acceptedAt != nil && decidedAt != nil) ? (acceptedAt! - decidedAt!) / 1000 : nil }
}

public struct Pair: Equatable {
    public var d: NodeID?
    public var n: NodeID?
    public init(d: NodeID? = nil, n: NodeID? = nil) { self.d = d; self.n = n }
}

extension Session {
    // MARK: Requests

    /// The live request B raised, while it is open.
    public var openReq: Request? {
        guard let id = reqId, let r = request(id), r.outcome == nil else { return nil }
        return r
    }
    /// B's current request, open or not.
    public var req: Request? { reqId.flatMap(request) }
    /// The System's request, while the session is frozen.
    public var sys: Request? { sysId.flatMap(request) }

    public func request(_ id: String) -> Request? { requests.first { $0.id == id } }

    func mutate(_ id: String, _ f: (inout Request) -> Void) {
        guard let i = requests.firstIndex(where: { $0.id == id }) else { return }
        f(&requests[i])
    }

    public func reqLabel(_ to: Target) -> String {
        switch to {
        case .work: return "Start round \(round + 1)"
        case .snooze: return "Snooze \(z + 1) of \(cfg.zMax)"
        case .status: return "Move on to check-up"
        case .strategy: return "Start planning round \(round + 1)"
        case .break: return "Start the movement break"
        case .end: return "End the session"
        }
    }

    public func reqWhat(_ r: Request) -> String {
        switch r.to {
        case .work: return "starting round \(round + 1)"
        case .snooze: return "snooze \(z + 1) of \(cfg.zMax)"
        case .status: return "moving on to check-up"
        case .strategy: return "moving on to planning"
        case .break: return "the movement break"
        case .end: return "ending the session"
        }
    }

    func newReq(_ to: Target, _ by: RaisedBy) -> Request {
        reqSeq += 1
        let r = Request(id: "r\(reqSeq)", sessionId: sessionId, round: round,
                        fromPhase: (state?.rawValue ?? "idle") + (frozen ? " (ended)" : ""), to: to, raisedBy: by,
                        sentAt: W, label: reqLabel(to))
        requests.append(r)
        return r
    }

    /// Policy: the arithmetic made into verdicts (addendum §6).
    public func policyFor(_ to: Target) -> Policy {
        let st = state
        if to == .end {
            return st == .status ? Policy(.refused, "Finish the check-up first.") : st == .break ? Policy(.refused, "Finish the break first.") : Policy(.approved)
        }
        if to == .snooze { return z < cfg.zMax ? Policy(.approved) : Policy(.refused, "No snoozes left.") }
        if st == .status { return Policy(.refused, "Check-up has \(Format.fmt(left())) left.") }
        if st == .break { return Policy(.refused, "Break has \(Format.fmt(left())) left.") }
        if to == .work {
            let p = commitPair()
            if let why = validateCommit(p.d, p.n) { return Policy(.refused, why) }
            return Policy(.approved)
        }
        return Policy(.approved)
    }

    /// What a human A cannot approve whatever they judge: a round with no valid pair, a fourth snooze.
    public func cannotApprove(_ r: Request) -> String? {
        if r.to == .snooze && z >= cfg.zMax { return "\(bName) has no snoozes left." }
        if r.to == .work && (state == .idle || state == .strategy) && !frozen {
            let p = commitPair()
            return validateCommit(p.d, p.n)
        }
        return nil
    }

    /// B asks. The clock keeps running.
    public func raise(_ to: Target) {
        if openReq != nil || state == nil { return }
        if frozen && to != .snooze { return }
        var r = newReq(to, .man)
        r.policy = policyFor(to)
        mutate(r.id) { $0.policy = r.policy }
        reqId = r.id
        let pol = r.policy!
        ev(.man, .engine, .info, "request \(r.id): \(r.label)",
           "from \(r.fromPhase), sent \(Format.stamp(r.sentAt))\npolicy default: " + (pol.verdict == .approved ? "approve" : "refuse, “\(pol.reason)”") + "\nthe clock keeps running")
        pushA("request", feedReq(request(r.id)!))
        if auto { decide(r.id, pol.verdict, pol.reason, by: .policy) }
        else { ev(.engine, .a, .info, "request \(r.id) waits for A", r.label + "\npolicy default shown beside it") }
    }

    public func decide(_ id: String, _ verdict: Verdict, _ reason: String, by: DecidedBy) {
        guard id == reqId, var r = request(id), r.verdict == nil, r.outcome == nil else { return }
        if verdict == .approved, cannotApprove(r) != nil { return }
        r.decidedAt = W
        r.decidedBy = by
        r.verdict = verdict
        r.reason = verdict == .refused ? (reason.isEmpty ? "\(aName) said no." : reason) : ""
        let overrule = by == .a && verdict != r.policy?.verdict
        ev(by == .a ? .a : .policy, .engine, verdict == .approved ? .ok : .warning,
           "request \(r.id) \(verdict.rawValue)" + (overrule ? " (A overrules policy)" : ""),
           r.label + (r.reason.isEmpty ? "" : "\nreason: \(r.reason)") + "\ndecided by \(by.rawValue), after \(Format.fmt((r.decidedAt! - r.sentAt) / 1000))")
        // The sit check rides on the approval of the next round: the offer may be a break first.
        if verdict == .approved && r.to == .work && state == .strategy && !frozen && sitCheck() {
            r.to = .break
            r.label += ", break first"
        }
        mutate(id) { $0 = r }
        pushA("verdict", feedReq(r))
        onRequestDecided?(r)
    }

    /// The System reaches the end of a phase and raises what comes next, approved by policy.
    func sysRaise(_ to: Target) {
        var r = newReq(to, .system)
        r.policy = Policy(.approved)
        r.decidedAt = W
        r.decidedBy = .policy
        r.verdict = .approved
        mutate(r.id) { $0 = r }
        sysId = r.id
        ev(.engine, .output, .info, "System raises \(r.id): \(r.label)", "approved by policy; frozen until B presses Go")
        pushA("request", feedReq(r))
    }

    func closeReq(_ id: String?, _ outcome: RequestOutcome) {
        guard let id = id, var r = request(id), r.outcome == nil else { return }
        r.outcome = outcome
        mutate(id) { $0.outcome = outcome }
        ev(.engine, nil, outcome == .overtaken ? .warning : .info, "request \(r.id) \(outcome.rawValue)", r.label)
        pushA("outcome", feedReq(r))
    }

    /// B presses Go: the agreement. This clock stops and the next starts at the same instant.
    public func accept(_ id: String) {
        guard var r = request(id), r.verdict == .approved, r.outcome == nil else { return }
        r.acceptedAt = W
        r.outcome = .accepted
        mutate(id) { $0 = r }
        let gap = Format.fmt((r.acceptedAt! - (r.decidedAt ?? r.sentAt)) / 1000)
        ev(.man, .engine, .info, "Go: \(r.label)", (r.raisedBy == .system ? "freeze " : "confirmed after ") + gap)
        pushA("outcome", feedReq(r))
        if reqId == id { reqId = nil }
        if sysId == id { sysId = nil }
        if let s = sysId { closeReq(s, .overtaken); sysId = nil }
        go(r)
    }

    /// B presses OK on a refusal. Nothing changes.
    public func ack(_ id: String) {
        guard var r = request(id), r.outcome == nil else { return }
        r.acceptedAt = W
        r.outcome = .acknowledged
        mutate(id) { $0 = r }
        ev(.man, .engine, .info, "OK: \(r.label) refused", r.reason)
        pushA("outcome", feedReq(r))
        reqId = nil
    }

    /// B's one button: asks for whatever comes next.
    public func nextPhase() {
        if openReq != nil || frozen { return }
        guard let st = state, st != .idle else {
            if intake.stage == .ready { okReady() }
            return
        }
        raise(st == .work || st == .snooze ? .status : st == .status ? .strategy : .work)
    }

    /// OK on the Ready screen: open the session and ask to start round 1, in one.
    public func okReady() {
        if openReq != nil { return }
        if state == nil { startSession() }
        raise(.work)
    }

    public func canEnd() -> Bool { state != nil && !frozen && openReq == nil }

    /// A: policy (autopilot) or a person.
    public func setAuto(_ v: Bool) {
        auto = v
        ev(.man, v ? .policy : .a, .info, v ? "A: policy (autopilot)" : "A: a person", v ? "policy answers every request at once" : "requests wait for A; the policy's default is shown beside each")
        if v, let r = openReq, r.verdict == nil, let pol = r.policy { decide(r.id, pol.verdict, pol.reason, by: .policy) }
    }

    // MARK: Doing and Next (SPEC §6.6)

    public func canPick() -> Bool { (state == nil || state == .idle || state == .strategy) && !frozen }

    /// Doing and Next are exclusive: a step picked as one stops being the other; picks win over last round's pair.
    public func commitPair() -> Pair {
        var d = picks.d ?? slot(.doing), n = picks.n ?? slot(.next)
        if let x = d, x == n { if picks.d == x { n = picks.n } else { d = picks.d } }
        return Pair(d: d, n: n)
    }

    public func pairNow() -> Pair { canPick() ? commitPair() : Pair(d: slot(.doing), n: slot(.next)) }

    public func validateCommit(_ d: NodeID?, _ n: NodeID?) -> String? {
        guard let d = d, let n = n else { return "Choose Doing and Next." }
        if d == n { return "Doing and Next must be different steps." }
        guard let nd = nodes[d], let nn = nodes[n] else { return "Choose Doing and Next." }
        if nd.root || nn.root { return "The goal itself cannot be Doing or Next." }
        if isClosed(d) { return "\(nd.title) is \(displayStatus(d).word), so it cannot be Doing." }
        if let w = unfinishedDeps(d).first { return "\(nd.title) is waiting for \(title(w) ?? ""), so it cannot be Doing yet." }
        if isClosed(n) { return "\(nn.title) is \(displayStatus(n).word), so it cannot be Next." }
        let un = unfinishedDeps(n)
        if !un.isEmpty && !(un.count == 1 && un[0] == d) { return "\(nn.title) is waiting for \(title(un[0]) ?? ""), so it can only be Next if that is Doing." }
        return nil
    }

    public func pickReason(_ id: NodeID, _ which: PickSlot) -> String? {
        if !canPick() { return "Doing and Next are chosen before a round: on the Ready screen, or while you plan." }
        guard let n = nodes[id] else { return "No such step." }
        if n.root { return "The goal itself cannot be picked." }
        if isClosed(id) { return "A \(displayStatus(id).word) step cannot be " + (which == .d ? "Doing." : "Next.") }
        if which == .d, let w = unfinishedDeps(id).first { return "Waiting for \(title(w) ?? "")." }
        return nil
    }

    public func pick(_ which: PickSlot, _ id: NodeID) {
        if let why = pickReason(id, which) { toast(why); return }
        let cur = which == .d ? picks.d : picks.n
        if cur == id {
            if which == .d { picks.d = nil } else { picks.n = nil }
            ev(.man, .engine, .info, "unpick \(which == .d ? "doing" : "next"): \(title(id) ?? "")", "view state until Go")
            return
        }
        if which == .d { picks.d = id; if picks.n == id { picks.n = nil } }
        else { picks.n = id; if picks.d == id { picks.d = nil } }
        ev(.man, .engine, .info, "pick \(which == .d ? "doing" : "next"): \(title(id) ?? "")", "view state until Go")
    }

    public func pairOps(_ d: NodeID, _ n: NodeID?) -> [Op] {
        var ops: [Op] = []
        let cd = slot(.doing), cn = slot(.next)
        if let cd = cd, cd != d, cd != n { ops.append(.status(cd, .open)) }
        if let cn = cn, cn != d, cn != n { ops.append(.status(cn, .open)) }
        if nodes[d]?.status != .doing { ops.append(.status(d, .doing)) }
        if let n = n, nodes[n]?.status != .next { ops.append(.status(n, .next)) }
        return ops
    }

    /// Auto-commit (SPEC §6.7): keep Doing if it can stay, else promote; Next is the oldest open step.
    public func autoPair() -> Pair {
        var D = slot(.doing) ?? slot(.next) ?? oldestOpen(except: nil)
        if let d = D, isClosed(d) || !unfinishedDeps(d).isEmpty { D = oldestOpen(except: nil) }
        guard let d = D else { return Pair() }
        let cn = slot(.next)
        let n = (cn != nil && cn != d && validateCommit(d, cn) == nil) ? cn : oldestOpen(except: d)
        return Pair(d: d, n: n)
    }
}

public enum PickSlot { case d, n }
