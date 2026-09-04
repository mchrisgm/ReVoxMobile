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

    /// `Int(_: Double)` traps on NaN and on infinity, and a `Date` can carry either — a row whose timestamp came
    /// back from storage as garbage would crash the Live screen on every redraw. Nonsense reads as "now"; a huge
    /// but finite age is clamped rather than trapped.
    func testANonFiniteOrAbsurdIntervalDoesNotTrap() {
        XCTAssertEqual(RelativeAge.text(from: Date(timeIntervalSince1970: .nan), to: now), "now")
        XCTAssertEqual(RelativeAge.text(from: Date(timeIntervalSince1970: -.infinity), to: now), "now")
        XCTAssertEqual(RelativeAge.text(from: Date(timeIntervalSince1970: .infinity), to: now), "now")
        XCTAssertEqual(RelativeAge.text(from: now, to: Date(timeIntervalSince1970: .nan)), "now")
        for then in [Date(timeIntervalSince1970: -1e300), .distantPast] {
            let text = RelativeAge.text(from: then, to: now)
            XCTAssertTrue(text.hasSuffix(" h") || text.hasSuffix(" min"), text)
        }
    }

    func testAgesBeyondADayKeepCountingHours() {
        XCTAssertEqual(age(90_000), "25 h")
        XCTAssertEqual(age(90_060), "25 h 1 min")
        XCTAssertEqual(age(90_119), "25 h 1 min")
    }
}
