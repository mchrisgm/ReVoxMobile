import SwiftUI
import ReVoxCore

struct LiveTranscriptRowView: View {
    let row: LiveTranscriptRow

    private static let timeStyle = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)

    var body: some View {
        switch row.kind {
        case .entry(let language, let english):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.time.formatted(Self.timeStyle)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(language)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Language \(language)")
                Text(english).font(.body)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        case .dropMarker:
            Text("… skipped: falling behind")
                .font(.caption.italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        case .joinedInProgress:
            Text(BroadcastCoordinator.joinedText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
    }
}
