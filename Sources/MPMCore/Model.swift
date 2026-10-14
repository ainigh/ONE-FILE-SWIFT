import Foundation

// The assistant's one turn per round (model.js), from check-up entry to check-up end (SPEC §8.6).
// The built-in assistant reads the plan itself. It never decides a request.

public struct Turn: Equatable {
    public var id: String
    public var since: Double
    public var deadline: Double
    public var answerAt: Double
    public var done: Bool
}

public struct Brief: Equatable {
    public var text: String
    public var forA: String
}

public final class Proposal: Identifiable {
    public let id: String
    public let kind: Kind
    public let targets: [NodeID]
    public let text: String
    public var stale = false
    let okNow: () -> Bool
    let opsNow: () -> [Op]

    public enum Kind { case done, cross }

    init(id: String, kind: Kind, targets: [NodeID], text: String, ok: @escaping () -> Bool, ops: @escaping () -> [Op]) {
        self.id = id; self.kind = kind; self.targets = targets; self.text = text; self.okNow = ok; self.opsNow = ops
    }
}

/// What the assistant's turn holds until planning.
public final class Held {
    public var thinking = false
    public var failed = false
    public var say: String?
    public var props: [Proposal] = []
    public var brief: Brief?

    init() {}
    static func thinking() -> Held { let h = Held(); h.thinking = true; return h }
    static func failed() -> Held { let h = Held(); h.failed = true; return h }
}

extension Session {
    func startTurn() {
        if !modelOn { turn = nil; held = nil; return }
        turnSeq += 1
        let id = "t_\(turnSeq)"
        let lat = min(statusLen * 0.55, 2.7 * max(1, speed))
        turn = Turn(id: id, since: T, deadline: phaseEnd, answerAt: T + lat, done: false)
        held = Held.thinking()
        ev(.engine, .coordinator, .info, "phase turn", "start assistant turn, deadline \(Format.stamp(W + statusLen * 1000)) (check-up end)", turn: id)
        ev(.coordinator, .model, .info, "plan sent", "projection \(Format.n(nodes.count, "step", "steps")), round \(round)\nassistant: built in (reads the plan in this app)", turn: id)
    }

    func abandonTurn() {
        turn?.done = true
        held = Held.failed()
        ev(.coordinator, nil, .warning, "turn abandoned: deadline missed", "no answer by \(Format.stamp(W)); ignored, the session goes on", turn: turn?.id)
    }

    /// The assistant reads B's plan so A does not have to: one plain paragraph about the round, and
    /// what, if anything, A might weigh.
    func briefForA() -> Brief {
        let base = rounds[round]?.start ?? [:]
        let changed = nodes.keys.filter { (base[$0] ?? .new) != displayStatus($0) }
        let cleared = changed.filter(finished).sorted().compactMap(title)
        let bl = nodes.keys.filter(isBlocked).sorted()
        let D = slot(.doing)
        var parts: [String] = []
        parts.append(cleared.isEmpty ? "B finished nothing this round." : "B finished " + (cleared.count == 1 ? "one step" : "\(cleared.count) steps") + ": " + cleared.joined(separator: ", ") + ".")
        if z > 0 { parts.append(z == 1 ? "One snooze." : "\(z) snoozes.") }
        if bl.count == 1 { parts.append("\(title(bl[0]) ?? "") is still waiting on \(title(unfinishedDeps(bl[0]).first) ?? "").") }
        else if bl.count > 1 { parts.append("\(bl.count) steps are still waiting on others.") }
        parts.append(D != nil ? "Doing stays \(title(D) ?? "") unless B changes it." : "B has nothing as Doing yet.")
        let forA = cleared.isEmpty && z >= 2 ? "Worth a word with B before approving round \(round + 1): several snoozes and nothing finished."
            : cleared.isEmpty ? "Nothing for A to weigh now. If this repeats, ask B about it."
            : "Nothing for A to weigh. Approve round \(round + 1) when B asks."
        return Brief(text: parts.joined(separator: " "), forA: forA)
    }

