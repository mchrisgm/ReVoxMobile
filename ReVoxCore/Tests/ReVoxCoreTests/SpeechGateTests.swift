import XCTest
@testable import ReVoxCore

/// Mirrors the gate cases of `tests/pipeline/test_stt.py`.
final class SpeechGateTests: XCTestCase {
    private func candidate(_ segments: [TranslationSegment], language: String = "es", probability: Float? = 0.95) -> TranslationCandidate {
        TranslationCandidate(language: language, languageProbability: probability, segments: segments)
    }

    private func segment(_ text: String, noSpeech: Float = 0.1, logProb: Float = -0.3) -> TranslationSegment {
        TranslationSegment(text: text, noSpeechProbability: noSpeech, averageLogProbability: logProb)
    }

    func testConstants() {
        XCTAssertEqual(SpeechGate.noSpeechMax, 0.85)
        XCTAssertEqual(SpeechGate.averageLogProbMin, -1.2)
        XCTAssertEqual(SpeechGate.languageProbMin, 0.4)
        XCTAssertEqual(SpeechGate.hallucinationPhrases, [
            "", "you", "thanks for watching", "thank you for watching",
            "subtitles by the amara.org community", "subscribe",
        ])
        XCTAssertEqual(SpeechGate.hallucinationPhrases.count, 6)
    }

    func testStrippedCharacterSet() {
        let set = SpeechGate.strippedCharacters
        XCTAssertEqual(set.count, 40)
        for scalar in "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars {   // the 32 ASCII punctuation characters
            XCTAssertTrue(set.contains(Character(scalar)), "missing \(scalar)")
        }
        for whitespace in [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"] as [Character] {   // the 6 Python whitespace characters
            XCTAssertTrue(set.contains(whitespace))
        }
        XCTAssertTrue(set.contains("¡"))
        XCTAssertTrue(set.contains("¿"))
        XCTAssertFalse(set.contains("a"))
    }

    func testJoinsSegmentsAndReportsLanguage() {
        let result = SpeechGate.evaluate(candidate([segment(" Hola."), segment(" Buenos días.")]))
        XCTAssertEqual(result, Translation(english: "Hola. Buenos días.", language: "es"))
    }

    func testRejectsHighNoSpeechProbability() {
        XCTAssertNil(SpeechGate.evaluate(candidate([segment("ghost", noSpeech: 0.99)])))
        XCTAssertNotNil(SpeechGate.evaluate(candidate([segment("kept", noSpeech: 0.85)])))   // boundary: > drops
    }

    func testRejectsLowAverageLogProbability() {
        XCTAssertNil(SpeechGate.evaluate(candidate([segment("noise", logProb: -2.5)])))
        XCTAssertNotNil(SpeechGate.evaluate(candidate([segment("kept", logProb: -1.2)])))    // boundary: < drops
    }

    func testRejectsHallucinationPhrases() {
        XCTAssertNil(SpeechGate.evaluate(candidate([segment(" Thanks for watching! ")])))
    }

    func testNormalization() {
        XCTAssertEqual(SpeechGate.normalize("¿Subscribe?"), "subscribe")
        XCTAssertEqual(SpeechGate.normalize("SUBSCRIBE..."), "subscribe")
        XCTAssertEqual(SpeechGate.normalize("you."), "you")
        XCTAssertEqual(SpeechGate.normalize(""), "")
        XCTAssertEqual(SpeechGate.normalize("\r\n Hi there! \r\n"), "hi there")
        XCTAssertEqual(SpeechGate.normalize("you know"), "you know")
        for rejected in ["¿Subscribe?", "SUBSCRIBE...", "you.", ""] {
            XCTAssertNil(SpeechGate.evaluate(candidate([segment(rejected)])), rejected)
        }
        XCTAssertEqual(SpeechGate.evaluate(candidate([segment("you know")]))?.english, "you know")
    }

    func testLanguageGate() {
        XCTAssertTrue(SpeechGate.languagePasses(probability: nil))
        XCTAssertTrue(SpeechGate.languagePasses(probability: 0.4))
        XCTAssertFalse(SpeechGate.languagePasses(probability: 0.39))
        XCTAssertNil(SpeechGate.evaluate(candidate([segment("text")], probability: 0.2)))
        XCTAssertNotNil(SpeechGate.evaluate(candidate([segment("text")], probability: nil)))   // pinned: gate skipped
    }

    func testEmptyAfterSegmentGatesIsDropped() {
        XCTAssertNil(SpeechGate.evaluate(candidate([segment("   ", logProb: -0.3), segment("gone", logProb: -3)])))
    }
}
