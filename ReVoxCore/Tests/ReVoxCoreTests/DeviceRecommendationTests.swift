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
}
