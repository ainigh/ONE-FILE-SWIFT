import Foundation

// The plan (store.js, SPEC §5): a tree of steps under one goal, Doing and Next among them, with
// dependencies between steps. Every change is a patch, logged with its round, and undoable.

public typealias NodeID = String

public enum NodeStatus: String, Codable {
    case open, doing, next, done, crossed
}

/// What a step reads as: its status, or blocked when it is open and waits for an unfinished step.
public enum DisplayStatus: String, Codable {
    case open, doing, next, blocked, done, crossed, new

    /// As the screens word it (WORD).
    public var word: String {
        switch self {
        case .crossed: return "crossed out"
        default: return rawValue
        }
    }
}

public struct Node: Codable, Equatable {
    public var title: String
    public var parent: NodeID?
    public var status: NodeStatus
    public var deps: [NodeID]
    public var created: Int
    public var root: Bool
    public var locked: Bool
    /// Wall-clock milliseconds.
    public var updated: Double
    /// Just added: the map lights it once. Not saved.
    public var fresh: Bool = false

    enum CodingKeys: String, CodingKey { case title, parent, status, deps, created, root, locked, updated }

    public init(title: String, parent: NodeID?, created: Int, updated: Double) {
        self.title = title
        self.parent = parent
        self.status = .open
        self.deps = []
        self.created = created
        self.root = parent == nil
        self.locked = false
        self.updated = updated
    }
}

/// One operation of a patch: the field it changes, from what, to what.
public enum OpValue: Equatable {
    case none
    case node(Node)
    case status(NodeStatus)
    case text(String)
    case deps([NodeID])
    case flag(Bool)
}

public enum OpField: String { case add, status, title, deps, locked }

public struct Op: Equatable {
    public var id: NodeID
    public var field: OpField
    public var from: OpValue
    public var to: OpValue

    public init(id: NodeID, field: OpField, from: OpValue = .none, to: OpValue) {
        self.id = id
        self.field = field
        self.from = from
        self.to = to
    }

    public static func add(_ id: NodeID, _ node: Node) -> Op { Op(id: id, field: .add, to: .node(node)) }
    public static func status(_ id: NodeID, _ s: NodeStatus) -> Op { Op(id: id, field: .status, to: .status(s)) }
    public static func title(_ id: NodeID, _ t: String) -> Op { Op(id: id, field: .title, to: .text(t)) }
    public static func deps(_ id: NodeID, _ d: [NodeID]) -> Op { Op(id: id, field: .deps, to: .deps(d)) }
    public static func locked(_ id: NodeID, _ v: Bool) -> Op { Op(id: id, field: .locked, to: .flag(v)) }
}

/// Who makes a patch.
public enum Author: String { case man, model, engine }

public struct PatchRecord {
    public var n: Int
    public var by: Author
    public var why: String
    public var round: Int
    public var phase: String
    public var ops: [Op]
}

/// The plan as the browser keeps it (PLAN_KEY, v 1).
public struct PlanSnapshot: Codable {
    public var v: Int = 1
    public var nodes: [NodeID: Node]
    public var seq: Int
    public var pn: Int
}

// MARK: - Queries

