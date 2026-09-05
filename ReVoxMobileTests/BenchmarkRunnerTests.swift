import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// M11 §5: the runner over fakes — one model at a time with an unload between, timings from the clock, the gated
/// text scored against the reference, heat and load failures skipped, cancellation kept partial.
final class BenchmarkRunnerTests: XCTestCase {
    private var fake: FakeBenchmarkSeams!
    private var runner: BenchmarkRunner!

    override func setUp() {
        fake = FakeBenchmarkSeams()
        runner = BenchmarkRunner(seams: fake.seams)
    }

    func testRunsModelsOneAtATimeInTheGivenOrderWithUnloadBetween() async throws {
        let outcome = try await runner.run(models: [.tiny, .small]) { _ in }
        XCTAssertEqual(fake.events.value, ["load tiny", "translate tiny", "translate tiny", "unload tiny",
                                           "load small", "translate small", "translate small", "unload small"])
        XCTAssertEqual(outcome.results.map(\.model), [.tiny, .small])
        XCTAssertEqual(outcome.sentence, BenchmarkSentences.spanish)
        XCTAssertEqual(outcome.measuredCount, 2)
        XCTAssertEqual(outcome.cancelledCount, 0)
    }

    func testTimingsAndAudioSecondsAreFilledFromTheClock() async throws {
        let outcome = try await runner.run(models: [.tiny]) { _ in }
        let result = try XCTUnwrap(outcome.results.first)
        XCTAssertGreaterThanOrEqual(result.loadSeconds, 0)
        XCTAssertGreaterThanOrEqual(result.firstSeconds, 0)
        XCTAssertGreaterThanOrEqual(result.steadySeconds, 0)
        XCTAssertEqual(result.audioSeconds, 2.0, "32 000 samples at 16 kHz")
        XCTAssertTrue(result.realTimeFactor.isFinite)
        XCTAssertGreaterThanOrEqual(result.realTimeFactor, 0)
        XCTAssertEqual(result.thermalState, "nominal")
        XCTAssertNil(result.skippedReason)
    }

