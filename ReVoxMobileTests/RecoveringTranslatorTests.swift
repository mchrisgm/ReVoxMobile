import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class RecoveringTranslatorTests: XCTestCase {
    private let hola = [WhisperSegmentSnapshot(text: " hola", noSpeechProbability: 0,
                                               tokenLogProbs: [WhisperTokenLogProb(token: 10, logProbability: -0.1)])]

    /// An engine whose `transcribe` and `detect` fail the first N times; counts loads and unloads.
    private func makeWhisper(transcribeFailures: Int = 0, detectFailures: Int = 0, failReload: Bool = false,
                             loads: LockedBox<Int>, unloads: LockedBox<Int>) -> WhisperKitTranslator {
        let segments = hola
        let remainingTranscribe = LockedBox<Int>(transcribeFailures)
        let remainingDetect = LockedBox<Int>(detectFailures)
        return WhisperKitTranslator(engine: WhisperEngine(
            load: { _ in
                var count = 0
                loads.mutate { $0 += 1; count = $0 }
                if failReload, count > 1 { throw URLError(.cannotLoadFromNetwork) }
                return 50_257
            },
            detect: { _ in
                var fail = false
                remainingDetect.mutate { if $0 > 0 { $0 -= 1; fail = true } }
                if fail { throw URLError(.timedOut) }
                return ("es", -0.1)
            },
            transcribe: { _, _ in
                var fail = false
                remainingTranscribe.mutate { if $0 > 0 { $0 -= 1; fail = true } }
                if fail { throw URLError(.timedOut) }
                return segments
            },
            unload: { unloads.mutate { $0 += 1 } }
        ))
    }

    func testFirstFailureUnloadsReloadsAndRetriesOnce() async throws {
        let loads = LockedBox<Int>(0), unloads = LockedBox<Int>(0)
        let events = LockedBox<[RecoveringTranslator.RecoveryEvent]>([])
        let whisper = makeWhisper(transcribeFailures: 1, loads: loads, unloads: unloads)
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .small) { event in
            events.mutate { $0.append(event) }
        }

        let candidate = try await translator.translate([0.1, 0.2], language: "es")
        XCTAssertEqual(candidate.segments.map(\.text), [" hola"],
                       "the adapter is a verbatim passthrough; the leading space is trimmed later, in SpeechGate.evaluate (§5.3)")
        XCTAssertEqual(unloads.value, 1)
        XCTAssertEqual(loads.value, 2, "one reload: the initial load plus the recovery load")
        XCTAssertEqual(events.value, [.reloaded])
        let count = await translator.reloadCount
        XCTAssertEqual(count, 1)
    }

    func testTheRetryFailingIsRethrownAndTheBudgetIsSpent() async throws {
        let loads = LockedBox<Int>(0), unloads = LockedBox<Int>(0)
        let events = LockedBox<[RecoveringTranslator.RecoveryEvent]>([])
        let whisper = makeWhisper(transcribeFailures: 3, loads: loads, unloads: unloads)
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .small) { event in
            events.mutate { $0.append(event) }
        }

        do {
            _ = try await translator.translate([0.1], language: "es")
            XCTFail("the retry failed too, so the error must reach the pipeline")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        do {
            _ = try await translator.translate([0.1], language: "es")
            XCTFail("the reload budget is spent")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(unloads.value, 1, "exactly one reload per run")
        XCTAssertEqual(loads.value, 2)
        XCTAssertEqual(events.value.count, 2)
        XCTAssertEqual(events.value.first, .reloaded)
        guard case .gaveUp(let reason) = events.value.last else {
            return XCTFail("expected a gaveUp event, got \(events.value)")
        }
        // `String(describing:)` resolves against the *static* type: `RecoveringTranslator.reload(after:)` holds the
        // failure as an `Error` existential, which stringifies through NSError bridging
        // ("Error Domain=NSURLErrorDomain Code=-1001"), while a concrete `URLError` stringifies as
        // "URLError(_nsError: …)". Run 33893492185 failed on exactly that difference. The invariant is that the
        // event carries a description of the error the pipeline saw, so the expectation is built the same way.
        let thrown: Error = URLError(.timedOut)
        XCTAssertEqual(reason, String(describing: thrown))
        XCTAssertTrue(reason.contains("-1001"), "the reason names the failure that was rethrown, got \(reason)")
    }

    func testAFailingReloadReportsItAndRethrowsTheOriginalError() async throws {
        let loads = LockedBox<Int>(0), unloads = LockedBox<Int>(0)
        let events = LockedBox<[RecoveringTranslator.RecoveryEvent]>([])
        let whisper = makeWhisper(transcribeFailures: 1, failReload: true, loads: loads, unloads: unloads)
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .small) { event in
            events.mutate { $0.append(event) }
        }

        do {
            _ = try await translator.translate([0.1], language: "es")
            XCTFail("the model could not be reloaded")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut, "the original failure is what the pipeline sees")
        }
        XCTAssertEqual(unloads.value, 1)
        XCTAssertEqual(loads.value, 2)
        guard case .reloadFailed = events.value.first else {
            return XCTFail("expected a reloadFailed event, got \(events.value)")
        }
    }

    func testDetectionSharesTheSameBudget() async throws {
        let loads = LockedBox<Int>(0), unloads = LockedBox<Int>(0)
        let whisper = makeWhisper(detectFailures: 1, loads: loads, unloads: unloads)
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .small)

        let detection = try await translator.detectLanguage(in: [0.1])
        XCTAssertEqual(detection.language, "es")
        XCTAssertEqual(unloads.value, 1)
        let count = await translator.reloadCount
        XCTAssertEqual(count, 1)
    }

    func testCancellationInsideTheTranslatorNeverTriggersAReload() async throws {
        let loads = LockedBox<Int>(0), unloads = LockedBox<Int>(0)
        let whisper = WhisperKitTranslator(engine: WhisperEngine(
            load: { _ in loads.mutate { $0 += 1 }; return 50_257 },
            detect: { _ in ("es", -0.1) },
            transcribe: { _, _ in throw CancellationError() },
            unload: { unloads.mutate { $0 += 1 } }
        ))
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .small)

        let candidate = try await translator.translate([0.1], language: "es")
        XCTAssertTrue(candidate.segments.isEmpty, "a stopped pipeline yields the empty candidate (§6.4)")
        XCTAssertEqual(unloads.value, 0)
        XCTAssertEqual(loads.value, 1)
    }

    func testItSatisfiesBothPipelineRoles() async throws {
        let whisper = WhisperKitTranslator(engine: WhisperEngine(
            load: { _ in 50_257 }, detect: { _ in ("fr", -0.2) }, transcribe: { _, _ in [] }, unload: {}
        ))
        try await whisper.load(progress: { _ in })
        let translator = RecoveringTranslator(whisper, reloading: whisper, model: .base)
        let detector: any LanguageDetector = translator
        let asTranslator: any Translator = translator
        let detection = try await detector.detectLanguage(in: [0.1])
        let candidate = try await asTranslator.translate([0.1], language: detection.language)
        XCTAssertEqual(candidate.language, "fr")
    }

    func testTheRecoverySinkDeliversToTheHandlerItWasGiven() {
        let sink = WhisperRecoverySink()
        let events = LockedBox<[RecoveringTranslator.RecoveryEvent]>([])
        sink.send(.reloaded)   // nobody is listening yet: dropped, never trapped
        sink.set { event in events.mutate { $0.append(event) } }
        sink.send(.reloaded)
        sink.send(.gaveUp("boom"))
        XCTAssertEqual(events.value, [.reloaded, .gaveUp("boom")])
    }
}
