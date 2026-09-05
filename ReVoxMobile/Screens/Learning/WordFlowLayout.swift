import SwiftUI

/// The wrapped line of word chips (M11 §2): `PillFlowLayout`'s greedy in-order packing with no gap between
/// chips, so the chips tile the line and every touch on it lands on a word, plus a first-text baseline — that of
/// the first chip — so the row's `HStack(alignment: .firstTextBaseline)` keeps the time and the language badge on
/// the first word's baseline rather than on the bottom of a 44 pt line. Copied rather than shared so this file
/// and the Live strip's layout stay in their own lanes.
struct WordFlowLayout: Layout {
    static let spacing: CGFloat = 0
    /// Rows overlap by this much: every chip keeps its 44 pt target, but the visible lines of text sit 32 pt apart
    /// instead of 44 — CI run 123's `live-running` showed a wrapped original with a gap wider than a line of text
    /// between its two lines. The overlap is the part of a chip's target above and below its glyphs; a touch in the
    /// overlap lands on the lower row, which is placed last.
    static let rowSpacing: CGFloat = -12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = Self.width(for: proposal, sizes: sizes)
        let rows = Self.rows(sizes: sizes, available: width)
        return CGSize(width: width, height: Self.height(of: rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(sizes: sizes, available: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.items {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height + Self.rowSpacing
        }
    }

    /// The first chip's baseline where `placeSubviews` puts it: centred in the first row, in the bounds' space.
    /// Acceptance (M11 §2): the first Learning row of the `live-running` screenshot shows the time and the badge
    /// on the first word's baseline. If CI renders them off it, this is the line to correct — in the same PR.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let row = Self.rows(sizes: sizes, available: bounds.width).first else { return nil }
        return bounds.minY + (row.height - sizes[0].height) / 2 + first.dimensions(in: ProposedViewSize(sizes[0]))[VerticalAlignment.firstTextBaseline]
    }

    /// The width the rows are packed into: the proposal's, or — unproposed or unbounded — everything on one row.
    static func width(for proposal: ProposedViewSize, sizes: [CGSize]) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return sizes.reduce(CGFloat(0)) { $0 + $1.width }
    }

    struct Row: Equatable {
        var items: [Int]
        var height: CGFloat
    }

    /// The rows' heights with the overlap between them; never less than the first row.
    static func height(of rows: [Row]) -> CGFloat {
        let stacked = rows.reduce(CGFloat(0)) { $0 + $1.height } + Self.rowSpacing * CGFloat(max(rows.count - 1, 0))
        return max(stacked, rows.first?.height ?? 0)
    }

    /// Greedy and in order: a chip joins the current row while it fits, and a chip wider than the whole row still
    /// gets a row of its own rather than being dropped. Pure, so the packing is tested without a view.
    static func rows(sizes: [CGSize], available: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(items: [], height: 0)
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let widthIfAdded = used + size.width
            if !current.items.isEmpty && widthIfAdded > available {
                rows.append(current)
                current = Row(items: [], height: 0)
                used = size.width
            } else {
                used = widthIfAdded
            }
            current.items.append(index)
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
