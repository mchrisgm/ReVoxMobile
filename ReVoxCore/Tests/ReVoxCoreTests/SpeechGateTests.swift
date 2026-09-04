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

    /// Windows evaluates `probability < 0.4 → drop`, which a NaN passes; here `probability >= 0.4 → keep`, which a
    /// NaN fails. The deliberate side: a detector that cannot score the language should not have its phrase
    /// translated. The app never produces one anyway (`WhisperKitTranslator.probability(fromLogProbability:)`
    /// clamps to [0, 1]), so this pins the deviation rather than a live path.
    func testANaNLanguageProbabilityIsDropped() {
        XCTAssertFalse(SpeechGate.languagePasses(probability: .nan))
        XCTAssertNil(SpeechGate.evaluate(candidate([segment("text")], probability: .nan)))
    }

    /// `strip` only touches the ends: inner punctuation, accents and combining marks survive.
    func testNormalizeStripsOnlyTheEnds() {
        XCTAssertEqual(SpeechGate.normalize("¿¡Hola!?"), "hola")
        XCTAssertEqual(SpeechGate.normalize("a.b"), "a.b")
        XCTAssertEqual(SpeechGate.normalize("e\u{301}."), "e\u{301}")
        XCTAssertEqual(SpeechGate.normalize("  You  "), "you")
        XCTAssertEqual(SpeechGate.normalize("!!!"), "")
        XCTAssertEqual(SpeechGate.normalize("Straße"), "straße")
    }

    func testSegmentsAreStrippedBeforeTheyAreJoined() {
        let result = SpeechGate.evaluate(candidate([segment("\n Uno "), segment("\tdos\r\n"), segment("   ")]))
        XCTAssertEqual(result?.english, "Uno dos")
    }
}

/// `Translation` is stored by the app (SwiftData rows and the export); records written before M8 have no
/// `spokenLanguage` and before M9 no `original`, and both must still decode.
final class TranslationCodableTests: XCTestCase {
    func testRecordsWrittenBeforeM8AndM9Decode() throws {
        let decoder = JSONDecoder()
        let preM8 = try decoder.decode(Translation.self, from: Data(#"{"english":"hello","language":"es"}"#.utf8))
        XCTAssertEqual(preM8, Translation(english: "hello", language: "es", spokenLanguage: "en", original: ""))
        let preM9 = try decoder.decode(Translation.self, from: Data(#"{"english":"hola","language":"en","spokenLanguage":"es"}"#.utf8))
        XCTAssertEqual(preM9, Translation(english: "hola", language: "en", spokenLanguage: "es", original: ""))
        let nulls = try decoder.decode(Translation.self, from: Data(#"{"english":"x","language":"fr","spokenLanguage":null,"original":null}"#.utf8))
        XCTAssertEqual(nulls.spokenLanguage, "en")
        XCTAssertEqual(nulls.original, "")
    }

    func testRoundTripKeepsEveryField() throws {
        let translation = Translation(english: "Bonjour.", language: "fr", spokenLanguage: "fr", original: "Good morning.")
        let data = try JSONEncoder().encode(translation)
        XCTAssertEqual(try JSONDecoder().decode(Translation.self, from: data), translation)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["english", "language", "spokenLanguage", "original"])
    }

    func testAMissingRequiredKeyThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"language":"es"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"english":"x"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"english":1,"language":"es"}"#.utf8)))
    }
}
