import SwiftUI
import ReVoxCore

/// One History row (§8.6). Colour is never the only status carrier: the source is a labelled symbol, the
/// counts are text, and the whole row reads as one VoiceOver sentence (§8.8).
struct SessionRowView: View {
    static let dateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
    /// M11: said before a preview that is a guess — the italic and the symbol are the visible cue, this is the spoken one.
    static let guessPreviewPrefix = "Unsure: "

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
            previewLine
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityText(for: summary))
    }

    /// M11: a session that holds only guesses previews one — secondary italic with the Unsure symbol inline, so it
    /// is never mistaken for a confident line. A confident preview is exactly what it was.
    @ViewBuilder
    private var previewLine: some View {
        if summary.previewIsGuess {
            (Text(Image(systemName: SessionSummary.guessSymbolName)) + Text(" \(summary.previewText)"))
                .font(.body.italic())
                .lineLimit(2)
                .foregroundStyle(.secondary)
        } else {
            Text(summary.previewText)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(summary.firstEnglishLine == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    /// The row's one VoiceOver sentence; pure, so the tests read it without a host.
    static func accessibilityText(for summary: SessionSummary) -> String {
        var parts = [
            "Session \(summary.startedAt.formatted(Self.dateStyle))",
            summary.sourceTitle,
            "\(summary.durationText) long",
            summary.entryCountText,
        ]
        if summary.joinedInProgress { parts.append("joined in progress") }
        parts.append(summary.previewIsGuess ? guessPreviewPrefix + summary.previewText : summary.previewText)
        return parts.joined(separator: ". ") + "."
    }
}
