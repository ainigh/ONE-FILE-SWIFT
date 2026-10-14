import Foundation

// The speech logic that needs only Foundation, so it's tested on any machine (swift test):
// text as it should be spoken, cutting microphone audio into phrases, and choosing voices.
// Ported from Tool Mac Tool (ainigh/tool-mac-tool, Sources/ToolCore/Speech.swift).

/// Text as it should be heard rather than read: no code, no Markdown marks, link text without
/// its address, one line per thought.
public enum SpokenText {
    public static func clean(_ text: String) -> String {
        var lines: [String] = []
        var inCode = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {   // code is for reading
                inCode.toggle()
                continue
            }
            if inCode { continue }
            lines.append(cleanLine(line))
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanLine(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        // A rule (---, ***, ___) says nothing.
        if s.count >= 3, Set(s.filter { !$0.isWhitespace }).count == 1, "-*_".contains(s.first!) { return "" }
        s = dropPrefix(s, pattern: #"^#{1,6}\s+"#)            // headings
        s = dropPrefix(s, pattern: #"^(>\s*)+"#)              // quotes
        s = dropPrefix(s, pattern: #"^([-*+]|\d{1,3}[.)])\s+"#) // list items
        s = dropPrefix(s, pattern: #"^\[[ xX]\]\s+"#)         // tasks
        s = replace(s, #"!?\[([^\]]*)\]\([^)]*\)"#, "$1")     // [text](url) -> text
        s = replace(s, #"https?://\S+"#, "a link")
        s = replace(s, #"(\*\*|__)(.+?)\1"#, "$2")             // bold
        s = replace(s, #"(?<![\w*])[*_](?!\s)(.+?)(?<!\s)[*_](?![\w*])"#, "$1") // italics
        s = replace(s, #"~~(.+?)~~"#, "$1")
        s = s.replacingOccurrences(of: "`", with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func dropPrefix(_ s: String, pattern: String) -> String {
        replace(s, pattern, "")
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Splits cleaned text into sentences: at . ! ? … followed by a space (not after a short
    /// abbreviation like "e.g." or "Dr."), and at every line break.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.split(separator: "\n") {
            var current = ""
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                current.append(c)
                if ".!?…".contains(c) {
                    // Closing quotes and brackets belong to the sentence.
                    while i + 1 < chars.count, "\"'”’)]".contains(chars[i + 1]) {
                        i += 1
                        current.append(chars[i])
                    }
                    let atEnd = i + 1 >= chars.count
                    let spaceNext = !atEnd && chars[i + 1].isWhitespace
                    if (spaceNext || atEnd) && !(c == "." && endsWithAbbreviation(current)) {
                        push(&out, current)
                        current = ""
                    }
                }
                i += 1
            }
            push(&out, current)
        }
        return out
    }

    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.",
                                                     "st.", "no.", "approx.", "fig.", "p.m.", "a.m."]

    private static func endsWithAbbreviation(_ s: String) -> Bool {
        guard let last = s.split(whereSeparator: \.isWhitespace).last?.lowercased() else { return false }
        let word = last.trimmingCharacters(in: CharacterSet(charactersIn: "(\"'"))
        if abbreviations.contains(word) { return true }
        // A single capital and a dot ("J. Smith") is an initial.
        return word.count == 2 && word.first!.isLetter
    }

    private static func push(_ out: inout [String], _ s: String) {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains(where: { $0.isLetter || $0.isNumber }) { out.append(t) }
    }

    /// The word being said `fraction` (0 to 1) of the way through saying `text`, when the time is
    /// spread over the words by their length. A UTF-16 range, as NSString counts.
    public static func wordRange(in text: String, at fraction: Double) -> NSRange? {
        var words: [NSRange] = []
        var start: String.Index?
        for i in text.indices {
            let inWord = text[i].isLetter || text[i].isNumber || ((text[i] == "'" || text[i] == "’") && start != nil)
            if inWord, start == nil { start = i }
            if !inWord, let s = start {
                words.append(NSRange(s..<i, in: text))
                start = nil
            }
        }
        if let s = start { words.append(NSRange(s..<text.endIndex, in: text)) }
        guard !words.isEmpty else { return nil }
        let total = words.reduce(0) { $0 + $1.length + 1 }
        var target = Double(total) * min(max(fraction, 0), 1)
        for w in words {
            target -= Double(w.length + 1)
            if target < 0 { return w }
        }
        return words.last
    }
}

/// Where to cut long audio into pieces a recognizer takes one at a time: at the quietest moment
/// near the end of each piece, so a word is rarely cut in half.
public enum QuietCut {
    /// `levels` is the loudness of consecutive short frames of one piece; the cut is the quietest
    /// frame at or after `from` (the last one if several are equally quiet, so pieces stay long).
    /// With nothing to search, the piece is kept whole.
    public static func cut(levels: [Float], from: Int) -> Int {
        let start = max(0, min(from, levels.count))
        guard start < levels.count else { return levels.count }
        var best = start
        for i in start..<levels.count where levels[i] <= levels[best] { best = i }
        return best
    }
}

/// Cuts live microphone audio (16 kHz mono) into phrases at the pauses, so each one can be written
/// down whole. Once someone speaks, every sample ends up in exactly one phrase; only quiet before
/// speech is dropped, all but a little of it (so the first word's start isn't clipped). A phrase
/// that runs on is cut at its quietest moment before it gets too long.
public struct PhraseCutter {
    public static let rate = 16_000
    /// Loudness is judged on frames this long (20 ms).
    static let frame = 320

    /// How long a pause ends a phrase.
    public var pause: Double
    /// The longest a phrase may get (the recognizer takes about 15 s at a time; longer is cut).
    public var longest: Double
    /// Quiet kept in front of speech.
    public var lead: Double = 0.3

    /// The open phrase so far.
    public private(set) var open: [Float] = []
    /// Someone spoke in the open phrase.
    public private(set) var spoke = false
    private var quietFrames = 0
    private var levels: [Float] = []        // per frame of `open`
    private var carry: [Float] = []         // samples short of a whole frame
    /// The background's loudness, followed slowly; speech is well above it.
    private var floor: Float = 0.003

    public init(pause: Double, longest: Double = 14) {
        self.pause = pause
        self.longest = longest
    }

    /// A finished phrase: its audio, and whether a pause ended it (rather than its length).
    public struct Phrase: Equatable {
        public var samples: [Float]
        public var paused: Bool
    }

    /// Adds what the microphone heard; returns the phrases it finished, oldest first.
    public mutating func add(_ samples: [Float]) -> [Phrase] {
        var done: [Phrase] = []
        carry += samples
        var i = 0
        while i + Self.frame <= carry.count {
            let chunk = Array(carry[i..<(i + Self.frame)])
            i += Self.frame
            if let phrase = addFrame(chunk) { done.append(phrase) }
        }
        carry.removeFirst(i)
        return done
    }

    /// Ends the open phrase now (listening stopped, or "send it now"): it, if anything was said.
    public mutating func flush() -> [Float]? {
        open += carry
        carry = []
        defer { reset() }
        return spoke ? open : nil
    }

    /// Forgets the open phrase (what was heard while held).
    public mutating func reset() {
        carry = []
        startOver()
    }

    /// A new phrase starts (what's heard but not yet looked at stays).
    private mutating func startOver() {
        open = []
        levels = []
        spoke = false
        quietFrames = 0
    }

    public static func rms(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sum: Float = 0
        for x in frame { sum += x * x }
        return (sum / Float(frame.count)).squareRoot()
    }

    /// Louder than this counts as speech.
    var threshold: Float { max(0.006, floor * 3.5) }

    private mutating func addFrame(_ chunk: [Float]) -> Phrase? {
        let level = Self.rms(chunk[...])
        let loud = level > threshold
        // The floor drops quickly to quiet and rises slowly with steady background noise; speech
        // doesn't move it.
        if level < floor {
            floor = floor * 0.9 + level * 0.1
        } else if !loud {
            floor = min(0.015, floor * 0.99 + level * 0.01)
        }
        open += chunk
        levels.append(level)
        if loud {
            spoke = true
            quietFrames = 0
        } else {
            quietFrames += 1
        }
        let frameSeconds = Double(Self.frame) / Double(Self.rate)
        if !spoke {
            // Only quiet so far: keep just the lead.
            let keep = max(1, Int((lead / frameSeconds).rounded()))
            if levels.count > keep {
                let drop = levels.count - keep
                levels.removeFirst(drop)
                open.removeFirst(drop * Self.frame)
            }
            return nil
        }
        if Double(quietFrames) * frameSeconds >= pause {
            // The pause ends it (and stays in it: a soft word in it isn't lost).
            let phrase = Phrase(samples: open, paused: true)
            startOver()
            return phrase
        }
        if Double(levels.count) * frameSeconds >= longest {
            // Too long: cut at the quietest frame of its last third; the rest starts the next one.
            let from = levels.count * 2 / 3
            let cut = QuietCut.cut(levels: levels, from: from) + 1
            let phrase = Phrase(samples: Array(open[..<(cut * Self.frame)]), paused: false)
            open.removeFirst(cut * Self.frame)
            levels.removeFirst(cut)
            spoke = levels.contains { $0 > threshold }
            quietFrames = 0
            return phrase
        }
        return nil
    }
}

/// The voices the app speaks with: Kokoro's best two women's and two men's (its own quality
/// grades put Heart and Bella first, then Michael and Fenrir). Open source (Apache 2.0); they run
/// on this Mac.
public struct NeuralVoice: Equatable {
    public var id: String
    public var name: String
    public var female: Bool

    public static let all = [
        NeuralVoice(id: "af_heart", name: "Heart", female: true),
        NeuralVoice(id: "af_bella", name: "Bella", female: true),
        NeuralVoice(id: "am_michael", name: "Michael", female: false),
        NeuralVoice(id: "am_fenrir", name: "Fenrir", female: false),
    ]

    public static func named(_ id: String?) -> NeuralVoice {
        all.first { $0.id == id } ?? all[0]
    }
}

/// A system voice, as much of it as picking one needs.
public struct VoiceInfo: Equatable {
    public enum Quality: Int, Comparable {
        case standard, enhanced, premium
        public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    public var identifier: String
    public var name: String
    /// "en-US"
    public var language: String
    public var quality: Quality
    /// nil when the system doesn't say.
    public var female: Bool?

    public init(identifier: String, name: String, language: String, quality: Quality, female: Bool?) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.female = female
    }
}

/// The macOS voices used while the Kokoro voices aren't there yet (first download, or it failed):
/// the two best women's and the two best men's voices this Mac has for the language. Best means
/// the highest quality (Premium, then Enhanced), then the ones that sound most natural (the order
/// of the lists below).
public enum VoiceLineup {
    static let women = ["Ava", "Zoe", "Serena", "Matilda", "Allison", "Samantha", "Susan", "Joelle", "Noelle",
                        "Karen", "Moira", "Tessa", "Kate", "Fiona", "Veena", "Isha", "Victoria"]
    static let men = ["Evan", "Jamie", "Nathan", "Lee", "Tom", "Aaron", "Alex", "Oliver", "Daniel", "Arthur",
                      "Malcolm", "Gordon", "Rishi", "Fred"]

    /// Women first, then men; fewer when the Mac doesn't have that many.
    public static func pick(_ voices: [VoiceInfo]) -> [VoiceInfo] {
        best(voices, female: true) + best(voices, female: false)
    }

    public static func best(_ voices: [VoiceInfo], female: Bool) -> [VoiceInfo] {
        let names = female ? women : men
        let theirs = voices.filter { v in
            if names.contains(v.name) { return true }
            if (female ? men : women).contains(v.name) { return false }
            return v.female == female
        }
        func rank(_ v: VoiceInfo) -> Int { names.firstIndex(of: v.name) ?? names.count }
        let sorted = theirs.sorted { a, b in
            if a.quality != b.quality { return a.quality > b.quality }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.name < b.name
        }
        var out: [VoiceInfo] = []
        for v in sorted where !out.contains(where: { $0.name == v.name }) {
            out.append(v)
            if out.count == 2 { break }
        }
        return out
    }
}