extension Session {
    public func node(_ id: NodeID) -> Node? { nodes[id] }
    public func finished(_ id: NodeID) -> Bool { nodes[id]?.status == .done }
    public func isClosed(_ id: NodeID) -> Bool {
        guard let s = nodes[id]?.status else { return false }
        return s == .done || s == .crossed
    }
    public func unfinishedDeps(_ id: NodeID) -> [NodeID] {
        (nodes[id]?.deps ?? []).filter { nodes[$0] != nil && !finished($0) }
    }
    public func isBlocked(_ id: NodeID) -> Bool { !isClosed(id) && !unfinishedDeps(id).isEmpty }
    /// The one step with this status, if any.
    public func slot(_ st: NodeStatus) -> NodeID? {
        nodes.first { $0.value.status == st }?.key
    }
    public func title(_ id: NodeID?) -> String? {
        guard let id = id else { return nil }
        return nodes[id]?.title
    }
    public func displayStatus(_ id: NodeID) -> DisplayStatus {
        guard let n = nodes[id] else { return .new }
        if n.status == .open && isBlocked(id) { return .blocked }
        return DisplayStatus(rawValue: n.status.rawValue) ?? .open
    }
    public func kids(_ id: NodeID) -> [NodeID] {
        nodes.filter { $0.value.parent == id }.map(\.key).sorted { nodes[$0]!.created < nodes[$1]!.created }
    }
    public func descendants(_ id: NodeID) -> [NodeID] {
        var out: [NodeID] = []
        for k in kids(id) { out.append(k); out += descendants(k) }
        return out
    }
    /// Every step in tree order, with its depth.
    public func treeOrder() -> [(id: NodeID, depth: Int)] {
        var out: [(id: NodeID, depth: Int)] = []
        func walk(_ id: NodeID, _ d: Int) { out.append((id: id, depth: d)); for k in kids(id) { walk(k, d + 1) } }
        let roots = nodes.filter { $0.value.parent == nil }.map(\.key).sorted { nodes[$0]!.created < nodes[$1]!.created }
        for r in roots { walk(r, 0) }
        return out
    }
    public func goal() -> NodeID? { nodes.first { $0.value.root }?.key }
    public func oldestOpen(except: NodeID?) -> NodeID? {
        var best: NodeID?
        for (k, n) in nodes {
            if n.root || k == except || n.status != .open || isBlocked(k) { continue }
            if best == nil || n.created < nodes[best!]!.created { best = k }
        }
        return best
    }
    /// Does a (transitively) wait for b?
    public func dependsOn(_ a: NodeID, _ b: NodeID, seen: Set<NodeID> = []) -> Bool {
        if seen.contains(a) { return false }
        var seen = seen; seen.insert(a)
        return (nodes[a]?.deps ?? []).contains { $0 == b || (nodes[$0] != nil && dependsOn($0, b, seen: seen)) }
    }
    /// Age in whole days since a step was last touched.
    public func ageDays(_ id: NodeID) -> Int {
        guard let n = nodes[id] else { return 0 }
        return Int(floor((W - n.updated) / 86_400_000))
    }
    /// A step B has not touched for five days or more: open, unlocked, not Doing or Next, not the goal.
    public func staleSteps() -> [NodeID] {
        nodes.filter { !$0.value.root && !$0.value.locked && $0.value.status == .open && ageDays($0.key) >= 5 }.map(\.key).sorted()
    }
    public func hasSteps() -> Bool { nodes.contains { !$0.value.root && !isClosed($0.key) } }
    public func leafSteps() -> [NodeID] {
        nodes.filter { !$0.value.root && kids($0.key).isEmpty && $0.value.status != .crossed }.map(\.key)
    }
    public func pathOf(_ id: NodeID) -> [String] {
        var out: [String] = []
        var p = nodes[id]?.parent
        while let q = p, let n = nodes[q] { out.insert(n.title, at: 0); p = n.parent }
        return out
    }

    /// Who edits, and when (addendum §7): only B edits the graph, and only in idle, work, snooze and
    /// plan. Check-up, the break and every freeze are closed. Nobody types into the grid.
    public func editBlock() -> String? {
        if frozen { return "Time has stopped. The plan opens again when you press Go." }
        if state == .status { return "The plan is closed during check-up. Step away from the desk." }
        if state == .break { return "The plan is locked during the movement break. It opens again in \(Format.digits(left()))." }
        return nil
    }

    public func describe(_ o: Op) -> String {
        var t = title(o.id) ?? o.id
        if o.field == .add {
            if case .node(let n) = o.to { t = n.title } else if case .node(let n) = o.from { t = n.title }
        }
        switch o.field {
        case .add:
            if case .node(let n) = o.to { return "add_node \(t) under \(title(n.parent) ?? "nothing")" }
            return "remove_node \(t)"
        case .status:
            if case .status(let to) = o.to {
                if to == .crossed { return "cross_out \(t)" }
                if case .status(.crossed) = o.from { return "restore \(t)" }
                return "set_status \(t) → \(DisplayStatus(rawValue: to.rawValue)?.word ?? to.rawValue)"
            }
            return "set_status \(t)"
        case .title:
            if case .text(let from) = o.from, case .text(let to) = o.to { return "rename \(from) → \(to)" }
            return "rename \(t)"
        case .deps:
            if case .deps(let from) = o.from, case .deps(let to) = o.to {
                return to.count > from.count ? "add_dependency \(t) on \(title(to.last) ?? "?")" : "remove_dependency \(t)"
            }
            return "dependency \(t)"
        case .locked:
            if case .flag(let v) = o.to { return (v ? "lock " : "unlock ") + t }
            return "lock \(t)"
        }
    }

