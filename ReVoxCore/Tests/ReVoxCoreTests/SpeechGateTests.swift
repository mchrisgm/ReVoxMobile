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

    // MARK: Unsure phrases (M11, §3)

    /// Not a Windows constant: the floor under which a low-log-probability segment is noise rather than a guess.
    func testGuessLogProbFloor() {
        XCTAssertEqual(SpeechGate.guessLogProbFloor, -2.5)
        XCTAssertLessThan(SpeechGate.guessLogProbFloor, SpeechGate.averageLogProbMin)
    }

    func testLanguageOutcome() {
        XCTAssertEqual(SpeechGate.languageOutcome(probability: nil), .confident)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: 0.4), .confident)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: 0.39), .unsure)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: .nan), .dropped)
        for probability in [nil, 0.4, 0.39, Float.nan] as [Float?] {
            XCTAssertEqual(SpeechGate.languagePasses(probability: probability),
                           SpeechGate.languageOutcome(probability: probability) == .confident, "\(String(describing: probability))")
        }
    }

    func testALowLogProbPhraseIsAGuessWithItsText() {
        let outcome = SpeechGate.classify(candidate([segment("noise", logProb: -2.0)]))
        XCTAssertEqual(outcome, .guess(Translation(english: "noise", language: "es", isGuess: true)))
    }

    func testAnUnsureLanguageIsAGuessEvenWithConfidentSegments() {
        let unsure = SpeechGate.classify(candidate([segment("text")], probability: 0.2))
        XCTAssertEqual(unsure, .guess(Translation(english: "text", language: "es", isGuess: true)))
        let pinned = SpeechGate.classify(candidate([segment("text")], probability: nil))
        XCTAssertEqual(pinned, .confident(Translation(english: "text", language: "es")))
    }

    /// The confident part alone is emitted, as today; the low part is discarded, never attached greyed.
    func testMixedSegmentsKeepOnlyTheConfidentPart() {
        let mixed = candidate([segment(" Hola."), segment("noise", logProb: -2.0)])
        XCTAssertEqual(SpeechGate.classify(mixed), .confident(Translation(english: "Hola.", language: "es")))
        XCTAssertEqual(SpeechGate.evaluate(mixed), Translation(english: "Hola.", language: "es"))
    }

    func testNoSpeechSegmentsNeverBecomeGuesses() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("ghost", noSpeech: 0.99, logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("ghost", noSpeech: 0.99, logProb: -0.3)])), .dropped)
    }

    /// `WhisperKitTranslator` reports −∞ for a segment with no word tokens: nothing to show, so never a guess.
    func testNoWordTokensIsNotAGuess() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("silent", logProb: -.infinity)])), .dropped)
        let mixed = SpeechGate.classify(candidate([segment("silent", logProb: -.infinity), segment("maybe", logProb: -2.0)]))
        XCTAssertEqual(mixed, .guess(Translation(english: "maybe", language: "es", isGuess: true)))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("odd", logProb: .nan)])), .dropped)
    }

    func testAGuessBelowTheFloorIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("static", logProb: -3.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("static", logProb: (-2.5 as Float).nextDown)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("edge", logProb: -2.5)])),
                       .guess(Translation(english: "edge", language: "es", isGuess: true)), "the floor itself is a guess")
    }

    func testAnEmptyOrWhitespaceGuessIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("   ", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("<|es|>", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([])), .dropped)
    }

    func testAHallucinationPhraseWithLowLogProbIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment(" Thanks for watching! ", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("you.", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("you.")], probability: 0.2)), .dropped)
    }

    func testGuessBoundaries() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept", logProb: -1.2)])), .confident(Translation(english: "kept", language: "es")))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept", logProb: (-1.2 as Float).nextDown)])),
                       .guess(Translation(english: "kept", language: "es", isGuess: true)))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept")], probability: 0.4)), .confident(Translation(english: "kept", language: "es")))
    }

    func testAGuessIsCleanedAndJoinedLikeAConfidentPhrase() {
        let outcome = SpeechGate.classify(candidate([segment(" Uno ", logProb: -2.0), segment("<|es|> dos", logProb: -2.0)]))
        XCTAssertEqual(outcome, .guess(Translation(english: "Uno dos", language: "es", isGuess: true)))
    }

    /// The case and the payload's flag say the same thing, set in one place.
    func testClassifySetsTheFlagFromTheCase() {
        guard case .guess(let guess) = SpeechGate.classify(candidate([segment("maybe", logProb: -2.0)])) else {
            return XCTFail("expected a guess")
        }
        XCTAssertTrue(guess.isGuess)
        guard case .confident(let sure) = SpeechGate.classify(candidate([segment("sure")])) else {
            return XCTFail("expected a confident phrase")
        }
        XCTAssertFalse(sure.isGuess)
    }

    /// `evaluate` is the confident case of `classify`, by construction: for every table row the two agree.
    func testEvaluateIsTheConfidentCaseOfClassify() {
        let table: [TranslationCandidate] = [
            candidate([segment(" Hola."), segment(" Buenos días.")]),
            candidate([segment("ghost", noSpeech: 0.99)]),
            candidate([segment("noise", logProb: -2.0)]),
            candidate([segment(" Thanks for watching! ")]),
            candidate([segment("text")], probability: 0.2),
            candidate([segment("text")], probability: nil),
            candidate([segment("text")], probability: .nan),
            candidate([segment("   ", logProb: -0.3), segment("gone", logProb: -3)]),
            candidate([segment("\n Uno "), segment("\tdos\r\n"), segment("   ")]),
        ]
        for row in table {
            if let translation = SpeechGate.evaluate(row) {
                XCTAssertEqual(SpeechGate.classify(row), .confident(translation), "\(row)")
            } else if case .confident = SpeechGate.classify(row) {
                XCTFail("classify is confident where evaluate is nil: \(row)")
            }
        }
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
        XCTAssertEqual(Set(object.keys), ["english", "language", "spokenLanguage", "original", "isGuess"])
    }

    /// A record written before M11 has no `isGuess` and decodes as a confident phrase; the flag round-trips.
    func testRecordsWrittenBeforeM11DecodeAsConfident() throws {
        let decoder = JSONDecoder()
        let preM11 = try decoder.decode(Translation.self, from: Data(#"{"english":"hello","language":"es","spokenLanguage":"en","original":""}"#.utf8))
        XCTAssertFalse(preM11.isGuess)
        let null = try decoder.decode(Translation.self, from: Data(#"{"english":"hello","language":"es","isGuess":null}"#.utf8))
        XCTAssertFalse(null.isGuess)
        let guess = Translation(english: "maybe", language: "es", isGuess: true)
        let data = try JSONEncoder().encode(guess)
        XCTAssertEqual(try decoder.decode(Translation.self, from: data), guess)
        XCTAssertNotEqual(guess, Translation(english: "maybe", language: "es"), "the flag is part of equality")
    }

    func testAMissingRequiredKeyThrows() {
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"language":"es"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"english":"x"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Translation.self, from: Data(#"{"english":1,"language":"es"}"#.utf8)))
    }
}