    func testAccuracyComesFromTheGatedTextAgainstTheReference() async throws {
        fake.setText("Good morning, where is the bus station?", for: .tiny)
        let outcome = try await runner.run(models: [.tiny, .small]) { _ in }
        XCTAssertEqual(outcome.results[0].wordErrorRate, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(outcome.results[0].hypothesis, "Good morning, where is the bus station?")
        XCTAssertEqual(outcome.results[1].wordErrorRate, 0, "small heard the reference exactly")
    }

    func testADroppedCandidateScoresOne() async throws {
        fake.setWordless(.tiny)   // no word tokens → −∞ log-probability → the gate drops it
        let outcome = try await runner.run(models: [.tiny]) { _ in }
        XCTAssertEqual(outcome.results[0].hypothesis, "")
        XCTAssertEqual(outcome.results[0].wordErrorRate, 1)
        XCTAssertNil(outcome.results[0].skippedReason, "a dropped candidate is still a measured model")
    }

    func testProgressMessagesArriveInOrder() async throws {
        let seen = LockedBox<[BenchmarkProgress]>([])
        _ = try await runner.run(models: [.tiny]) { progress in seen.mutate { $0.append(progress) } }
        XCTAssertEqual(seen.value, [.synthesising, .loading(.tiny, WhisperKitTranslator.preparingMessage), .loading(.tiny, "Loading"),
                                    .translating(.tiny, pass: 1), .translating(.tiny, pass: 2), .finished(.tiny)])
    }

    func testAHotModelIsSkippedAndTheNextStillRuns() async throws {
        fake.setThermal([.serious, .nominal])
        let seen = LockedBox<[BenchmarkProgress]>([])
        let outcome = try await runner.run(models: [.tiny, .small]) { progress in seen.mutate { $0.append(progress) } }
        XCTAssertEqual(outcome.results[0], .skipped(.tiny, reason: BenchmarkSkipReason.tooHot, thermalState: "serious"))
        XCTAssertNil(outcome.results[1].skippedReason)
        XCTAssertEqual(outcome.results[1].thermalState, "nominal")
        XCTAssertFalse(fake.events.value.contains("load tiny"), "a hot model is never loaded")
        XCTAssertTrue(seen.value.contains(.skipped(.tiny, BenchmarkSkipReason.tooHot)))
        XCTAssertEqual(outcome.measuredCount, 1)
    }

    func testALoadFailureIsRecordedAndTheRunContinues() async throws {
        fake.failLoad(of: .tiny)
        let outcome = try await runner.run(models: [.tiny, .small]) { _ in }
        XCTAssertEqual(outcome.results[0].skippedReason, "couldn't load: boom")
        XCTAssertNil(outcome.results[1].skippedReason)
        XCTAssertEqual(fake.events.value, ["load tiny", "unload tiny", "load small", "translate small", "translate small", "unload small"],
                       "unload is still attempted after a failed load")
    }

    func testCancellationDuringATranslateRecordsNoResultAndMarksTheRestCancelled() async throws {
        fake.holdTranslate(of: .tiny)
        let runner = self.runner!
        let task = Task { try await runner.run(models: [.tiny, .small, .medium]) { _ in } }
        await waitFor("tiny's first translate") { self.fake.events.value.contains("translate tiny") }
        task.cancel()
        let outcome = try await task.value
        XCTAssertEqual(outcome.results.map(\.skippedReason), [BenchmarkSkipReason.cancelled, BenchmarkSkipReason.cancelled, BenchmarkSkipReason.cancelled],
                       "an empty candidate from a cancelled decode is never scored")
        XCTAssertEqual(outcome.measuredCount, 0)
        XCTAssertEqual(outcome.cancelledCount, 3)
        XCTAssertTrue(fake.events.value.contains("unload tiny"), "the cancelled model is still unloaded")
        XCTAssertFalse(fake.events.value.contains("load small"))
    }

    func testCancellationAfterAModelKeepsItsResult() async throws {
        fake.holdTranslate(of: .small)   // tiny runs to completion; small blocks in its first translate
        let runner = self.runner!
        let task = Task { try await runner.run(models: [.tiny, .small, .medium]) { _ in } }
        await waitFor("small's translate") { self.fake.events.value.contains("translate small") }
        task.cancel()
        let outcome = try await task.value
        XCTAssertNil(outcome.results[0].skippedReason, "tiny finished before the cancel")
        XCTAssertEqual(outcome.results[1].skippedReason, BenchmarkSkipReason.cancelled)
        XCTAssertEqual(outcome.results[2].skippedReason, BenchmarkSkipReason.cancelled)
        XCTAssertEqual(outcome.measuredCount, 1)
        XCTAssertEqual(outcome.cancelledCount, 2)
    }

    func testMemoryDeltaIsTheHighestSampleAboveTheStart() async throws {
        let outcome = try await runner.run(models: [.tiny]) { _ in }
        XCTAssertEqual(outcome.results[0].residentBeforeMB, 100)
        XCTAssertEqual(outcome.results[0].peakDeltaMB, 100, "the fake adds 100 MB on load")
    }

    func testThermalTextAndTooHot() {
        XCTAssertEqual(BenchmarkRunner.thermalText(.nominal), "nominal")
        XCTAssertEqual(BenchmarkRunner.thermalText(.fair), "fair")
        XCTAssertEqual(BenchmarkRunner.thermalText(.serious), "serious")
        XCTAssertEqual(BenchmarkRunner.thermalText(.critical), "critical")
        XCTAssertFalse(BenchmarkRunner.isTooHot("nominal"))
        XCTAssertFalse(BenchmarkRunner.isTooHot("fair"))
        XCTAssertTrue(BenchmarkRunner.isTooHot("serious"))
        XCTAssertTrue(BenchmarkRunner.isTooHot("critical"))
        XCTAssertEqual(BenchmarkRunner.passes, 2)
    }

    func testNoSpeechPropagatesAndNothingIsLoaded() async {
        var seams = fake.seams
        seams.makeStimulus = { throw BenchmarkError.noSpeech }
        let runner = BenchmarkRunner(seams: seams)
        do {
            _ = try await runner.run(models: [.tiny]) { _ in }
            XCTFail("expected noSpeech")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .noSpeech)
        }
        XCTAssertEqual(fake.events.value, [])
    }

    func testASecondRunWhileOneIsInProgressIsRefused() async throws {
        fake.hold = true
        let runner = self.runner!
        let first = Task { try await runner.run(models: [.tiny]) { _ in } }
        try await Task.sleep(nanoseconds: 30_000_000)
        do {
            _ = try await runner.run(models: [.tiny]) { _ in }
            XCTFail("expected busy")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .busy)
        }
        fake.hold = false
        let outcome = try await first.value
        XCTAssertEqual(outcome.measuredCount, 1)
    }
}