    private func setOp(_ o: Op) {
        if o.field == .add {
            if case .node(let n) = o.to {
                var m = n; m.fresh = true; m.updated = W
                nodes[o.id] = m
            } else {
                nodes.removeValue(forKey: o.id)
            }
            return
        }
        guard var n = nodes[o.id] else { return }
        switch o.field {
        case .status:
            guard case .status(let to) = o.to else { return }
            if to == .doing || to == .next, let cur = slot(to), cur != o.id { nodes[cur]?.status = .open }
            n.status = to
            if to == .done { doneAt[o.id] = T } else { doneAt.removeValue(forKey: o.id) }
        case .title: if case .text(let t) = o.to { n.title = t }
        case .deps: if case .deps(let d) = o.to { n.deps = d }
        case .locked: if case .flag(let v) = o.to { n.locked = v }
        case .add: break
        }
        n.updated = W
        nodes[o.id] = n
    }

    private func current(_ o: Op) -> OpValue {
        guard let n = nodes[o.id] else { return .none }
        switch o.field {
        case .add: return .node(n)
        case .status: return .status(n.status)
        case .title: return .text(n.title)
        case .deps: return .deps(n.deps)
        case .locked: return .flag(n.locked)
        }
    }

    /// Store.apply: every change goes through here, is logged with its round stamp, and (for B and
    /// the model) can be undone.
    @discardableResult
    public func apply(_ by: Author, _ ops: [Op], why: String = "", noUndo: Bool = false) -> PatchRecord? {
        if ops.isEmpty { return nil }
        if by != .engine, let blocked = editBlock() {
            ev(byPart(by), .store, .warning, "patch refused: plan closed", blocked)
            toast(blocked)
            return nil
        }
        var rec = PatchRecord(n: pn + 1, by: by, why: why, round: round, phase: state?.rawValue ?? "none", ops: [])
        rec.ops = ops.map { o in
            var x = o
            x.from = o.field == .add ? (nodes[o.id].map { .node($0) } ?? .none) : current(o)
            return x
        }
        var was: [NodeID: Bool] = [:]
        for k in nodes.keys { was[k] = isBlocked(k) }
        let D0 = slot(.doing)
        let lines = rec.ops.map(describe)
        rec.ops.forEach(setOp)
        pn = rec.n
        let unb = nodes.keys.filter { was[$0] == true && !isBlocked($0) && !isClosed($0) }.sorted()
        ev(byPart(by), .store, .ok, "patch \(rec.n): \(Format.n(rec.ops.count, "op", "ops"))",
           "by \(by.rawValue)" + (why.isEmpty ? "" : " (\(why))") + ", round \(rec.round) · \(rec.phase), store version \(rec.n)\n" + lines.joined(separator: "\n")
           + (unb.isEmpty ? "" : "\nunblocked: " + unb.compactMap(title).joined(separator: ", ")),
           turn: by == .model ? turn?.id : nil)
        if onSavePlan?(snapshot()) ?? false {
            ev(.store, .disk, .ok, "plan saved", "this Mac's storage, \(Format.n(nodes.count, "step", "steps")), version \(pn)")
        } else {
            ev(.store, .disk, .warning, "plan not saved", "storage refused; the plan lives only in this window until it can be saved")
        }
        if !noUndo && by != .engine { undoStack.append(rec); redoStack = [] }
        // SPEC §6.5: Doing vacated during work or snooze, with no new Doing in the patch: promote Next.
        if let d0 = D0, slot(.doing) == nil, running(), state == .work || state == .snooze {
            if let n = slot(.next) {
                apply(.engine, [.status(n, .doing)], why: "promote next")
                speak("promote_next", AnnounceContext(doing: title(n), prevDoing: title(d0)), "Now doing \(title(n) ?? "").")
            } else {
                speak("no_doing", AnnounceContext(), "No doing node.")
            }
        }
        return rec
    }

    func byPart(_ by: Author) -> Part {
        switch by { case .man: return .man; case .model: return .coordinator; case .engine: return .engine }
    }

    public func undo() {
        guard let rec = undoStack.popLast() else { return }
        let orphans = rec.ops.contains { o in
            if o.field == .add, case .node = o.to, nodes[o.id] != nil, !kids(o.id).isEmpty { return true }
            return false
        }
        if orphans { undoStack.append(rec); toast("Undo would remove a step that now has steps under it. Cross it out instead."); return }
        let inv = rec.ops.reversed().map { Op(id: $0.id, field: $0.field, to: $0.from) }
        ev(.man, .store, .info, "undo patch \(rec.n)", "")
        if apply(.man, inv, why: "undo \(rec.n)", noUndo: true) != nil { redoStack.append(rec) } else { undoStack.append(rec) }
    }

