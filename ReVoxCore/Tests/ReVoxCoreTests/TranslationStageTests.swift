import XCTest
@testable import ReVoxCore

/// Mirrors the `Translator.translate` cases of `tests/pipeline/test_stt.py`.
final class TranslationStageTests: XCTestCase {
    private let audio = [Float](repeating: 0, count: 16_000)

    private func segment(_ text: String) -> TranslationSegment {
        TranslationSegment(text: text, noSpeechProbability: 0.1, averageLogProbability: -0.3)
    }

    func testJoinsSegmentsAndReportsLanguage() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Hola."), segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let result = try await stage.translate(audio)
        XCTAssertEqual(result?.english, "Hola. Buenos días.")
        XCTAssertEqual(result?.language, "es")
        let languages = await translator.languages
        XCTAssertEqual(languages, ["es"])                       // the translator received the detected language
        let detections = await detector.calls
        XCTAssertEqual(detections, 1)
    }

    func testLanguagePinPassedThrough() async throws {
        let detector = FakeLanguageDetector()
        let translator = FakeTranslator(language: "fr", segments: [segment("hi")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        _ = try await stage.translate(audio)
        let languages = await translator.languages
        XCTAssertEqual(languages, ["fr"])
        let detections = await detector.calls
        XCTAssertEqual(detections, 0)                            // the detector is not called when pinned
    }

    /// M11 (W8): an unsure language is decoded and kept as an unspoken guess. Windows dropped it; so did the port
    /// until M11 (deviation W2, which is retired for this case).
    func testAnUnsureLanguageIsDecodedAndKeptAsAnUnspokenGuess() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "text", language: "es", isGuess: true))
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.isSpoken, false, "a guess is never spoken")
        let calls = await translator.calls
        XCTAssertEqual(calls.count, 1, "the translator runs for an unsure language now")
        let translation = try await stage.translate(audio)
        XCTAssertEqual(translation?.isGuess, true)
    }

    /// The one language score that still skips the decode: a NaN cannot be placed above or below any floor.
    func testANaNLanguageScoreIsDroppedBeforeTheTranslatorRuns() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: .nan)
        let translator = FakeTranslator(segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let result = try await stage.route(audio)
        XCTAssertNil(result)
        let calls = await translator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testALowLogProbPhraseIsAnUnspokenGuess() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(segments: [
            TranslationSegment(text: " maybe", noSpeechProbability: 0.1, averageLogProbability: -2.0),
        ])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "maybe", language: "es", isGuess: true))
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.isSpoken, false)
    }

    func testLowProbabilityAcceptedWithPin() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(language: "fr", segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        let result = try await stage.translate(audio)
        XCTAssertEqual(result, Translation(english: "text", language: "fr"))
        XCTAssertEqual(result?.isGuess, false)
    }

    /// A pinned language is never detected, so the detector's doubt cannot make it a guess: the phrase is spoken.
    func testAPinnedLanguageNeverYieldsALanguageGuess() async throws {
        let detector = FakeLanguageDetector(language: "de", probability: 0.05)
        let translator = FakeTranslator(language: "fr", segments: [segment(" Yes.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Yes.", language: "fr"))
        XCTAssertEqual(routed?.isSpoken, true)
        let detections = await detector.calls
        XCTAssertEqual(detections, 0)
    }

    func testGatedSegmentsYieldNil() async throws {
        let translator = FakeTranslator(segments: [
            TranslationSegment(text: "ghost", noSpeechProbability: 0.99, averageLogProbability: -0.3),
        ])
        let stage = TranslationStage(detector: FakeLanguageDetector(), translator: translator, pinnedLanguage: nil)
        let result = try await stage.translate(audio)
        XCTAssertNil(result)
    }

    // MARK: Ignored language and two-way routing (M8, §8.2)

    private actor FakeTranscriber: Transcriber {
        private(set) var calls: [String] = []
        private let segments: [TranslationSegment]
        init(segments: [TranslationSegment]) { self.segments = segments }
        func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate {
            calls.append(language)
            return TranslationCandidate(language: language, languageProbability: nil, segments: segments)
        }
    }

    private actor FakeSecondary: SecondaryTranslator {
        private(set) var calls: [String] = []
        private let result: String?
        init(result: String?) { self.result = result }
        func translate(_ text: String, from source: String, to target: String) async throws -> String? {
            calls.append("\(source)->\(target): \(text)")
            return result
        }
    }

    func testTheIgnoredLanguageIsNeitherTranslatedNorTranscribedWithTwoWayOff() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("should never be produced")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     ignoredLanguage: "en", twoWay: false)
        let routed = try await stage.route(audio)
        XCTAssertNil(routed, "the ignored language is dropped before anything is translated")
        let languages = await translator.languages
        XCTAssertEqual(languages, [], "the translator is never called for an ignored phrase")
    }

    /// M11: an unsure detection may be the language the user asked ReVox to leave alone (the detector scored
    /// English as "de" at 0.3, say), so while a language is ignored it is dropped — with two-way off and on.
    func testAnUnsureDetectionIsDroppedWhileALanguageIsIgnored() async throws {
        for twoWay in [false, true] {
            let detector = FakeLanguageDetector(language: "de", probability: 0.3)
            let translator = FakeTranslator(language: "de", segments: [segment("must not be decoded")])
            let transcriber = FakeTranscriber(segments: [segment("must not be decoded either")])
            let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                         transcriber: transcriber, secondary: FakeSecondary(result: "unused"),
                                         ignoredLanguage: "en", twoWay: twoWay, targetLanguage: "es")
            let routed = try await stage.route(audio)
            XCTAssertNil(routed, "twoWay \(twoWay)")
            let languages = await translator.languages
            XCTAssertEqual(languages, [], "twoWay \(twoWay)")
            let transcribed = await transcriber.calls
            XCTAssertEqual(transcribed, [], "twoWay \(twoWay)")
        }
        // The unsure code equal to the ignored one is dropped too, not handed to the second direction.
        let detector = FakeLanguageDetector(language: "en", probability: 0.2)
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: FakeTranslator(language: "en"), pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "Buenos días."),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertNil(routed)
        let transcribed = await transcriber.calls
        XCTAssertEqual(transcribed, [])
    }

    /// The second direction keeps using `evaluate`: nothing unsure is ever spoken to the other person.
    func testTheSecondDirectionNeverProducesAGuess() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let low = TranslationSegment(text: " Good morning.", noSpeechProbability: 0.1, averageLogProbability: -2.0)
        let transcriber = FakeTranscriber(segments: [low])
        let stage = TranslationStage(detector: detector, translator: FakeTranslator(language: "en", segments: [low]), pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "Buenos días."),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertNil(routed, "a low-log-probability transcription is dropped, not guessed")
        let intoEnglish = TranslationStage(detector: detector, translator: FakeTranslator(language: "en", segments: [low]), pinnedLanguage: nil,
                                           ignoredLanguage: "en", twoWay: true, targetLanguage: "en")
        let english = try await intoEnglish.route(audio)
        XCTAssertNil(english, "the English target path uses evaluate too")
    }

    func testAnotherLanguageIsStillTranslatedWhileALanguageIsIgnored() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment("Good morning")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     ignoredLanguage: "en", twoWay: false)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning", language: "es", spokenLanguage: "en"))
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.isSpoken, true)
    }

    func testTwoWayTranscribesTheIgnoredLanguageAndTranslatesItIntoTheTarget() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("the translate task must not be used")])
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let secondary = FakeSecondary(result: "Buenos días.")
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: secondary,
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Buenos días.", language: "es", spokenLanguage: "es"),
                       "the row is tagged with the language it is written in, so the transcript reads as the conversation did")
        XCTAssertEqual(routed?.route, .toTarget("es"))
        XCTAssertEqual(routed?.isSpoken, true)
        let transcribed = await transcriber.calls
        XCTAssertEqual(transcribed, ["en"], "the words are taken as spoken, not translated to English first")
        let secondaryCalls = await secondary.calls
        XCTAssertEqual(secondaryCalls, ["en->es: Good morning."])
        let translateCalls = await translator.languages
        XCTAssertEqual(translateCalls, [], "Whisper's translate task has no part in the second direction")
    }

    func testTwoWayWithoutAnEngineStillTranscribesButSaysNothing() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("unused")])
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: nil,
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning.", language: "en", spokenLanguage: "en"))
        XCTAssertEqual(routed?.route, .transcribedOnly(reason: TranslationStage.noEngineReason))
        XCTAssertEqual(routed?.isSpoken, false, "the transcript keeps it; the voice does not say it")
    }

    func testTwoWayWithAnEngineThatHasNoSuchPairIsTranscribedOnlyWithThatReason() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("unused")])
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: nil),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "cy")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.route, .transcribedOnly(reason: TranslationStage.unavailablePairReason(from: "en", to: "cy")))
        XCTAssertEqual(routed?.isSpoken, false)
        XCTAssertEqual(TranslationStage.unavailablePairReason(from: "en", to: "cy"), "No on-device translation from en to cy")
    }

    /// English as the target needs no second engine: Whisper's translate task already produces English, so the
    /// second direction is the ordinary path and costs nothing extra.
    func testTwoWayIntoEnglishUsesWhispersOwnTranslateTask() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment("must not be used")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "unused"),
                                     ignoredLanguage: "es", twoWay: true, targetLanguage: "en")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning.", language: "es", spokenLanguage: "en"))
        XCTAssertEqual(routed?.route, .toEnglish)
        let transcribed = await transcriber.calls
        XCTAssertEqual(transcribed, [])
        let translateCalls = await translator.languages
        XCTAssertEqual(translateCalls, ["es"])
    }

    /// The one-way path must be bit-for-bit what it was before M8 when nothing is configured.
    func testWithNoIgnoredLanguageNothingChanges() async throws {
        let detector = FakeLanguageDetector(language: "fr", probability: 0.9)
        let translator = FakeTranslator(language: "fr", segments: [segment(" Yes.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.translation.spokenLanguage, "en")
    }

    func testTheSecondDirectionsTextIsCleanedToo() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("unused")])
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "<|es|>  Buenos días. "),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.english, "Buenos días.")
    }

    /// A host without a transcribe seam falls back to Whisper's translate task for the second direction, whose
    /// output is English whatever was spoken. That English used to be handed to the secondary engine labelled as
    /// the ignored language ("de" here), so an engine that trusts the source code — Apple's does — translated
    /// English as if it were German. The fallback must say what it produced.
    func testWithoutATranscriberTheFallbackHandsTheSecondaryEnglishAndSaysSo() async throws {
        let detector = FakeLanguageDetector(language: "de", probability: 0.95)
        let translator = FakeTranslator(language: "de", segments: [segment(" Good morning.")])
        let secondary = FakeSecondary(result: "Bonjour.")
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: nil, secondary: secondary,
                                     ignoredLanguage: "de", twoWay: true, targetLanguage: "fr", wantsOriginal: true)
        let routed = try await stage.route(audio)
        let secondaryCalls = await secondary.calls
        XCTAssertEqual(secondaryCalls, ["en->fr: Good morning."], "the translate task produced English")
        XCTAssertEqual(routed?.translation, Translation(english: "Bonjour.", language: "fr", spokenLanguage: "fr", original: ""),
                       "the fallback never had the words as spoken, so Learning mode gets no original from it")
        XCTAssertEqual(routed?.route, .toTarget("fr"))
    }

    /// The same fallback with no engine at all: the transcript-only row holds English text, so it is tagged as
    /// English — a `[de]` badge over "Good morning." would be a lie about what the row says.
    func testWithoutATranscriberOrAnEngineTheTranscriptOnlyRowIsTaggedAsTheEnglishItHolds() async throws {
        let detector = FakeLanguageDetector(language: "de", probability: 0.95)
        let translator = FakeTranslator(language: "de", segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: nil, secondary: nil,
                                     ignoredLanguage: "de", twoWay: true, targetLanguage: "fr")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning.", language: "en", spokenLanguage: "en"))
        XCTAssertEqual(routed?.route, .transcribedOnly(reason: TranslationStage.noEngineReason))
        XCTAssertEqual(routed?.isSpoken, false)
    }

    // MARK: Learning mode (M9)

    private actor FailingTranscriber: Transcriber {
        func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate {
            throw CancellationError()
        }
    }

    func testLearningTranscribesTheWordsAsSpokenNextToTheTranslation() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos"), segment(" días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.english, "Good morning.")
        XCTAssertEqual(routed?.translation.original, "Buenos días.")
        XCTAssertEqual(routed?.route, .toEnglish)
        let calls = await transcriber.calls
        XCTAssertEqual(calls, ["es"])
    }

    func testLearningNeverTranscribesEnglishTwice() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment("must not be used")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.original, "Good morning.", "the translation is the words")
        let calls = await transcriber.calls
        XCTAssertEqual(calls, [], "no second decode for English")
    }

    func testWithoutLearningTheTranscriberIsNeverCalled() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.original, "")
        let calls = await transcriber.calls
        XCTAssertEqual(calls, [], "learning costs a second decode per phrase, so it is never run unasked")
    }

    /// Doubtful audio is not decoded a second time: a guess has no original even with Learning on.
    func testALearningGuessIsNotTranscribedTwice() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning.", language: "es", original: "", isGuess: true))
        let calls = await transcriber.calls
        XCTAssertEqual(calls, [])
    }

    /// The confident path is exactly what it was before M11.
    func testAConfidentPhraseIsExactlyWhatItWas() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed, RoutedTranslation(translation: Translation(english: "Good morning.", language: "es", spokenLanguage: "en",
                                                                          original: "Buenos días.", isGuess: false),
                                                 route: .toEnglish, isSpoken: true))
    }

    func testATranscribeFailureCostsOnlyTheOriginal() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: FailingTranscriber(), wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.english, "Good morning.", "learning must never lose a phrase")
        XCTAssertEqual(routed?.translation.original, "")
    }

    func testTheSecondDirectionKeepsTheWordsItTranscribedAnyway() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let translator = FakeTranslator(language: "en", segments: [segment("unused")])
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let secondary = FakeSecondary(result: "Buenos días.")
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: secondary,
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es", wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation.original, "Good morning.")
        XCTAssertEqual(routed?.translation.english, "Buenos días.")
        let calls = await transcriber.calls
        XCTAssertEqual(calls, ["en"], "one transcribe serves both the reply and Learning mode")
    }

    // MARK: the public `translate` wrapper and a degenerate configuration

    func testTranslateIsTheRoutedTranslationWithoutTheRoute() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Hola.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let translation = try await stage.translate(audio)
        let routed = try await stage.route(audio)
        XCTAssertEqual(translation, routed?.translation)
        XCTAssertEqual(translation, Translation(english: "Hola.", language: "es"))

        let ignoring = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil, ignoredLanguage: "es")
        let dropped = try await ignoring.translate(audio)
        XCTAssertNil(dropped)
    }

    /// Pinning the very language that is ignored, with two-way off, drops every phrase before any engine runs:
    /// the configuration is self-defeating and the settings screen should refuse it, but the stage stays honest.
    func testAPinnedLanguageThatIsAlsoIgnoredDropsEveryPhraseWithTwoWayOff() async throws {
        let detector = FakeLanguageDetector(language: "fr", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment("never")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "es",
                                     ignoredLanguage: "es", twoWay: false)
        let routed = try await stage.route(audio)
        XCTAssertNil(routed)
        let detections = await detector.calls
        XCTAssertEqual(detections, 0)
        let translations = await translator.calls
        XCTAssertTrue(translations.isEmpty)
    }
}