    func modelAnswer() {
        guard var t = turn else { return }
        t.done = true
        turn = t
        let props = modelProps(), text = modelSay(x ?? 0)
        let h = Held()
        h.say = text
        h.props = props
        h.brief = briefForA()
        held = h
        let lat = String(format: "%.1f", (t.answerAt - t.since) / max(1, speed))
        ev(.model, .coordinator, .ok, "answer received", "say: \"\(text)\"\npatch: \(Format.n(props.count, "proposal", "proposals"))\nbrief for A: \"\(h.brief!.text)\"\nlatency \(lat) s, deadline met; held until plan", turn: t.id)
    }

    /// What the assistant says to B at planning: the round's count, then the one thing worth knowing.
    func modelSay(_ x: Int) -> String {
        var bits = [x == 0 ? "Nothing cleared this round. A smaller Doing may help." : x == 1 ? "One step cleared." : "\(x) steps cleared."]
        let bl = nodes.keys.sorted().first(where: isBlocked)
        let base = rounds[round]?.start ?? [:]
        let freed = nodes.keys.sorted().first { base[$0] == .blocked && displayStatus($0) == .open }
        if let bl = bl { bits.append("\(title(bl) ?? "") waits on \(title(unfinishedDeps(bl).first) ?? ""), so keep that moving.") }
        else if let f = freed { bits.append("\(title(f) ?? "") is unblocked now.") }
        else if slot(.next) == nil, oldestOpen(except: slot(.doing)) != nil { bits.append("Nothing is Next yet: pick one before the round starts.") }
        return bits.joined(separator: " ")
    }

    /// Proposals, each one patch B can accept or skip on the board: finish a step under Doing that
    /// looks done, and cross out steps untouched for five days. Locked steps are never touched.
    func modelProps() -> [Proposal] {
        var out: [Proposal] = []
        let D = slot(.doing)
        func free(_ id: NodeID) -> Bool { nodes[id] != nil && !(nodes[id]!.locked) }
        let leaf = D.flatMap { descendants($0).first { free($0) && nodes[$0]!.status == .open && !isBlocked($0) } }
        if let leaf = leaf {
            propSeq += 1
            out.append(Proposal(id: "p_\(propSeq)", kind: .done, targets: [leaf], text: "Mark “\(title(leaf) ?? "")” as done",
                                ok: { [weak self] in self?.nodes[leaf]?.status == .open },
                                ops: { [.status(leaf, .done)] }))
        }
        if round >= 1 {
            for id in staleSteps() {
                if id == D || id == slot(.next) { continue }
                propSeq += 1
                out.append(Proposal(id: "p_\(propSeq)", kind: .cross, targets: [id], text: "Cross out “\(title(id) ?? "")”: untouched for \(ageDays(id)) days",
                                    ok: { [weak self] in self?.nodes[id]?.status == .open },
                                    ops: { [.status(id, .crossed)] }))
            }
        }
        return Array(out.prefix(3))
    }

    /// The proposals on the map right now: at planning, while the plan is open.
    public func mapProps() -> [Proposal] {
        guard state == .strategy, editBlock() == nil, let h = held else { return [] }
        return h.props.filter { !$0.stale && nodes[$0.targets[0]] != nil }
    }

    public func acceptProp(_ p: Proposal) {
        guard let h = held else { return }
        if !p.okNow() { p.stale = true; return }
        ev(.man, .coordinator, .info, "accept \(p.id)", p.text, turn: turn?.id)
        if apply(.model, p.opsNow(), why: "turn \(turn?.id ?? "")") != nil { h.props.removeAll { $0 === p } }
    }

    public func rejectProp(_ p: Proposal) {
        guard let h = held else { return }
        ev(.man, .coordinator, .info, "reject \(p.id)", p.text, turn: turn?.id)
        h.props.removeAll { $0 === p }
    }
}
