import XCTest
import SwiftUI
@testable import ReVoxMobile

/// M10: the packing behind the Live strip, tested without a view (CI run 106 rendered the scroll-view strip blank).
final class PillFlowLayoutTests: XCTestCase {
    private func size(_ width: CGFloat, _ height: CGFloat = 44) -> CGSize { CGSize(width: width, height: height) }

    func testPillsWrapInOrderWhenTheRowIsFull() {
        let rows = PillFlowLayout.rows(sizes: [size(100), size(100), size(100), size(100)], available: 320, spacing: 6)
        XCTAssertEqual(rows.map(\.items), [[0, 1, 2], [3]], "three 100 pt pills and two gaps are 312 pt; a fourth needs 418")
        XCTAssertEqual(rows.map(\.height), [44, 44])
    }

    func testAPillWiderThanTheRowGetsARowOfItsOwnRatherThanBeingDropped() {
        let rows = PillFlowLayout.rows(sizes: [size(50), size(500), size(50)], available: 300, spacing: 6)
        XCTAssertEqual(rows.map(\.items), [[0], [1], [2]])
    }

    func testARowIsAsTallAsItsTallestPill() {
        let rows = PillFlowLayout.rows(sizes: [size(50, 44), size(50, 60), size(50, 44)], available: 300, spacing: 6)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].height, 60)
    }

    func testNoPillsMeansNoRows() {
        XCTAssertEqual(PillFlowLayout.rows(sizes: [], available: 300, spacing: 6), [])
    }

    /// The width the rows pack into: the proposal's, or everything on one row when nothing is proposed.
    func testAnUnboundedProposalPacksEverythingOnOneRow() {
        let sizes = [size(100), size(100)]
        XCTAssertEqual(PillFlowLayout.width(for: .unspecified, sizes: sizes, spacing: 6), 206)
        XCTAssertEqual(PillFlowLayout.width(for: ProposedViewSize(width: .infinity, height: nil), sizes: sizes, spacing: 6), 206)
        XCTAssertEqual(PillFlowLayout.width(for: ProposedViewSize(width: 150, height: nil), sizes: sizes, spacing: 6), 150)
    }

    /// The seven pills of the idle strip fit two rows on a 393 pt phone (361 pt inside the 16 pt margins) at the
    /// default type size. The widths are the measured ones from the simulator rounded up; the point of the test is
    /// that a change to a title or to the padding that pushes the volume or the ⓘ button onto a third row is seen.
    func testTheIdleStripIsTwoRowsOnAThreeNinetyThreePointPhone() {
        let pills = [size(66), size(104), size(96), size(106), size(124), size(72), size(44)]   // Mic, Balanced, Duck on, Learn off, Two-way off, 80%, ⓘ
        let rows = PillFlowLayout.rows(sizes: pills, available: 393 - 32, spacing: LiveControlStrip.pillSpacing)
        XCTAssertEqual(rows.count, 2, "\(rows.map(\.items))")
    }
}
