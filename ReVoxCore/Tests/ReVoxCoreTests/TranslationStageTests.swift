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

    func testRejectsUnsureLanguageWhenAutoDetecting() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let result = try await stage.translate(audio)
        XCTAssertNil(result)
        let calls = await translator.calls
        XCTAssertTrue(calls.isEmpty)                             // W2: no encoder pass for a rejected language
    }

    func testLowProbabilityAcceptedWithPin() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(language: "fr", segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        let result = try await stage.translate(audio)
        XCTAssertEqual(result, Translation(english: "text", language: "fr"))
    }

    func testGatedSegmentsYieldNil() async throws {
        let translator = FakeTranslator(segments: [
            TranslationSegment(text: "ghost", noSpeechProbability: 0.99, averageLogProbability: -0.3),
        ])
        let stage = TranslationStage(detector: FakeLanguageDetector(), translator: translator, pinnedLanguage: nil)
        let result = try await stage.translate(audio)
        XCTAssertNil(result)
    }
}
