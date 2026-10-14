import Foundation

// The session's numbers (state.js): R the round, r the reminders (and the snoozes), Ls the sitting
// limit, Lb the movement break. Everything else follows from them.

public struct SessionConfig: Codable, Equatable {
    /// The round, in seconds. Whole minutes, 1 to 120.
    public var R: Double
    /// Reminders per round; also the snoozes a round allows. 2, 3 or 4.
    public var r: Int
    /// The sitting limit, in seconds: 1800, 2700 or 3600.
    public var Ls: Double
    /// The movement break, in seconds: 120, 180 or 300.
    public var Lb: Double

    public init(R: Double = 600, r: Int = 3, Ls: Double = 2700, Lb: Double = 180) {
        self.R = R
        self.r = r
        self.Ls = Ls
        self.Lb = Lb
    }

    public static let `default` = SessionConfig()

    /// The base unit: the round split in half, r times. The snooze and the plan are this long.
    public var q: Double { R / pow(2, Double(r)) }
    public var zMax: Int { r }
    /// Time left when each reminder shows, longest first: q·2^(r−1) … q.
    public var remTimes: [Double] { (0..<r).reversed().map { q * pow(2, Double($0)) } }
    /// The check-up after a round: q · 2^(z+1) ÷ (x+1).
    public func awayFor(z: Int, x: Int) -> Double { q * pow(2, Double(z + 1)) / Double(x + 1) }

    public static func validR(_ R: Double) -> Bool { R >= 60 && R <= 7200 && R.truncatingRemainder(dividingBy: 60) == 0 }
    public var isValid: Bool {
        Self.validR(R) && [2, 3, 4].contains(r) && [1800, 2700, 3600].contains(Ls) && [120, 180, 300].contains(Lb)
    }
}

/// The voice: fixed (the spec's wording only), varied (another sentence with the same facts), or rich
/// (varied, plus a tail that says what the numbers mean for B right now). Rich is the default.
public enum VoiceStyle: String, Codable, CaseIterable {
    case fixed, varied, rich
    public var word: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The phases (engine.js PHASE).
public enum Phase: String, Codable, CaseIterable {
    case idle, work, snooze, status, strategy, `break`

    /// As the screens name it.
    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .work: return "Work"
        case .snooze: return "Snooze"
        case .status: return "Check-up"
        case .strategy: return "Plan"
        case .break: return "Break"
        }
    }
}

/// Where a request goes (TO_PHASE): a phase, or the end of the session.
public enum Target: String, Codable {
    case work, snooze, status, strategy, `break`, end

    public var phase: Phase? { Phase(rawValue: rawValue) }
    /// As the request screen's lines name it.
    public var word: String {
        switch self {
        case .work: return "work"
        case .snooze: return "snooze"
        case .status: return "check-up"
        case .strategy: return "plan"
        case .break: return "break"
        case .end: return "end"
        }
    }
}