    public func redo() {
        guard let rec = redoStack.popLast() else { return }
        ev(.man, .store, .info, "redo patch \(rec.n)", "")
        if apply(.man, rec.ops.map { Op(id: $0.id, field: $0.field, to: $0.to) }, why: "redo \(rec.n)", noUndo: true) != nil { undoStack.append(rec) } else { redoStack.append(rec) }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: B's operations on the graph (each one patch)

    func canEdit(_ id: NodeID?) -> Bool { id != nil && nodes[id!] != nil }

    public func markDone(_ id: NodeID) {
        guard canEdit(id), let n = nodes[id], !n.root, !finished(id) else { return }
        if let b = editBlock() { toast(b); return }
        if picks.d == id { picks.d = nil }
        if picks.n == id { picks.n = nil }
        apply(.man, [.status(id, .done)])
    }
    public func reopen(_ id: NodeID) {
        if canEdit(id), finished(id), unfinishedDeps(id).isEmpty { apply(.man, [.status(id, .open)]) }
    }
    public func crossOut(_ id: NodeID) {
        guard canEdit(id), let n = nodes[id], !n.root, n.status != .crossed else { return }
        var ops: [Op] = [.status(id, .crossed)]
        for k in descendants(id) {
            let s = nodes[k]!.status
            if s != .done && s != .crossed { ops.append(.status(k, .crossed)) }
        }
        if apply(.man, ops) != nil {
            if picks.d == id { picks.d = nil }
            if picks.n == id { picks.n = nil }
        }
    }
    public func restore(_ id: NodeID) {
        if canEdit(id), nodes[id]?.status == .crossed { apply(.man, [.status(id, .open)]) }
    }
    public func rename(_ id: NodeID, _ t: String) {
        let t = t.trimmingCharacters(in: .whitespaces)
        if canEdit(id), !t.isEmpty, t != nodes[id]?.title { apply(.man, [.title(id, t)]) }
    }
    /// Adds a step under `parent` (the goal when nil; a goal is made when there is none). Its id.
    @discardableResult
    public func addChild(_ parent: NodeID?, _ t: String? = nil) -> NodeID? {
        var parent = canEdit(parent) ? parent : goal()
        if parent == nil {
            seq += 1
            let gid = "n\(seq)"
            if apply(.man, [.add(gid, Node(title: "Today", parent: nil, created: seq, updated: W))]) == nil { return nil }
            parent = gid
        }
        seq += 1
        let id = "n\(seq)"
        let n = Node(title: (t?.isEmpty == false) ? t! : "New step", parent: parent, created: seq, updated: W)
        return apply(.man, [.add(id, n)]) != nil ? id : nil
    }
    public func addDep(_ id: NodeID, on: NodeID) {
        guard canEdit(id), canEdit(on), id != on, !(nodes[id]!.deps.contains(on)) else { return }
        if dependsOn(on, id) {
            let m = "\(title(on) ?? "") already waits for \(title(id) ?? ""). A step cannot wait for itself."
            ev(.man, .store, .error, "patch refused: dependency cycle", m)
            toast(m)
            return
        }
        apply(.man, [.deps(id, nodes[id]!.deps + [on])])
    }
    public func removeDep(_ id: NodeID) {
        if canEdit(id), let d = nodes[id]?.deps, !d.isEmpty { apply(.man, [.deps(id, Array(d.dropLast()))]) }
    }
    public func setLock(_ id: NodeID, _ v: Bool) {
        if canEdit(id) { apply(.man, [.locked(id, v)]) }
    }

    /// Clear the plan: every step goes, and the next visit starts at the intake. Only outside a session.
    @discardableResult
    public func clearPlan() -> Bool {
        if state != nil { return false }
        let count = nodes.count
        nodes = [:]; seq = 0; pn = 0; doneAt = [:]; undoStack = []; redoStack = []; selected = nil; picks = Pair()
        intake = Intake(stage: firstStage(), ids: [])
        gridRound = 0
        _ = onSavePlan?(snapshot())
        ev(.man, .store, .info, "plan cleared", "\(Format.n(count, "step", "steps")) removed")
        return true
    }

    // MARK: Persistence

    public func snapshot() -> PlanSnapshot { PlanSnapshot(nodes: nodes, seq: seq, pn: pn) }

    /// The plan outlives the app: every patch writes it, and the next launch opens on it.
    @discardableResult
    public func load(_ p: PlanSnapshot) -> Bool {
        guard p.v == 1 else { return false }
        var ns: [NodeID: Node] = [:]
        for (k, n) in p.nodes {
            var m = n
            m.root = n.parent == nil
            ns[k] = m
        }
        for (k, n) in ns {
            var m = n
            if let p = m.parent, ns[p] == nil { m.parent = nil; m.root = true }
            m.deps = m.deps.filter { ns[$0] != nil }
            ns[k] = m
        }
        nodes = ns
        seq = max(0, p.seq)
        pn = max(0, p.pn)
        return true
    }
}
