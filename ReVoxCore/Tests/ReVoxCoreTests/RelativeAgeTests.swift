import XCTest
@testable import ReVoxCore

final class RelativeAgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func age(_ seconds: TimeInterval) -> String {
        RelativeAge.text(from: now.addingTimeInterval(-seconds), to: now)
    }

    func testUnderASecondIsNow() {
        XCTAssertEqual(age(0), "now")
        XCTAssertEqual(age(0.4), "now")
        XCTAssertEqual(age(0.99), "now")
    }

    func testSecondsThenMinutesThenHours() {
        XCTAssertEqual(age(1), "1 s")
        XCTAssertEqual(age(12), "12 s")
        XCTAssertEqual(age(59.9), "59 s")
        XCTAssertEqual(age(60), "1 min")
        XCTAssertEqual(age(61), "1 min")
        XCTAssertEqual(age(3_599), "59 min")
        XCTAssertEqual(age(3_600), "1 h")
        XCTAssertEqual(age(3_900), "1 h 5 min")
        XCTAssertEqual(age(7_200), "2 h")
    }

    func testAFutureTimestampReadsAsNow() {
        XCTAssertEqual(age(-5), "now", "a skewed clock must not produce a negative age")
    }
}
