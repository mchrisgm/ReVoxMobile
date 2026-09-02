import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class SmokeTests: XCTestCase {
    func testCoreIsLinkedIntoTheApp() {
        XCTAssertEqual(ReVoxCore.sampleRate, 16_000)
    }
}
