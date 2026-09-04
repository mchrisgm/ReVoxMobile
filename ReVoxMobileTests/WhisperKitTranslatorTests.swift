import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class WhisperKitTranslatorTests: XCTestCase {
    private func engine(specialTokenBegin: Int = 50_257,
                        detect: @escaping @Sendable ([Float]) async throws -> (language: String, logProbability: Float) = { _ in ("es", -0.1) },
                        transcribe: @escaping @Sendable ([Float], WhisperDecodingSpec) async throws -> [WhisperSegmentSnapshot] = { _, _ in [] },
                        unloads: LockedBox<Int> = LockedBox(0)) -> WhisperEngine {
        WhisperEngine(
            load: { progress in progress("Specializing"); progress("Loading"); return specialTokenBegin },
            detect: detect,
            transcribe: transcribe,
            unload: { unloads.mutate { $0 += 1 } }
        )
    }

    func testDecodingSpecIsTheR3OptionSetVerbatim() {
        let spec = WhisperDecodingSpec(language: "fr")
        XCTAssertEqual(spec.task, "translate")
        XCTAssertEqual(spec.language, "fr")
        XCTAssertEqual(spec.temperature, 0)
        XCTAssertEqual(spec.temperatureFallbackCount, 0)
        XCTAssertTrue(spec.usePrefillPrompt)
        XCTAssertFalse(spec.detectLanguage)
        XCTAssertTrue(spec.skipSpecialTokens)
        XCTAssertTrue(spec.withoutTimestamps)
        XCTAssertFalse(spec.wordTimestamps)
        XCTAssertEqual(spec.windowClipTime, 0)
        XCTAssertNil(spec.compressionRatioThreshold)
        XCTAssertNil(spec.logProbThreshold)
        XCTAssertNil(spec.firstTokenLogProbThreshold)
        XCTAssertNil(spec.noSpeechThreshold)
        XCTAssertEqual(spec.chunkingStrategy, "none")
    }

    /// M8's second direction is the same decode with Whisper's other task; nothing else about R3 moves.
    func testTheTranscribeTaskChangesOnlyTheTask() {
        let translate = WhisperDecodingSpec(language: "es")
        let transcribe = WhisperDecodingSpec(language: "es", task: "transcribe")
        XCTAssertEqual(transcribe.task, "transcribe")
        var asTranslate = transcribe
        asTranslate.task = translate.task
        XCTAssertEqual(asTranslate, translate, "only `task` differs between the two specs")
    }

    func testTranscribeAsksWhisperForTheTranscribeTaskAndTranslateForTranslate() async throws {
        let tasks = LockedBox<[String]>([])
        let translator = WhisperKitTranslator(engine: engine(transcribe: { _, spec in
            tasks.mutate { $0.append(spec.task) }
            return [WhisperSegmentSnapshot(text: " Buenos días.", noSpeechProbability: 0, tokenLogProbs: [WhisperTokenLogProb(token: 10, logProbability: -0.1)])]
        }))
        try await translator.load(progress: { _ in })
        _ = try await translator.translate([0, 0, 0], language: "es")
        let transcribed = try await translator.transcribe([0, 0, 0], language: "es")
        XCTAssertEqual(tasks.value, ["translate", "transcribe"])
        XCTAssertEqual(transcribed.segments.first?.text, " Buenos días.")
        XCTAssertEqual(transcribed.language, "es")
    }

    func testLanguageProbabilityIsExpOfTheLogProbabilityClamped() {
        XCTAssertEqual(WhisperKitTranslator.probability(fromLogProbability: 0), 1)
        XCTAssertEqual(WhisperKitTranslator.probability(fromLogProbability: -0.916_29), 0.4, accuracy: 0.001)
        XCTAssertEqual(WhisperKitTranslator.probability(fromLogProbability: 0.5), 1, "clamped")
        XCTAssertEqual(WhisperKitTranslator.probability(fromLogProbability: -.infinity), 0)
    }

    func testAverageLogProbabilityIgnoresSpecialTokens() {
        let begin = 50_257
        let tokens = [
            WhisperTokenLogProb(token: 50_258, logProbability: 0),     // <|sot|>, excluded
            WhisperTokenLogProb(token: 100, logProbability: -0.5),
            WhisperTokenLogProb(token: 200, logProbability: -1.5),
            WhisperTokenLogProb(token: 50_257, logProbability: 0),     // <|endoftext|>, excluded
        ]
        XCTAssertEqual(WhisperKitTranslator.averageLogProbability(of: tokens, specialTokenBegin: begin), -1.0, accuracy: 0.0001)
        XCTAssertEqual(WhisperKitTranslator.averageLogProbability(of: [WhisperTokenLogProb(token: 50_258, logProbability: 0)], specialTokenBegin: begin), -.infinity)
        XCTAssertEqual(WhisperKitTranslator.averageLogProbability(of: [], specialTokenBegin: begin), -.infinity)
    }

    func testDetectLanguageUsesExpAndTranslatePassesTheLanguageThrough() async throws {
        let specs = LockedBox<[WhisperDecodingSpec]>([])
        let translator = WhisperKitTranslator(engine: engine(
            detect: { _ in ("de", -0.223_14) },
            transcribe: { _, spec in
                specs.mutate { $0.append(spec) }
                return [
                    WhisperSegmentSnapshot(text: " Hello.", noSpeechProbability: 0, tokenLogProbs: [
                        WhisperTokenLogProb(token: 50_258, logProbability: 0), WhisperTokenLogProb(token: 10, logProbability: -0.2), WhisperTokenLogProb(token: 11, logProbability: -0.4),
                    ]),
                    WhisperSegmentSnapshot(text: " World.", noSpeechProbability: 0, tokenLogProbs: [WhisperTokenLogProb(token: 50_257, logProbability: 0)]),
                ]
            }))
        try await translator.load { _ in }
        let loaded = await translator.isLoaded
        XCTAssertTrue(loaded)

        let detection = try await translator.detectLanguage(in: [0.1, 0.2])
        XCTAssertEqual(detection.language, "de")
        XCTAssertEqual(detection.probability, 0.8, accuracy: 0.001)

        let candidate = try await translator.translate([0.1, 0.2], language: "de")
        XCTAssertEqual(candidate.language, "de")
        XCTAssertNil(candidate.languageProbability, "the stage attaches the detection probability, not the adapter")
        XCTAssertEqual(candidate.segments.count, 2)
        XCTAssertEqual(candidate.segments[0].text, " Hello.")
        XCTAssertEqual(candidate.segments[0].noSpeechProbability, 0)
        XCTAssertEqual(candidate.segments[0].averageLogProbability, -0.3, accuracy: 0.0001)
        XCTAssertEqual(candidate.segments[1].averageLogProbability, -.infinity, "no word tokens → dropped by the gate")
        XCTAssertEqual(specs.value.map(\.language), ["de"])
        XCTAssertEqual(specs.value.first, WhisperDecodingSpec(language: "de"))
    }

    func testLoadReportsPreparingMessagesAndIsIdempotent() async throws {
        let messages = LockedBox<[String]>([])
        let translator = WhisperKitTranslator(engine: engine())
        try await translator.load { message in messages.mutate { $0.append(message) } }
        try await translator.load { message in messages.mutate { $0.append(message) } }
        XCTAssertEqual(messages.value, [WhisperKitTranslator.preparingMessage, "Specializing", "Loading"], "second load is a no-op")
    }

    func testCancellationIsSwallowedIntoAnEmptyCandidate() async throws {
        let translator = WhisperKitTranslator(engine: engine(transcribe: { _, _ in throw CancellationError() }))
        try await translator.load { _ in }
        let candidate = try await translator.translate([0], language: "es")
        XCTAssertEqual(candidate.segments, [])
        XCTAssertEqual(candidate.language, "es")
    }

    func testOtherErrorsPropagate() async throws {
        struct Boom: Error {}
        let translator = WhisperKitTranslator(engine: engine(transcribe: { _, _ in throw Boom() }))
        try await translator.load { _ in }
        do {
            _ = try await translator.translate([0], language: "es")
            XCTFail("expected the error to propagate")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testTranslateBeforeLoadThrowsNotLoaded() async {
        let translator = WhisperKitTranslator(engine: engine())
        do {
            _ = try await translator.translate([0], language: "es")
            XCTFail("expected notLoaded")
        } catch {
            XCTAssertEqual(error as? WhisperTranslatorError, .notLoaded)
        }
    }

    func testUnloadForwardsAndClearsLoadedState() async throws {
        let unloads = LockedBox(0)
        let translator = WhisperKitTranslator(engine: engine(unloads: unloads))
        try await translator.load { _ in }
        await translator.unload()
        let loaded = await translator.isLoaded
        XCTAssertFalse(loaded)
        XCTAssertEqual(unloads.value, 1)
    }

    func testFirstTokenThresholdOverrideReachesTheSpec() async throws {
        let specs = LockedBox<[WhisperDecodingSpec]>([])
        let translator = WhisperKitTranslator(engine: engine(transcribe: { _, spec in specs.mutate { $0.append(spec) }; return [] }))
        try await translator.load { _ in }
        await translator.setFirstTokenLogProbThreshold(-1.5)
        _ = try await translator.translate([0], language: "es")
        XCTAssertEqual(specs.value.first?.firstTokenLogProbThreshold, -1.5)
    }
}
