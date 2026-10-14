import Foundation

// Host events (monitor.js): what the Monitor draws and the Log lists. The parts of the app, as the
// Monitor draws them: the Session engine is the hub; each part hangs off the one it mostly hands
// off to, on the side of the people (left) or of the plan and the assistant (right).

public enum Part: String, CaseIterable, Codable {
    case engine, timers, man, a, policy, output, coordinator, model, scheduler, store, disk, feed

    public var title: String {
        switch self {
        case .engine: return "Session engine"
        case .timers: return "Timers"
        case .man: return "B"
        case .a: return "A"
        case .policy: return "Policy"
        case .output: return "B's screen"
        case .coordinator: return "Turns"
        case .model: return "Assistant"
        case .scheduler: return "Initiative"
        case .store: return "Store"
        case .disk: return "Storage"
        case .feed: return "A's feed"
        }
    }
    /// The part it hangs off.
    public var up: Part? {
        switch self {
        case .engine: return nil
        case .timers, .man, .a, .policy, .output, .coordinator, .store: return .engine
        case .model, .scheduler: return .coordinator
        case .disk: return .store
        case .feed: return .a
        }
    }
    /// Left (the people) or right (the plan and the assistant), for the hub's branches.
    public var side: String {
        switch self {
        case .timers, .man, .a, .policy: return "l"
        default: return "r"
        }
    }
    public var what: String {
        switch self {
        case .engine: return "Runs the session: holds the clocks, routes every request, and changes phase on Go."
        case .timers: return "Ends each phase when its clock runs out and raises the System's request."
        case .man: return "The person working: picks Doing and Next, edits the plan, asks to move on, presses Go."
        case .a: return "Answers B's requests to change phase, or leaves them to the policy."
        case .policy: return "Decides requests on A's behalf while autopilot is on."
        case .output: return "What B sees and hears: the screens, the strip and the cover, the voice."
        case .coordinator: return "Runs the assistant's one turn per round and holds its answer until planning."
        case .model: return "The built-in assistant: reads the plan, writes a note for B, proposals and a brief for A."
        case .scheduler: return "Scheduled look-ins from Settings › Schedule."
        case .store: return "The plan: every change is a patch, logged with its round, and undoable."
        case .disk: return "This Mac's storage, where the plan is kept between launches."
        case .feed: return "Pushes everything A's screen shows to the URL set under Admin › Feed. One way only."
        }
    }
    /// Hand-offs that do not follow the tree.
    public static let links: [(Part, Part)] = [(.man, .store), (.man, .coordinator), (.coordinator, .store), (.coordinator, .output), (.coordinator, .a)]
    public static func under(_ k: Part) -> [Part] { allCases.filter { $0.up == k } }
}

public enum Outcome: String, Codable {
    case info, ok, warning, error

    /// Its colour token (COLORS) and word (OUTWORD).
    public var tone: Tone {
        switch self { case .info: return .doing; case .ok: return .done; case .warning: return .blocked; case .error: return .stop }
    }
    public var word: String {
        switch self { case .info: return "Hand-off"; case .ok: return "Done"; case .warning: return "Warning"; case .error: return "Error" }
    }
}

/// The colour tokens of the design (base.css), named so the screens can map them.
public enum Tone: String {
    case doing, next, done, blocked, stop, rest, ink2, ink3
}

public struct Event: Identifiable, Equatable {
    public var id: Int
    public var at: String
    public var from: Part
    public var to: Part?
    public var outcome: Outcome
    public var title: String
    public var detail: String
    public var turn: String?
    public var fresh: Bool

    public var route: String { from.title + (to.map { " → " + $0.title } ?? "") }
}

/// What B does, as A sees it: a note on A's screen that fades after five seconds.
public struct Note: Identifiable, Equatable {
    public var id: Int
    public var text: String
    public var warn: Bool
    /// Monotonic milliseconds.
    public var at: Double
}

extension Session {
    public static let noteMs = 5000.0

    @discardableResult
    func ev(_ from: Part, _ to: Part?, _ outcome: Outcome, _ title: String, _ detail: String, turn: String? = nil) -> Event {
        evId += 1
        let e = Event(id: evId, at: Format.stamp(W), from: from, to: to, outcome: outcome, title: title, detail: detail, turn: turn, fresh: true)
        events.append(e)
        if events.count > 600 { events.removeFirst() }
        if outcome == .warning || outcome == .error { let k = to ?? from; unseen[k, default: 0] += 1 }
        logsV += 1
        onEvent?(e)
        if from == .man && to != .a && to != .policy { notify(e) }
        return e
    }

    /// A patch is told by its operations rather than its number; everything else by the event's own title.
    func notify(_ e: Event) {
        var text = e.title
        if text.hasPrefix("patch "), text.contains(":") {
            let ops = e.detail.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
                .map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("unblocked:") }
                .map { line -> String in
                    // "add_node x" → "add node x"
                    guard let sp = line.firstIndex(of: " ") else { return line }
                    let head = String(line[..<sp]), rest = String(line[sp...])
                    return head.replacingOccurrences(of: "_", with: " ") + rest
                }
            if !ops.isEmpty { text = ops.joined(separator: " · ") }
        }
        let warn = e.outcome == .warning || e.outcome == .error
        notes.append(Note(id: e.id, text: text, warn: warn, at: mono()))
        pushA("note", .object(["text": .string(text), "warn": .bool(warn), "title": .string(e.title), "detail": .string(e.detail)]))
        if notes.count > 6 { notes.removeFirst() }
    }

    public func markSeen(_ part: Part? = nil) {
        if let p = part { unseen[p] = 0 } else { unseen = [:] }
    }

    /// Notes still showing (five seconds each).
    public func liveNotes() -> [Note] {
        let now = mono()
        notes.removeAll { now - $0.at >= Self.noteMs }
        return notes
    }
}
