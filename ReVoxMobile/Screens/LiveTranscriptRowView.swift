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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// M10 (HIG audit): what VoiceOver says for the leading column — "12 s" is read as a letter, so the age is
    /// spoken in full; the clock reads as a time on its own.
    static func leadingAccessibilityText(time: Date, now: Date?, display: Settings.TimeDisplay) -> String {
        let clock = time.formatted(timeStyle)
        guard let now else { return clock }
        switch display {
        case .time: return clock
        case .age: return spokenAge(from: time, to: now)
        case .both: return "\(spokenAge(from: time, to: now)), \(clock)"
        }
    }

    /// `RelativeAge.text` said in full: "just now", "12 seconds ago", "3 minutes ago", "1 hour 5 minutes ago".
    /// The same buckets as the visible form (whole seconds under a minute, minutes under an hour, then hours and
    /// minutes), and a future `then` is "just now" for the same reason a negative age is never shown.
    static func spokenAge(from then: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(then).rounded(.down))
        guard seconds >= 1 else { return "just now" }
        if seconds < 60 { return "\(plural(seconds, "second")) ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(plural(minutes, "minute")) ago" }
        let hours = minutes / 60
        let rest = minutes % 60
        guard rest > 0 else { return "\(plural(hours, "hour")) ago" }
        return "\(plural(hours, "hour")) \(plural(rest, "minute")) ago"
    }

    private static func plural(_ count: Int, _ unit: String) -> String {
        count == 1 ? "1 \(unit)" : "\(count) \(unit)s"
    }

    /// "Language Spanish" where the locale knows the code, "Language es" when it does not: the badge shows the
    /// code, VoiceOver should not spell it.
    static func languageAccessibilityText(_ code: String) -> String {
        "Language \(LanguageCatalog.displayName(code, whenNil: code))"
    }

    var body: some View {
        switch row.kind {
        case .entry(let language, let original, let english):
            entryRow(language: language, original: original, english: english)
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

    /// HIG-Live-2 (M6 audit, deferred): three columns beside each other do not fit at the accessibility text
    /// sizes, where the leading column alone can take half the width. There the time and the badge go on one line
    /// and the text under them; at every other size the layout is the one-line row it always was.
    @ViewBuilder
    private func entryRow(language: String, original: String, english: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    leadingColumn
                    languageBadge(language)
                    Spacer(minLength: 0)
                }
                textColumn(original: original, english: english)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                leadingColumn
                languageBadge(language)
                textColumn(original: original, english: english)
                Spacer(minLength: 0)
            }
        }
    }

    private var leadingColumn: some View {
        Text(Self.leadingText(time: row.time, now: now, display: timeDisplay))
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .accessibilityLabel(Self.leadingAccessibilityText(time: row.time, now: now, display: timeDisplay))
    }

    private func languageBadge(_ language: String) -> some View {
        Text(language)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .accessibilityLabel(Self.languageAccessibilityText(language))
    }

    private func textColumn(original: String, english: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsOriginal, !original.isEmpty, original != english {
                Text(original).font(.body).foregroundStyle(.secondary)
                if romanizes, let latin = Romanizer.romanize(original) {
                    // `.secondary`, not `.tertiary`: the tertiary label composites to about 1.7:1 on white (M10 audit).
                    Text(latin).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(english).font(.body)
        }
    }
}
