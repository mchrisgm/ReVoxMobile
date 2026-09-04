import SwiftUI
import ReVoxCore

/// One History row (§8.6). Colour is never the only status carrier: the source is a labelled symbol, the
/// counts are text, and the whole row reads as one VoiceOver sentence (§8.8).
struct SessionRowView: View {
    static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)

    let summary: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.startedAt, format: Self.dateStyle).font(.headline)
                Spacer()
                Text(summary.durationText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            // One Text, not an HStack of five (M10 audit): at the accessibility sizes a paragraph wraps where a
            // row of fixed pieces stacks its words one under another.
            (Text(Image(systemName: summary.sourceSymbolName)) + Text(" \(summary.metaLineText)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary.previewText)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(summary.firstEnglishLine == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [
            "Session \(summary.startedAt.formatted(Self.dateStyle))",
            summary.sourceTitle,
            "\(summary.durationText) long",
            summary.entryCountText,
        ]
        if summary.joinedInProgress { parts.append("joined in progress") }
        parts.append(summary.previewText)
        return parts.joined(separator: ". ") + "."
    }
}
