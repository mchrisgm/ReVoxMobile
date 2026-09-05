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
    /// M11 §2: this row's one open popover, nil when none. Held by the row, so the Live screen's one-second
    /// TimelineView ticks and row appends keep it; `OriginalWordsLine` and `WordLookUpActions` read the services
    /// from `\.wordLookup` themselves (the default is `WordLookup.unavailable`, so every hosted test row is honest
    /// and inert; `RootView` applies the production one outermost).
    @State private var lookup: WordPopoverModel?

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

    /// M11 §3: a phrase the gates were unsure about. The marker is the first line of the text column, so it stacks
    /// under the badge at the accessibility sizes like the rest of the text; the English is italic and secondary, so
    /// the state is never carried by colour alone; VoiceOver reads the marker as "Unsure translation" between the
    /// language and the English in the row's one combined element.
    static let guessMarkerText = "Unsure"
    static let guessAccessibilityText = "Unsure translation"
    /// One symbol with the History row and the Settings example.
    static let guessSymbolName = SessionSummary.guessSymbolName

    /// M11 §2: the languages whose original stays plain text for now — the chip layout runs left to right. One
    /// list with the splitter.
    static let rightToLeftLanguages: Set<String> = WordSplitter.rightToLeftLanguages
    /// M11 §2: VoiceOver gets a "Look up ‹word›" custom action for at most this many words of a row.
    static let maxWordActions = OriginalWordsLine.customActionLimit

    /// M11 §2, pure: the original line is worth tapping — non-empty, different from the English, not English
    /// (nothing to learn) and not right-to-left. Learning off, English rows and guesses without an original render
    /// exactly as before.
    static func tapsWords(language: String, original: String, english: String) -> Bool {
        !original.isEmpty && original != english && language != "en" && !WordSplitter.isRightToLeft(language)
    }

    /// The custom action's title; the popover it opens is the same one a tap opens.
    static func wordActionTitle(_ word: String) -> String { WordPopoverContent.lookUpActionTitle(word) }

    /// The words that get a custom action: the first `maxWordActions`, in sentence order, so a long row does not
    /// put thirty actions before its own.
    static func actionWords(_ words: [OriginalWord]) -> [OriginalWord] { OriginalWordsLine.actionWords(words) }

    var body: some View {
        switch row.kind {
        case .entry(let language, let original, let english):
            let words = tappableWords(language: language, original: original, english: english)
            entryRow(language: language, original: original, english: english, words: words)
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                // M11 §2: the words are reachable without the chips — one "Look up ‹word›" action per word, on the
                // row itself so they survive the combine (the words line is `children: .ignore` and reads as the
                // sentence). Empty `words`: no actions, the row reads as it always has.
                .modifier(WordLookUpActions(words: words, language: language, original: original, english: english, lookup: $lookup))
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
    private func entryRow(language: String, original: String, english: String, words: [OriginalWord]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    leadingColumn
                    languageBadge(language)
                    Spacer(minLength: 0)
                }
                textColumn(language: language, original: original, english: english, words: words)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                leadingColumn
                languageBadge(language)
                textColumn(language: language, original: original, english: english, words: words)
                Spacer(minLength: 0)
            }
        }
    }

    /// Empty unless the row shows its original and `tapsWords` says yes. `WordSplitter.cachedWords` is memoised
    /// per (language, sentence) on the main actor, so the body under the TimelineView never re-tokenises.
    @MainActor
    private func tappableWords(language: String, original: String, english: String) -> [OriginalWord] {
        guard showsOriginal, Self.tapsWords(language: language, original: original, english: english) else { return [] }
        return WordSplitter.cachedWords(in: original, language: language)
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

    private func textColumn(language: String, original: String, english: String, words: [OriginalWord]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isGuess { guessMarker }
            if showsOriginal, !original.isEmpty, original != english {
                if words.isEmpty {
                    Text(original).font(.body).foregroundStyle(.secondary)
                } else {
                    // M11 §2: the greying of a guess stays outside this line — the chips are secondary already and
                    // the marker above says why; the line reads as the sentence, so the combined row is unchanged.
                    OriginalWordsLine(original: original, language: language, english: english, words: words, lookup: $lookup)
                }
                if romanizes, let latin = Romanizer.romanize(original) {
                    // `.secondary`, not `.tertiary`: the tertiary label composites to about 1.7:1 on white (M10 audit).
                    Text(latin).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(english)
                .font(row.isGuess ? Font.body.italic() : Font.body)
                .foregroundStyle(row.isGuess ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    /// M11 §3: the visible reason a row is greyed, read as "Unsure translation".
    private var guessMarker: some View {
        Label(Self.guessMarkerText, systemImage: Self.guessSymbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(Self.guessAccessibilityText)
    }
}
