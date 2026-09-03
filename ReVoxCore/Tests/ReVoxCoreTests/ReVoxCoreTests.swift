import XCTest
@testable import ReVoxCore

final class ReVoxCoreTests: XCTestCase {
    func testPipelineSampleRateIs16kHz() {
        XCTAssertEqual(AudioFormat.pipelineSampleRate, 16_000)
    }
}
