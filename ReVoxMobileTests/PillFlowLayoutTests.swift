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

    // MARK: M11 — one captioned row per group on a 393 pt phone (361 pt inside the margins)

    /// The width a pill or caption renders at on this simulator at the default type size — measured here rather
    /// than typed in, so a title, padding or font change moves the packing with it. The M10 numbers CI run 107
    /// measured were Mic 66, Balanced 108, ⓘ 44, Duck on 102, 100% 92, Two-way off 132, Learn off 106; the pair
    /// pills are estimated at You speak English 150 and They speak Spanish 161, and the failure message prints
    /// what CI actually measured.
    @MainActor private func width<V: View>(_ view: V) -> CGFloat {
        let controller = UIHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: 1_000, height: LiveControlPill.minimumHeight)).width.rounded(.up)
    }

    private static let phone: CGFloat = 393 - 32
    private static let narrowPhone: CGFloat = 320 - 32

    @MainActor func testEachIdleGroupIsOneRowOnAThreeNinetyThreePointPhone() {
        let caption = width(LiveGroupCaption(title: LiveControlStrip.languagesCaption))
        XCTAssertEqual(caption, LiveControlStrip.captionColumnWidth, "the longest caption fits the fixed column")
        let listen = [caption, width(LiveControlPill(systemImage: "mic", title: "Mic")),
                      width(LiveControlPill(systemImage: LiveControlStrip.latencySymbol(for: .balanced), title: "Balanced")),
                      LiveControlPill.minimumHeight].map { size($0) }
        let voice = [caption, width(LiveControlPill(systemImage: "waveform.badge.minus", title: "Duck on", isOn: true)),
                     width(LiveControlPill(systemImage: "speaker.wave.3", title: "100%"))].map { size($0) }
        let languages = [caption, width(LiveControlPill(systemImage: "arrow.left.arrow.right", title: "Two-way off")),
                         width(LiveControlPill(systemImage: "text.book.closed", title: "Learn off"))].map { size($0) }
        for (name, group) in [("Listen", listen), ("Voice", voice), ("Languages", languages)] {
            let rows = PillFlowLayout.rows(sizes: group, available: Self.phone, spacing: LiveControlStrip.pillSpacing)
            XCTAssertEqual(rows.count, 1, "\(name) measured \(group.map(\.width)) at \(Self.phone) pt")
        }
    }

    @MainActor func testTheLanguagePairIsOneRowOnAThreeNinetyThreePointPhone() {
        let pair = [width(LiveControlPill(systemImage: nil, title: LiveControlStrip.youSpeakTitle, value: "English")),
                    width(LiveControlPill(systemImage: nil, title: LiveControlStrip.theySpeakTitle, value: "Spanish"))].map { size($0) }
        let rows = PillFlowLayout.rows(sizes: pair, available: Self.phone, spacing: LiveControlStrip.pillSpacing)
        XCTAssertEqual(rows.map(\.items), [[0, 1]], "measured \(pair.map(\.width))")
    }

    /// M11 review: at the largest accessibility size a pair pill is wider than any iPhone on one line, so it wraps
    /// inside its capsule (the layout re-measures it at the row's width) instead of running off the screen edge.
    @MainActor func testAPairPillWrapsInsideThePhoneWidthAtTheLargestType() {
        let pill = LiveControlPill(systemImage: nil, title: LiveControlStrip.theySpeakTitle, value: "Spanish")
            .dynamicTypeSize(.accessibility5)
        let controller = UIHostingController(rootView: pill)
        let size = controller.sizeThatFits(in: CGSize(width: Self.phone, height: .greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(size.width.rounded(.up), Self.phone, "measured \(size)")
        XCTAssertGreaterThan(size.height, LiveControlPill.minimumHeight, "two lines, not one clipped one")
    }

    /// On a 320 pt phone a group wraps inside itself: the ⓘ drops under Listen, the pair becomes two lines.
    func testAGroupWrapsOnlyInsideItselfOnAThreeTwentyPointPhone() {
        let listen = [size(72), size(66), size(108), size(44)]
        XCTAssertEqual(PillFlowLayout.rows(sizes: listen, available: Self.narrowPhone, spacing: LiveControlStrip.pillSpacing).map(\.items), [[0, 1, 2], [3]])
        let pair = [size(150), size(161)]
        XCTAssertEqual(PillFlowLayout.rows(sizes: pair, available: Self.narrowPhone, spacing: LiveControlStrip.pillSpacing).map(\.items), [[0], [1]])
    }
}
