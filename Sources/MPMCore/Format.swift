import Foundation

// Numbers the way the engine says them (announce.js): every screen writes them the same way.

public enum Format {
    public static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// Countdown digits: whole seconds, rounded up. 6:12, 0:05.
    public static func digits(_ seconds: Double) -> String {
        let s = max(0, Int(ceil(seconds - 1e-9)))
        return "\(s / 60):\(pad2(s % 60))"
    }

    /// Spoken-friendly lengths: 45 s, 1:30, 10 min, 1:05:00.
    public static func fmt(_ t: Double) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) s" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h):\(pad2(m)):\(pad2(sec))" }
        if sec == 0 { return "\(m) min" }
        return "\(m):\(pad2(sec))"
    }

    /// "1 step" / "3 steps".
    public static func n(_ x: Int, _ one: String, _ many: String) -> String {
        "\(x) \(x == 1 ? one : many)"
    }

    /// "a, b and c"; the empty list reads as "nothing".
    public static func list(_ xs: [String]) -> String {
        if xs.isEmpty { return "nothing" }
        if xs.count == 1 { return xs[0] }
        return xs.dropLast().joined(separator: ", ") + " and " + xs[xs.count - 1]
    }

    static let ordinals = ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth"]
    public static func ordinal(_ i: Int) -> String { i >= 0 && i < ordinals.count ? ordinals[i] : "\(i)th" }

    /// 14:32:07, from a wall-clock time in milliseconds, in the local time zone.
    public static func stamp(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return "\(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0)):\(pad2(c.second ?? 0))"
    }

    /// ISO 8601, from a wall-clock time in milliseconds.
    public static func iso(_ ms: Double) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }

    /// "today", "yesterday", "3 days ago": how long since `ms`, as of `now` (both wall-clock ms).
    public static func updatedWord(_ ms: Double, now: Double) -> String {
        let d = Int(floor((now - ms) / 86_400_000))
        return d <= 0 ? "today" : d == 1 ? "yesterday" : "\(d) days ago"
    }

    /// Seated time as the screens show it: "38 min".
    public static func seatedMin(_ seconds: Double) -> String { "\(Int(floor(seconds / 60))) min" }

    /// FNV-1a, 32-bit: the deterministic choice the voice makes.
    public static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 {
            h ^= UInt32(b)
            h = h &* 0x01000193
        }
        return h
    }
}
