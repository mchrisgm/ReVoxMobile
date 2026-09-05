import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: the word chips, the popover and the dictionary sheet lay out in a `UIHostingController` at the
/// default and the largest accessibility text sizes, with the inert default lookup and with injected services.
/// SwiftUI has no unit-test renderer, so this proves the views build and do not trap on first layout — the bar
/// `ScreenHostingTests` holds every other screen to.
@MainActor
final class LearningHostingTests: XCTestCase {
    private let sentence = "Buenos días, gracias por acompañarnos hoy."
    private let english = "Good morning, thank you for joining us today."

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    // MARK: WordFlowLayout

    /// `PillFlowLayout`'s greedy in-order packing, copied with no gap: three 100 pt chips are 300 pt, a fourth
    /// needs 400 and wraps; an over-wide chip still gets a row of its own; a row is as tall as its tallest chip.
    func testWordFlowLayoutPacksLikeThePillLayoutWithNoGap() {
        func size(_ width: CGFloat, _ height: CGFloat = 44) -> CGSize { CGSize(width: width, height: height) }
        XCTAssertEqual(WordFlowLayout.spacing, 0)
        let rows = WordFlowLayout.rows(sizes: [size(100), size(100), size(100), size(100)], available: 320)
        XCTAssertEqual(rows.map(\.items), [[0, 1, 2], [3]])
        XCTAssertEqual(rows.map(\.height), [44, 44])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50), size(500), size(50)], available: 300).map(\.items), [[0], [1], [2]])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50, 44), size(50, 60)], available: 300)[0].height, 60)
        XCTAssertEqual(WordFlowLayout.rows(sizes: [], available: 300), [])
        XCTAssertEqual(WordFlowLayout.width(for: .unspecified, sizes: [size(100), size(100)]), 200)
        XCTAssertEqual(WordFlowLayout.width(for: ProposedViewSize(width: 150, height: nil), sizes: [size(100), size(100)]), 150)
    }

    func testWordFlowLayoutHostsInsideABaselineAlignedRow() {
        host(WordFlowLayout {
            Text("Buenos").font(.body)
            Text("días").font(.body)
        })
        host(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("10:41:07").font(.caption.monospacedDigit())
            WordFlowLayout {
                ForEach(0..<12, id: \.self) { index in
                    Text("palabra\(index)").font(.body).frame(minHeight: 44)
                }
            }
        }
        .frame(width: 390))
    }
}
