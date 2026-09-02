import XCTest
@testable import ReVoxCore

final class ReVoxCoreTests: XCTestCase {
    func testPipelineSampleRateIs16kHz() {
        XCTAssertEqual(ReVoxCore.sampleRate, 16_000)
    }
}
