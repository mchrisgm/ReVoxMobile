import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class SmokeTests: XCTestCase {
    func testCoreIsLinkedIntoTheApp() {
        XCTAssertEqual(ReVoxCore.sampleRate, 16_000)
    }

    func testPinnedDependencyVersionsAreRecorded() {
        XCTAssertEqual(LinkedDependencies.whisperKitVersion, "1.1.0")
        XCTAssertEqual(LinkedDependencies.fluidAudioVersion, "0.15.6")
    }
}
