import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class SmokeTests: XCTestCase {
    func testCoreIsLinkedIntoTheApp() {
        XCTAssertEqual(AudioFormat.pipelineSampleRate, 16_000)
    }
}
