import XCTest
@testable import ReVoxCore

/// R13 table; replaces the Windows device-resolution tests (no CUDA on iOS).
final class DeviceRecommendationTests: XCTestCase {
    private func gib(_ value: Double) -> UInt64 {
        UInt64(value * 1_073_741_824)
    }

    func testMemoryTierRoundsToNearestGiB() {
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(3.4)), 3)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(3.9)), 4)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(4.0)), 4)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(5.9)), 6)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(6.0)), 6)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(7.9)), 8)
        XCTAssertEqual(DeviceRecommendation.memoryTierGB(bytes: gib(8.0)), 8)
    }

    func testBelowFourGBRecommendsBase() {
        let recommendation = DeviceRecommendation.forPhysicalMemory(bytes: gib(3.4))
        XCTAssertEqual(recommendation.recommended, .base)
        XCTAssertEqual(recommendation.suitable, [.tiny, .base, .small])
        XCTAssertTrue(recommendation.warnings.isEmpty)
    }

    func testFourAndFiveGBRecommendSmall() {
        for value in [3.9, 4.0, 5.4] {
            let recommendation = DeviceRecommendation.forPhysicalMemory(bytes: gib(value))
            XCTAssertEqual(recommendation.recommended, .small, "\(value)")
            XCTAssertEqual(recommendation.suitable, [.tiny, .base, .small], "\(value)")
            XCTAssertTrue(recommendation.warnings.isEmpty, "\(value)")
        }
    }

    func testSixAndSevenGBAddMedium() {
        for value in [5.9, 6.0, 7.4] {
            let recommendation = DeviceRecommendation.forPhysicalMemory(bytes: gib(value))
            XCTAssertEqual(recommendation.recommended, .small, "\(value)")
            XCTAssertEqual(recommendation.suitable, [.tiny, .base, .small, .medium], "\(value)")
            XCTAssertTrue(recommendation.warnings.isEmpty, "\(value)")
        }
    }

    func testEightGBOffersAllFiveWithHeatWarnings() {
        for value in [7.9, 8.0, 12.0] {
            let recommendation = DeviceRecommendation.forPhysicalMemory(bytes: gib(value))
            XCTAssertEqual(recommendation.recommended, .small, "\(value)")
            XCTAssertEqual(recommendation.suitable, Set(WhisperModelID.allCases), "\(value)")
            XCTAssertEqual(recommendation.warnings, [.medium: DeviceRecommendation.heatWarning, .largeV3: DeviceRecommendation.heatWarning], "\(value)")
        }
        XCTAssertEqual(DeviceRecommendation.heatWarning, "Long load time and heat")
    }

    func testPocketTTSAdvisory() {
        XCTAssertNil(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 6))
        XCTAssertNil(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 8))
        XCTAssertNotNil(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 4))
        XCTAssertNotNil(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 3))
        XCTAssertEqual(DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 4),
                       "On this iPhone pocket-tts and a Whisper model share limited memory; ReVox falls back to the system voice if memory runs low.")
    }

    // MARK: M11 §5: the measured rule

    private func measured(_ model: WhisperModelID, wer: Double, rtf: Double, load: Double = 3) -> ModelBenchmarkResult {
        ModelBenchmarkResult(model: model, loadSeconds: load, firstSeconds: rtf * 2, steadySeconds: rtf, audioSeconds: 1,
                             wordErrorRate: wer, residentBeforeMB: 100, peakDeltaMB: 100, thermalState: "nominal")
    }

    func testThresholdsAreTheAssumedValues() {
        XCTAssertEqual(DeviceRecommendation.maxRealTimeFactor, 0.5)
        XCTAssertEqual(DeviceRecommendation.maxLoadSeconds, 10.0)
    }

    func testMeasuredWithNoResultsIsTheMemoryRecommendation() {
        for value in [3.4, 4.0, 6.0, 8.0] {
            let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(value))
            XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: []), memory, "\(value)")
            XCTAssertNil(DeviceRecommendation.bestMeasured(memory: memory, results: []), "\(value)")
        }
    }

    func testMeasuredPicksTheMostAccurateQualifyingModel() {
        let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(8))
        let results = [measured(.tiny, wer: 0.25, rtf: 0.05), measured(.small, wer: 0.125, rtf: 0.1), measured(.medium, wer: 0, rtf: 0.4, load: 8)]
        let recommendation = DeviceRecommendation.measured(memory: memory, results: results)
        XCTAssertEqual(recommendation.recommended, .medium)
        XCTAssertEqual(recommendation.suitable, memory.suitable, "suitable stays memory-derived")
        XCTAssertEqual(recommendation.warnings, memory.warnings, "warnings stay memory-derived")
        XCTAssertEqual(DeviceRecommendation.bestMeasured(memory: memory, results: results), .medium)
    }

    func testMeasuredNeverPromotesOutsideSuitable() {
        let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(6))
        let results = [measured(.small, wer: 0.25, rtf: 0.1), measured(.largeV3, wer: 0, rtf: 0.2)]
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: results).recommended, .small)
    }

    func testMeasuredIgnoresSlowOrSlowLoadingModels() {
        let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(8))
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: [measured(.tiny, wer: 0.25, rtf: 0.05), measured(.medium, wer: 0, rtf: 0.5)]).recommended, .tiny,
                       "0.5 exactly does not qualify")
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: [measured(.tiny, wer: 0.25, rtf: 0.05), measured(.medium, wer: 0, rtf: 0.3, load: 10)]).recommended, .tiny,
                       "10 s exactly does not qualify")
        XCTAssertFalse(DeviceRecommendation.qualifies(measured(.medium, wer: 0, rtf: 0.5)))
        XCTAssertFalse(DeviceRecommendation.qualifies(measured(.medium, wer: 0, rtf: 0.3, load: 10)))
        XCTAssertTrue(DeviceRecommendation.qualifies(measured(.medium, wer: 0, rtf: 0.49, load: 9.9)))
    }

    func testMeasuredTieBreaksOnRealTimeFactorThenCatalogueOrder() {
        let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(8))
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: [measured(.medium, wer: 0, rtf: 0.3), measured(.small, wer: 0, rtf: 0.1)]).recommended, .small)
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: [measured(.medium, wer: 0, rtf: 0.1), measured(.small, wer: 0, rtf: 0.1)]).recommended, .small,
                       "equal error and speed: the earlier catalogue entry")
    }

    func testMeasuredWithNothingQualifyingFallsBackToMemory() {
        let memory = DeviceRecommendation.forPhysicalMemory(bytes: gib(4))
        let results = [measured(.tiny, wer: 0, rtf: 0.9), measured(.small, wer: 0, rtf: 0.2, load: 30)]
        XCTAssertEqual(DeviceRecommendation.measured(memory: memory, results: results), memory)
    }

    func testQualifiesRejectsSkippedAndZeroAudio() {
        XCTAssertFalse(DeviceRecommendation.qualifies(.skipped(.tiny, reason: BenchmarkSkipReason.tooHot, thermalState: "serious")))
        let noAudio = ModelBenchmarkResult(model: .tiny, loadSeconds: 1, firstSeconds: 0, steadySeconds: 0, audioSeconds: 0,
                                           wordErrorRate: 0, residentBeforeMB: 0, peakDeltaMB: 0, thermalState: "nominal")
        XCTAssertFalse(DeviceRecommendation.qualifies(noAudio))
    }
}
