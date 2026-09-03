import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class DeviceInfoTests: XCTestCase {
    func testTierAndRecommendationFollowCore() {
        let sixGiB = DeviceInfo(physicalMemoryBytes: 6 * 1_073_741_824)
        XCTAssertEqual(sixGiB.memoryTierGB, 6)
        XCTAssertEqual(sixGiB.recommendation, DeviceRecommendation.forPhysicalMemory(bytes: 6 * 1_073_741_824))
        XCTAssertEqual(sixGiB.recommendation.recommended, .small)
        XCTAssertTrue(sixGiB.recommendation.suitable.contains(.medium))

        // physicalMemory reports a few hundred MB below the nominal size; rounding absorbs it (§5.6).
        let almostFour = DeviceInfo(physicalMemoryBytes: 4 * 1_073_741_824 - 300_000_000)
        XCTAssertEqual(almostFour.memoryTierGB, 4)
        XCTAssertEqual(almostFour.recommendation.recommended, .small)
    }

    func testCurrentReadsProcessInfo() {
        let info = DeviceInfo.current()
        XCTAssertEqual(info.physicalMemoryBytes, ProcessInfo.processInfo.physicalMemory)
        XCTAssertGreaterThan(info.memoryTierGB, 0)
    }
}
