import SwiftUI

/// M10: the Live strip's pills wrap into as many rows as the width needs, left to right, in order.
///
/// A horizontal `ScrollView` was the first shape of the strip, and the first scroll view under a navigation bar
/// becomes the bar's tracked scroll view: the bar dropped its large title and inset the strip's content under
/// itself, so CI's screenshots showed an empty band where the pills were (run 106) while the two-way row, the
/// second scroll view, drew fine. Wrapping shows every control at once — nothing to scroll to find the volume or
/// the details — and leaves the transcript as the bar's scroll view, the M9 arrangement CI had rendered.
struct PillFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = Self.width(for: proposal, sizes: ideal, spacing: spacing)
        let sizes = Self.sizes(subviews, ideal: ideal, cappedTo: width)
        let rows = Self.rows(sizes: sizes, available: width, spacing: spacing)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let sizes = Self.sizes(subviews, ideal: ideal, cappedTo: bounds.width)
        let rows = Self.rows(sizes: sizes, available: bounds.width, spacing: spacing)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.items {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    /// A pill wider than the whole row is measured again at the row's width, so at the accessibility type sizes
    /// (where `LiveControlPill` lets its text wrap) it wraps inside its capsule instead of running off the screen
    /// edge (M11 review). At the other sizes a pill is fixed-width and answers with its ideal size regardless.
    static func sizes(_ subviews: LayoutSubviews, ideal: [CGSize], cappedTo available: CGFloat) -> [CGSize] {
        zip(subviews, ideal).map { subview, size in
            size.width <= available ? size : subview.sizeThatFits(ProposedViewSize(width: available, height: nil))
        }
    }

    /// The width the rows are packed into: the proposal's, or — unproposed or unbounded — everything on one row.
    static func width(for proposal: ProposedViewSize, sizes: [CGSize], spacing: CGFloat) -> CGFloat {
        if let width = proposal.width, width.isFinite { return width }
        return sizes.reduce(CGFloat(0)) { $0 + $1.width } + spacing * CGFloat(max(sizes.count - 1, 0))
    }

    struct Row: Equatable {
        var items: [Int]
        var height: CGFloat
    }

    /// Greedy and in order: a pill joins the current row while it fits, and a pill wider than the whole row still
    /// gets a row of its own rather than being dropped. Pure, so the packing is tested without a view.
    static func rows(sizes: [CGSize], available: CGFloat, spacing: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(items: [], height: 0)
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let widthIfAdded = current.items.isEmpty ? size.width : used + spacing + size.width
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
