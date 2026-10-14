import XCTest
@testable import CountdownCore

final class SpeechTests: XCTestCase {
    func testCleanDropsMarkdownAndCode() {
        let reply = """
        # Plan
        Here is **bold**, *italic*, `code` and [a link](https://x.y).

        - first item
        2. second item
        > a quote
        ---
        ```swift
        let x = 1
        ```
        See https://example.com for more.
        """
        XCTAssertEqual(SpokenText.clean(reply), """
        Plan
        Here is bold, italic, code and a link.

        first item
        second item
        a quote

        See a link for more.
        """)
    }

    func testCleanKeepsSnakeCaseAndProducts() {
        XCTAssertEqual(SpokenText.clean("Set my_var_name to 2*3*4."), "Set my_var_name to 2*3*4.")
    }

    func testSentencesSplitAtEndsAndLines() {
        XCTAssertEqual(SpokenText.sentences("Hi there. How are you? Fine!\nNext line"),
                       ["Hi there.", "How are you?", "Fine!", "Next line"])
    }

    func testSentencesKeepAbbreviationsDecimalsAndQuotes() {
        XCTAssertEqual(SpokenText.sentences("Use e.g. butter. It costs 3.50 now. He said \"stop.\" Then left."),
                       ["Use e.g. butter.", "It costs 3.50 now.", "He said \"stop.\"", "Then left."])
        XCTAssertEqual(SpokenText.sentences("Ask J. Smith about it."), ["Ask J. Smith about it."])
    }

    func testSentencesSkipPunctuationOnly() {
        XCTAssertEqual(SpokenText.sentences("...\n- \nOk."), ["Ok."])
    }

    func testQuietCut() {
        XCTAssertEqual(QuietCut.cut(levels: [5, 1, 4, 2, 3], from: 2), 3)
        XCTAssertEqual(QuietCut.cut(levels: [5, 1, 1, 4], from: 0), 2)   // the later of two
        XCTAssertEqual(QuietCut.cut(levels: [5, 1], from: 4), 2)
        XCTAssertEqual(QuietCut.cut(levels: [], from: 0), 0)
    }

    /// `seconds` of a steady tone at `level` (rms), or silence.
    private func audio(_ seconds: Double, level: Float = 0) -> [Float] {
        let n = Int(seconds * Double(PhraseCutter.rate))
        return (0..<n).map { i in level == 0 ? 0 : (i % 2 == 0 ? level : -level) }
    }

    func testPhraseCutterEndsAPhraseAtThePause() {
        var c = PhraseCutter(pause: 0.6)
        XCTAssertEqual(c.add(audio(2)), [])                      // quiet: nothing yet
        XCTAssertEqual(c.add(audio(1.5, level: 0.1)).count, 0)   // speaking
        let done = c.add(audio(0.9))                             // a pause ends it
        XCTAssertEqual(done.count, 1)
        // The lead of quiet, what was said, and the pause.
        XCTAssertEqual(Double(done[0].samples.count) / 16_000, 2.4, accuracy: 0.03)
        XCTAssertEqual(done[0].samples.filter { $0 != 0 }.count, Int(1.5 * 16_000))
        XCTAssertTrue(done[0].paused)
        XCTAssertFalse(c.spoke)
    }

    func testPhraseCutterKeepsEverySpokenSampleInOddSizedPieces() {
        var c = PhraseCutter(pause: 0.5, longest: 4)
        var phrases: [[Float]] = []
        let speech = audio(11, level: 0.2)
        var i = 0
        var step = 100
        while i < speech.count {
            let end = min(speech.count, i + step)
            phrases += c.add(Array(speech[i..<end])).map(\.samples)
            i = end
            step = step % 997 + 37
        }
        if let last = c.flush() { phrases.append(last) }
        let spoken = speech.count
        XCTAssertGreaterThan(phrases.count, 1)
        XCTAssertTrue(phrases.allSatisfy { Double($0.count) / 16_000 <= 4.05 })
        XCTAssertEqual(phrases.reduce(0) { $0 + $1.filter { $0 != 0 }.count }, spoken)
    }

    func testPhraseCutterFlushesOnlyWhenSomethingWasSaid() {
        var c = PhraseCutter(pause: 1)
        _ = c.add(audio(2))
        XCTAssertNil(c.flush())
        _ = c.add(audio(1) + audio(0.5, level: 0.1))
        // The speech and the bit of quiet before it.
        XCTAssertEqual(c.flush().map { Double($0.count) / 16_000 } ?? 0, 0.8, accuracy: 0.03)
    }

    func testWordRange() {
        let s = "I don't really"
        XCTAssertEqual(SpokenText.wordRange(in: s, at: 0).map { (s as NSString).substring(with: $0) }, "I")
        XCTAssertEqual(SpokenText.wordRange(in: s, at: 0.3).map { (s as NSString).substring(with: $0) }, "don't")
        XCTAssertEqual(SpokenText.wordRange(in: s, at: 1).map { (s as NSString).substring(with: $0) }, "really")
        XCTAssertNil(SpokenText.wordRange(in: "...", at: 0.5))
    }

    func testNeuralVoices() {
        XCTAssertEqual(NeuralVoice.all.filter(\.female).count, 2)
        XCTAssertEqual(NeuralVoice.all.filter { !$0.female }.count, 2)
        XCTAssertEqual(NeuralVoice.named("am_fenrir").name, "Fenrir")
        XCTAssertEqual(NeuralVoice.named("nope").id, "af_heart")
    }

    func testVoiceLineupPicksTwoWomenAndTwoMen() {
        func v(_ name: String, _ lang: String, _ q: VoiceInfo.Quality, _ female: Bool? = nil) -> VoiceInfo {
            VoiceInfo(identifier: "\(lang).\(name).\(q)", name: name, language: lang, quality: q, female: female)
        }
        let voices = [
            v("Samantha", "en-US", .standard), v("Samantha", "en-US", .enhanced), v("Ava", "en-US", .premium),
            v("Zoe", "en-US", .enhanced), v("Allison", "en-US", .enhanced),
            v("Fred", "en-US", .standard), v("Daniel", "en-GB", .standard), v("Evan", "en-US", .enhanced),
            v("Jamie", "en-GB", .premium), v("Rocko", "en-US", .standard, false),
        ]
        XCTAssertEqual(VoiceLineup.pick(voices).map(\.identifier),
                       ["en-US.Ava.premium", "en-US.Zoe.enhanced", "en-GB.Jamie.premium", "en-US.Evan.enhanced"])
    }

    func testVoiceLineupFallsBackOnWhatTheSystemSays() {
        let voices = [
            VoiceInfo(identifier: "a", name: "Amélie", language: "fr-CA", quality: .enhanced, female: true),
            VoiceInfo(identifier: "t", name: "Thomas", language: "fr-FR", quality: .standard, female: false),
            VoiceInfo(identifier: "x", name: "Mystery", language: "fr-FR", quality: .premium, female: nil),
        ]
        XCTAssertEqual(VoiceLineup.pick(voices).map(\.identifier), ["a", "t"])
    }
}
