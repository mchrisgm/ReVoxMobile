import SwiftUI
import ReVoxCore

struct LiveTranscriptRowView: View {
    let row: LiveTranscriptRow
    /// M9: what the leading column shows. `now` non-nil enables the age forms; History and Session detail pass
    /// nil and always get the time, because "12 s ago" means nothing a day later.
    var now: Date? = nil
    var timeDisplay: Settings.TimeDisplay = .time
    /// M9 Learning mode: the words as spoken above the translation, and their Latin form under them.
    var showsOriginal = false
    var romanizes = false

    private static let timeStyle = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)

    /// "12 s" / "10:41:07" / both — pure, so the tests read it without a view.
    static func leadingText(time: Date, now: Date?, display: Settings.TimeDisplay) -> String {
        let clock = time.formatted(timeStyle)
        guard let now else { return clock }
        switch display {
        case .time: return clock
        case .age: return RelativeAge.text(from: time, to: now)
        case .both: return "\(RelativeAge.text(from: time, to: now)) · \(clock)"
        }
    }

    var body: some View {
        switch row.kind {
        case .entry(let language, let original, let english):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.leadingText(time: row.time, now: now, display: timeDisplay))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(language)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityLabel("Language \(language)")
                VStack(alignment: .leading, spacing: 2) {
                    if showsOriginal, !original.isEmpty, original != english {
                        Text(original).font(.body).foregroundStyle(.secondary)
                        if romanizes, let latin = Romanizer.romanize(original) {
                            Text(latin).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Text(english).font(.body)
                }
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
