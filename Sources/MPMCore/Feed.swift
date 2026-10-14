import Foundation

/// Plain JSON, for the feed's envelopes and anything else that goes out as data.
public indirect enum JSON: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public static func int(_ v: Int) -> JSON { .number(Double(v)) }
    public static func opt(_ v: String?) -> JSON { v.map { .string($0) } ?? .null }
    public static func opt(_ v: Double?) -> JSON { v.map { .number($0) } ?? .null }
    public static func opt(_ v: Int?) -> JSON { v.map { .number(Double($0)) } ?? .null }

    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d == d.rounded() && abs(d) < 1e15 ? Int(d) as Any : d as Any
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    public func data() -> Data {
        (try? JSONSerialization.data(withJSONObject: any, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

/// One message of A's feed (feed.js): everything A's screen shows, as one POST each.
public struct FeedMessage {
    public var seq: Int
    public var kind: String
    public var at: String
    public var body: JSON

    public init(seq: Int, kind: String, at: String, body: JSON) {
        self.seq = seq
        self.kind = kind
        self.at = at
        self.body = body
    }
}

extension Session {
    func feedEnvelope(_ kind: String, _ data: JSON) -> FeedMessage {
        feedSeq += 1
        let body: JSON = .object([
            "v": .int(1), "seq": .int(feedSeq), "kind": .string(kind), "at": .string(Format.iso(W)),
            "session": .opt(sessionId.isEmpty ? nil : sessionId), "round": .int(round),
            "state": .opt(state?.rawValue), "frozen": .bool(frozen), "left": running() ? .int(Int(left().rounded())) : .null,
            "names": .object(["a": .opt(names.a.isEmpty ? nil : names.a), "b": .opt(names.b.isEmpty ? nil : names.b)]),
            "data": data,
        ])
        return FeedMessage(seq: feedSeq, kind: kind, at: Format.iso(W), body: body)
    }

    public func feedReq(_ r: Request) -> JSON {
        .object([
            "id": .string(r.id), "label": .string(r.label), "round": .int(r.round), "from_phase": .string(r.fromPhase),
            "to_phase": .string(r.to.rawValue), "raised_by": .string(r.raisedBy.rawValue), "sent_at": .number(r.sentAt.rounded()),
            "policy": r.policy.map { .object(["verdict": .string($0.verdict.rawValue), "reason": .string($0.reason)]) } ?? .null,
            "verdict": .opt(r.verdict?.rawValue), "decided_by": .opt(r.decidedBy?.rawValue), "decided_at": .opt(r.decidedAt?.rounded()),
            "reason": .string(r.reason), "accepted_at": .opt(r.acceptedAt?.rounded()), "outcome": .opt(r.outcome?.rawValue),
            "cannot_approve": r.verdict != nil ? .null : .opt(cannotApprove(r)),
        ])
    }

    /// pushA: called wherever A's screen learns something. The app sends it when a feed is on.
    func pushA(_ kind: String, _ data: JSON) {
        guard let send = onFeed else { return }
        send(feedEnvelope(kind, data))
    }

    public func feedHello() {
        pushA("hello", .object(["note": .string("A's feed from Machine Prompts Man: one POST per thing A's screen shows; nothing is read back.")]))
    }

    public func feedTest() {
        pushA("test", .object(["note": .string("sent from Admin › Feed")]))
    }

    /// An event from the app around the engine (the feed, the voice switch, the schedule).
    public func logEvent(_ from: Part, _ to: Part?, _ outcome: Outcome, _ title: String, _ detail: String) {
        ev(from, to, outcome, title, detail)
    }
}
