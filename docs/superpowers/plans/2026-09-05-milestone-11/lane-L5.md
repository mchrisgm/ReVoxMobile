## Lane L5: Wave 2 wiring — the row, the Settings insertions, the environment

Runs after every wave-1 lane (L1–L4) is merged onto `claude/revoxmobile-ios-app-hkajbf`. L1 and L2 are already merged (`3f3f714`, `f35dba3`); L3 and L4 are not yet, so the L4 signatures in **Consumes** are the spec's names with the design panel's labels, and the two `AppEnvironment.swift` anchors are quoted from the pre-L3 file. No ReVoxCore change; the broadcast extension is untouched. Working directory for every command: `/home/user/ReVoxMobile`.

**Files**

- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/LiveTranscriptRowView.swift` (guess styling, tappable words, custom actions)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsView.swift` (insert `GuessesSettingsSection(model:)` under Source language)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingExample.swift` (`SettingExamples.learning(true)` — the Learning copy §7 assigns to L5; L1's wave-1 file, merged)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsViewModel.swift` (`learningHelpText` — same)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/App/RootView.swift` (`.environment(\.wordLookup, …)` outermost)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/App/AppEnvironment.swift` (`wordSpeaker`, `wordLookup`, the microphone rule)
- Not touched: `SessionRowView.swift` (L2 did not leave it: the guess preview, symbol and "Unsure: " prefix are on the branch)
- Test files:
  - `/home/user/ReVoxMobile/ReVoxMobileTests/RowAccessibilityTests.swift` (guess copy, `tapsWords`, action title and cap, rows with chips host)
  - `/home/user/ReVoxMobile/ReVoxMobileTests/SettingsViewModelTests.swift` (the Learning copy)
  - `/home/user/ReVoxMobile/ReVoxMobileTests/AppEnvironmentTests.swift` (the lookup is built over the app's speaker; the microphone rule)
  - `/home/user/ReVoxMobile/ReVoxMobileTests/ScreenshotTests.swift` (a greyed Unsure row in `live-running`; a new `learning-word` capture)

**Interfaces**

Consumes (exact):
- Seam commit: `struct LiveTranscriptRow { let isGuess: Bool; init(id: UUID = UUID(), time: Date, kind: Kind, isGuess: Bool = false) }`; `SettingsViewModel.store` internal.
- L2 (merged): `struct GuessesSettingsSection: View { @Bindable var model: SettingsViewModel }` — `GuessesSettingsSection(model:)`; `SessionSummary.guessSymbolName: String` (`"questionmark.circle"`); `SettingExamples.guessRow: LiveTranscriptRow`; `public init(timestamp: Date, language: String, original: String, english: String, isGuess: Bool = false)` on `TranscriptEntry`; `LiveViewModel.handle(.entry)` appends `LiveTranscriptRow(…, isGuess: entry.isGuess)`.
- L4: `struct OriginalWord: Identifiable, Equatable, Sendable { let id: Int; let text: String; let range: Range<String.Index> }`; `enum WordSplitter { @MainActor static func words(in text: String, language: String) -> [OriginalWord] }` (memoised); `struct OriginalWordsLine: View` with `init(original: String, language: String, words: [OriginalWord], lookup: Binding<WordPopoverModel?>, onSelect: @escaping (OriginalWord) -> Void)`; `@MainActor @Observable final class WordPopoverModel { init(word: OriginalWord, language: String, original: String, english: String, lookup: WordLookup); func load() async; func receiveMeaning(_ text: String?) }`; `struct WordPopoverView: View { init(model: WordPopoverModel) }` (other parameters defaulted); `struct WordLookup { var speaker: WordSpeaker?; var hasVoice: @MainActor (String) -> Bool; var hasDefinition: @MainActor (String) -> Bool; var translatorAvailability: @Sendable (String) async -> WordTranslatorAvailability; static let unavailable: WordLookup; @MainActor static func production(speaker: WordSpeaker) -> WordLookup }` with the memberwise `WordLookup(speaker:hasVoice:hasDefinition:translatorAvailability:)`; `extension EnvironmentValues { var wordLookup: WordLookup }` (default `.unavailable`); `enum WordTranslatorAvailability: Equatable, Sendable { case unavailableOnThisiOS, needsDownload, unsupported, ready }`; `@MainActor @Observable final class WordSpeaker { init(isMicrophoneRunning: @escaping @MainActor () -> Bool); private(set) var isSpeaking: Bool }` (synthesizer created lazily on the first `speak`).
- Existing app code: `enum LiveState { case idle, preparing, running, error }`; `LiveViewModel.state: LiveState`, `LiveViewModel.captureMode: CaptureMode`; `public enum CaptureMode { case microphone, broadcast }` (ReVoxCore); `SettingExamples.spanishOriginal`, `.spanishEnglish`, `.sampleRow(original:)`, `.japaneseRow`; `Romanizer.romanize(_:)`.

Produces (exact):
- `LiveTranscriptRowView.tapsWords(language: String, original: String, english: String) -> Bool` (static, pure)
- `LiveTranscriptRowView.rightToLeftLanguages: Set<String>` = `["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"]`
- `LiveTranscriptRowView.guessMarkerText = "Unsure"`, `.guessAccessibilityText = "Unsure translation"`, `.guessSymbolName` (`== SessionSummary.guessSymbolName`)
- `LiveTranscriptRowView.maxWordActions = 12`, `.wordActionTitle(_ word: String) -> String` ("Look up ‹word›"), `.actionWords(_ words: [OriginalWord]) -> [OriginalWord]`
- `AppEnvironment.wordSpeaker: WordSpeaker`, `AppEnvironment.wordLookup: WordLookup`, `static func isMicrophoneRunning(state: LiveState, captureMode: CaptureMode) -> Bool`
- `RootView` applies `.environment(\.wordLookup, environment.wordLookup)` outermost, after `.fullScreenCover`, so L6's tutorial cover inherits the production lookup.
- `SettingExamples.learning(true)` = "The words as spoken appear above the translation. Tap a word to hear it and see what it means." (L6's `OnboardingDemo.learningText(learning: true, romanize: false)` still equals it); `SettingsViewModel.learningHelpText` ends with " Tap any word for its pronunciation and meaning."
- A `docs/screenshots/learning-word.png` capture for L7 to place in the README (the popover's content hosted alone, not a popover with an arrow).

### Task 1: The guess styling — Unsure marker, italic secondary English

- [ ] Step 1: Write the failing test. Append to the end of the class in `/home/user/ReVoxMobile/ReVoxMobileTests/RowAccessibilityTests.swift`, before its final `}`:

```swift
    // MARK: M11 §3: the guess marker

    func testTheGuessMarkerCopyIsExactAndSharesTheHistorySymbol() {
        XCTAssertEqual(LiveTranscriptRowView.guessMarkerText, "Unsure")
        XCTAssertEqual(LiveTranscriptRowView.guessAccessibilityText, "Unsure translation")
        XCTAssertEqual(LiveTranscriptRowView.guessSymbolName, "questionmark.circle")
        XCTAssertEqual(LiveTranscriptRowView.guessSymbolName, SessionSummary.guessSymbolName,
                       "Live, Session detail, the History row and the Settings example show one symbol")
    }
```

- [ ] Step 2: Run it. CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/RowAccessibilityTests.swift` parses (the three statics do not exist yet, which only the simulator build reports).

- [ ] Step 3: Implement. In `/home/user/ReVoxMobile/ReVoxMobile/Screens/LiveTranscriptRowView.swift`, after the `languageAccessibilityText` function (current lines 60–64), add:

```swift
    /// M11 §3: a phrase the gates were unsure about. The marker is the first line of the text column, so it stacks
    /// under the badge at the accessibility sizes like the rest of the text; the English is italic and secondary, so
    /// the state is never carried by colour alone; VoiceOver reads the marker as "Unsure translation" between the
    /// language and the English in the row's one combined element.
    static let guessMarkerText = "Unsure"
    static let guessAccessibilityText = "Unsure translation"
    /// One symbol with the History row and the Settings example.
    static let guessSymbolName = SessionSummary.guessSymbolName
```

  Replace the current `textColumn` (lines 125–136):

```swift
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
```

  with:

```swift
    private func textColumn(original: String, english: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isGuess { guessMarker }
            if showsOriginal, !original.isEmpty, original != english {
                Text(original).font(.body).foregroundStyle(.secondary)
                if romanizes, let latin = Romanizer.romanize(original) {
                    // `.secondary`, not `.tertiary`: the tertiary label composites to about 1.7:1 on white (M10 audit).
                    Text(latin).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(english)
                .font(row.isGuess ? .body.italic() : .body)
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
```

- [ ] Step 4: Run. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/LiveTranscriptRowView.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/RowAccessibilityTests.swift` — both parse. (`GuessHostingTests.testAGuessRowHostsAtEverySize`, already on the branch, hosts this row at `.large` and `.accessibility5` on the simulator.)

- [ ] Step 5: Commit.

```
git add ReVoxMobile/Screens/LiveTranscriptRowView.swift ReVoxMobileTests/RowAccessibilityTests.swift
git commit -m "feat(app): a guess row shows an Unsure marker and italic, secondary English

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 2: Tappable words — the pure rule, the chips line, the select staging, the custom actions

- [ ] Step 1: Write the failing tests. In `/home/user/ReVoxMobile/ReVoxMobileTests/RowAccessibilityTests.swift` change the imports at the top from

```swift
import XCTest
import ReVoxCore
@testable import ReVoxMobile
```

  to

```swift
import XCTest
import SwiftUI
import ReVoxCore
@testable import ReVoxMobile
```

  and append inside the class, after `testTheGuessMarkerCopyIsExactAndSharesTheHistorySymbol`:

```swift
    // MARK: M11 §2: which rows tap words, and the Look up actions

    func testTapsWordsOnlyOnAForeignLeftToRightOriginal() {
        XCTAssertTrue(LiveTranscriptRowView.tapsWords(language: "es", original: "Buenos días.", english: "Good morning."))
        XCTAssertTrue(LiveTranscriptRowView.tapsWords(language: "ja", original: "おはよう", english: "Good morning."))
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "es", original: "", english: "Good morning."), "Learning off: no original")
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "es", original: "Hola", english: "Hola"), "nothing to learn when the two are the same")
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "en", original: "Yes", english: "Sí"), "English rows are never tappable")
        for code in ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"] {
            XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: code, original: "مرحبا", english: "Hello"), "\(code) is right-to-left: plain text for now")
        }
        XCTAssertEqual(LiveTranscriptRowView.rightToLeftLanguages, ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"])
    }

    func testTheWordActionsNameTheWordAndStopAtTwelve() {
        XCTAssertEqual(LiveTranscriptRowView.wordActionTitle("estación"), "Look up estación")
        XCTAssertEqual(LiveTranscriptRowView.maxWordActions, 12)
        let sentence = "uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince"
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 15)
        let actions = LiveTranscriptRowView.actionWords(words)
        XCTAssertEqual(actions.count, 12)
        XCTAssertEqual(actions.map(\.text), Array(words.prefix(12)).map(\.text), "the first twelve, in sentence order")
        XCTAssertTrue(LiveTranscriptRowView.actionWords([]).isEmpty)
    }

    /// The row hosts with the inert default lookup (`WordLookup.unavailable`) on both paths — chips for a Spanish
    /// Learning row and for a Japanese guess with an original, plain text for an English row and for a
    /// right-to-left one — at the default and the largest accessibility size.
    func testRowsWithChipsHostAtEverySize() {
        let rows = [
            LiveTranscriptRow(time: said, kind: .entry(language: "es", original: "¿Dónde está la estación?", english: "Where is the station?")),
            LiveTranscriptRow(time: said.addingTimeInterval(1), kind: .entry(language: "ja", original: "おはよう", english: "Good morning."), isGuess: true),
            LiveTranscriptRow(time: said.addingTimeInterval(2), kind: .entry(language: "en", original: "Hello there", english: "Hello there")),
            LiveTranscriptRow(time: said.addingTimeInterval(3), kind: .entry(language: "ar", original: "مرحبا", english: "Hello")),
        ]
        for size in [DynamicTypeSize.large, .accessibility5] {
            host(List {
                ForEach(rows) { row in
                    LiveTranscriptRowView(row: row, now: said.addingTimeInterval(12), timeDisplay: .both, showsOriginal: true, romanizes: true)
                }
            }
            .environment(\.dynamicTypeSize, size))
        }
        host(List { ForEach(rows) { LiveTranscriptRowView(row: $0) } })
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }
```

- [ ] Step 2: Run it. CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/RowAccessibilityTests.swift` parses; `python3 scripts/dev/check-tests-are-discoverable.py` reports every `test…` inside `RowAccessibilityTests: XCTestCase`.

- [ ] Step 3: Implement the members. In `/home/user/ReVoxMobile/ReVoxMobile/Screens/LiveTranscriptRowView.swift` replace the property block (current lines 4–14)

```swift
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
```

  with

```swift
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
    /// M11 §2: the services a word popover needs. The default is `WordLookup.unavailable`, so every hosted test
    /// row is honest and inert; `RootView` applies the production one outermost.
    @Environment(\.wordLookup) private var wordLookup
    /// M11 §2: this row's one open popover, nil when none. Held by the row, so the Live screen's one-second
    /// TimelineView ticks and row appends keep it.
    @State private var lookup: WordPopoverModel?
```

  Then, directly after the Task 1 statics (`static let guessSymbolName = SessionSummary.guessSymbolName`), add:

```swift
    /// M11 §2: the languages whose original stays plain text for now — the chip layout runs left to right.
    static let rightToLeftLanguages: Set<String> = ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"]
    /// M11 §2: VoiceOver gets a "Look up ‹word›" custom action for at most this many words of a row.
    static let maxWordActions = 12

    /// M11 §2, pure: the original line is worth tapping — non-empty, different from the English, not English
    /// (nothing to learn) and not right-to-left. Learning off, English rows and guesses without an original render
    /// exactly as before.
    static func tapsWords(language: String, original: String, english: String) -> Bool {
        !original.isEmpty && original != english && language != "en" && !rightToLeftLanguages.contains(language)
    }

    /// The custom action's title; the popover it opens is the same one a tap opens.
    static func wordActionTitle(_ word: String) -> String { "Look up \(word)" }

    /// The words that get a custom action: the first `maxWordActions`, in sentence order, so a long row does not
    /// put thirty actions before its own.
    static func actionWords(_ words: [OriginalWord]) -> [OriginalWord] { Array(words.prefix(maxWordActions)) }
```

- [ ] Step 4: Implement the body. Replace the `.entry` case of `body` (current lines 67–71)

```swift
        switch row.kind {
        case .entry(let language, let original, let english):
            entryRow(language: language, original: original, english: english)
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
```

  with

```swift
        switch row.kind {
        case .entry(let language, let original, let english):
            let words = tappableWords(language: language, original: original, english: english)
            entryRow(language: language, original: original, english: english, words: words)
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                // M11 §2: the words are reachable without the chips — one action per word, on the row itself so
                // they survive the combine (the words line is `children: .ignore` and reads as the sentence).
                .accessibilityActions {
                    ForEach(Self.actionWords(words)) { word in
                        Button(Self.wordActionTitle(word.text)) {
                            select(word, language: language, original: original, english: english)
                        }
                    }
                }
```

  Replace `entryRow` (current lines 90–109)

```swift
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
```

  with

```swift
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

    /// Empty unless the row shows its original and `tapsWords` says yes. `WordSplitter.words` is memoised per
    /// (language, sentence), so the body under the TimelineView never re-tokenises.
    private func tappableWords(language: String, original: String, english: String) -> [OriginalWord] {
        guard showsOriginal, Self.tapsWords(language: language, original: original, english: english) else { return [] }
        return WordSplitter.words(in: original, language: language)
    }

    /// Opens the popover for one word. Selecting while another popover is open closes that one first and stages
    /// the new model on the next run-loop turn: two `.popover(isPresented:)` bindings flipped in one update make
    /// UIKit skip the second presentation while the first dismissal is in flight.
    private func select(_ word: OriginalWord, language: String, original: String, english: String) {
        let model = WordPopoverModel(word: word, language: language, original: original, english: english, lookup: wordLookup)
        guard lookup != nil else {
            lookup = model
            return
        }
        lookup = nil
        Task { @MainActor in lookup = model }
    }
```

  Replace the Task 1 `textColumn`

```swift
    private func textColumn(original: String, english: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isGuess { guessMarker }
            if showsOriginal, !original.isEmpty, original != english {
                Text(original).font(.body).foregroundStyle(.secondary)
                if romanizes, let latin = Romanizer.romanize(original) {
                    // `.secondary`, not `.tertiary`: the tertiary label composites to about 1.7:1 on white (M10 audit).
                    Text(latin).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(english)
                .font(row.isGuess ? .body.italic() : .body)
                .foregroundStyle(row.isGuess ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
```

  with

```swift
    private func textColumn(language: String, original: String, english: String, words: [OriginalWord]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if row.isGuess { guessMarker }
            if showsOriginal, !original.isEmpty, original != english {
                if words.isEmpty {
                    Text(original).font(.body).foregroundStyle(.secondary)
                } else {
                    // M11 §2: the greying of a guess stays outside this line — the chips are secondary already and
                    // the marker above says why; the line reads as the sentence, so the combined row is unchanged.
                    OriginalWordsLine(original: original, language: language, words: words, lookup: $lookup,
                                      onSelect: { select($0, language: language, original: original, english: english) })
                }
                if romanizes, let latin = Romanizer.romanize(original) {
                    // `.secondary`, not `.tertiary`: the tertiary label composites to about 1.7:1 on white (M10 audit).
                    Text(latin).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(english)
                .font(row.isGuess ? .body.italic() : .body)
                .foregroundStyle(row.isGuess ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }
```

- [ ] Step 5: Run. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/LiveTranscriptRowView.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/RowAccessibilityTests.swift && python3 scripts/dev/check-core-imports.py --all` — the row file keeps `import ReVoxCore` (it uses `Settings` and `Romanizer`), so the gate stays green. Every existing call site (`LiveView`, `SessionDetailView`, `SettingsView`, `GuessesSettingsSection`, `OnboardingView`, the tests) is untouched: the initialiser did not change.

- [ ] Step 6: Commit.

```
git add ReVoxMobile/Screens/LiveTranscriptRowView.swift ReVoxMobileTests/RowAccessibilityTests.swift
git commit -m "feat(app): a Learning row's original is tappable word chips with one popover per row and Look up actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 3: Settings — the Unsure phrases section under Source language, and the Learning copy

- [ ] Step 1: Write the failing test. In `/home/user/ReVoxMobile/ReVoxMobileTests/SettingsViewModelTests.swift`, directly after `testEveryExampleChangesWithItsValue` (its closing `}` follows the `"the example is kana on purpose…"` assertion), add:

```swift
    /// M11 §2: the Learning copy says the words are tappable — on the example, which is the live demonstration
    /// (the same row view), and in the footer.
    func testTheLearningCopySaysWordsAreTappable() {
        XCTAssertEqual(SettingExamples.learning(true),
                       "The words as spoken appear above the translation. Tap a word to hear it and see what it means.")
        XCTAssertEqual(SettingExamples.learning(false), "Only the translation is shown.")
        XCTAssertTrue(SettingsViewModel.learningHelpText.hasPrefix("Shows the words as they were spoken above the translation."))
        XCTAssertTrue(SettingsViewModel.learningHelpText.hasSuffix(" Tap any word for its pronunciation and meaning."))
    }
```

- [ ] Step 2: Run it. CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/SettingsViewModelTests.swift` parses; on the simulator the two equality assertions fail against today's strings.

- [ ] Step 3: Implement the copy. In `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingExample.swift` replace (current lines 96–98)

```swift
    static func learning(_ on: Bool) -> String {
        on ? "The words as spoken appear above the translation." : "Only the translation is shown."
    }
```

  with

```swift
    static func learning(_ on: Bool) -> String {
        on ? "The words as spoken appear above the translation. Tap a word to hear it and see what it means."
           : "Only the translation is shown."
    }
```

  In `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsViewModel.swift` replace (current line 94)

```swift
    static let learningHelpText = "Shows the words as they were spoken above the translation. Each phrase is decoded a second time, so it takes a little longer to appear."
```

  with

```swift
    static let learningHelpText = "Shows the words as they were spoken above the translation. Each phrase is decoded a second time, so it takes a little longer to appear. Tap any word for its pronunciation and meaning."
```

- [ ] Step 4: Implement the insertion. In `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsView.swift` replace (current lines 46–53, the end of the Source language section and the start of the next)

```swift
                SettingExample(symbol: "globe",
                               text: model.language.map { SettingExamples.sourceLanguagePinned(LanguageCatalog.displayName($0, whenNil: "")) }
                                     ?? SettingExamples.sourceLanguageAuto)
            } footer: {
                Text(SettingsViewModel.sourceLanguageHelpText)
            }

            Section {
```

  with

```swift
                SettingExample(symbol: "globe",
                               text: model.language.map { SettingExamples.sourceLanguagePinned(LanguageCatalog.displayName($0, whenNil: "")) }
                                     ?? SettingExamples.sourceLanguageAuto)
            } footer: {
                Text(SettingsViewModel.sourceLanguageHelpText)
            }

            // M11 §3: directly under Source language, whose footer has just said what an unsure phrase is.
            GuessesSettingsSection(model: model)

            Section {
```

  The Learning footer at (current) line 88, `Text("\(SettingsViewModel.learningHelpText)\n\(SettingsViewModel.romanizeHelpText)")`, picks the new sentence up unchanged; `ScreenHostingTests.testSettingsViewHosts` hosts the screen with the new section in place.

- [ ] Step 5: Run. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/SettingsView.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/SettingExample.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/SettingsViewModel.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/SettingsViewModelTests.swift && grep -rn "Tap a word to hear it" ReVoxMobile ReVoxMobileTests --include=*.swift` — one hit in `SettingExample.swift` plus the test.

- [ ] Step 6: Commit.

```
git add ReVoxMobile/Screens/SettingsView.swift ReVoxMobile/Screens/SettingExample.swift ReVoxMobile/Screens/SettingsViewModel.swift ReVoxMobileTests/SettingsViewModelTests.swift
git commit -m "feat(settings): the Unsure phrases section sits under Source language; the Learning copy says words are tappable

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 4: AppEnvironment owns the word speaker and the production lookup; RootView applies it outermost

- [ ] Step 1: Write the failing tests. In `/home/user/ReVoxMobile/ReVoxMobileTests/AppEnvironmentTests.swift`, directly after `testTestingEnvironmentWiresEveryComponent` (its closing `}` follows the `"default source is the microphone"` assertion), add:

```swift
    /// M11 §2: the word popover's services are one environment value built over the app's own speaker.
    func testWordLookupIsBuiltOverTheAppsWordSpeaker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertTrue(environment.wordLookup.speaker === environment.wordSpeaker, "one speaker for every popover")
        XCTAssertFalse(environment.wordSpeaker.isSpeaking)
        XCTAssertFalse(environment.wordLookup.hasVoice("zz"), "the production lookup asks the system voices; no voice for an unknown code")
    }

    /// M11 §2: a word said through the speaker while the microphone is running would be heard and translated, so
    /// the Say button is disabled exactly then — not during an Other-apps run (the ring carries their audio, not
    /// the speaker) and not while idle.
    func testTheMicrophoneRuleBehindTheSayButton() {
        XCTAssertTrue(AppEnvironment.isMicrophoneRunning(state: .running, captureMode: .microphone))
        XCTAssertTrue(AppEnvironment.isMicrophoneRunning(state: .preparing, captureMode: .microphone), "the session is already open while preparing")
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .running, captureMode: .broadcast))
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .idle, captureMode: .microphone))
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .error, captureMode: .microphone))
    }
```

- [ ] Step 2: Run it. CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/AppEnvironmentTests.swift` parses (the file already imports ReVoxCore for `CaptureMode`).

- [ ] Step 3: Implement `AppEnvironment`. In `/home/user/ReVoxMobile/ReVoxMobile/App/AppEnvironment.swift` replace (current lines 35–36)

```swift
    let onboarding: OnboardingViewModel
    private var interruptionTask: Task<Void, Never>?
```

  with

```swift
    let onboarding: OnboardingViewModel
    /// M11 §2: says one tapped word through its own synthesizer (created on first use); told when the microphone
    /// is running so the Say button is disabled then.
    let wordSpeaker: WordSpeaker
    /// M11 §2: the popover's services, applied to the environment outermost by `RootView`.
    let wordLookup: WordLookup
    private var interruptionTask: Task<Void, Never>?
```

  Replace the `LiveActivity` box (current lines 41–48)

```swift
    @MainActor
    private final class LiveActivity {
        weak var live: LiveViewModel?
        var isBusy: Bool {
            guard let live else { return false }
            return live.state == .running || live.state == .preparing
        }
    }
```

  with

```swift
    @MainActor
    private final class LiveActivity {
        weak var live: LiveViewModel?
        var isBusy: Bool {
            guard let live else { return false }
            return live.state == .running || live.state == .preparing
        }
        /// M11 §2: the word speaker's rule, read at every tap of Say.
        var isMicrophoneRunning: Bool {
            guard let live else { return false }
            return AppEnvironment.isMicrophoneRunning(state: live.state, captureMode: live.captureMode)
        }
    }

    /// M11 §2, pure: a word said through the speaker while the microphone session is open (preparing or running)
    /// would be heard and translated back; an Other-apps run reads the ring, not the speaker, so it is allowed.
    static func isMicrophoneRunning(state: LiveState, captureMode: CaptureMode) -> Bool {
        (state == .running || state == .preparing) && captureMode == .microphone
    }
```

  In `init`, replace (current lines 95–96)

```swift
        activity.live = live
        live.volume = voiceVolume   // the Live screen's volume slider writes the players' box (M9)
```

  with

```swift
        activity.live = live
        live.volume = voiceVolume   // the Live screen's volume slider writes the players' box (M9)
        // A local, never `self`: the closure is created before initialisation completes. The synthesizer is made on
        // the first `speak`, so a test environment never pays for one.
        let speaker = WordSpeaker(isMicrophoneRunning: { activity.isMicrophoneRunning })
        self.wordSpeaker = speaker
        self.wordLookup = WordLookup.production(speaker: speaker)
```

  (`live()` and `testing(root:)` need no change: both go through this `init`.)

- [ ] Step 4: Implement `RootView`. In `/home/user/ReVoxMobile/ReVoxMobile/App/RootView.swift` replace (current lines 28–33)

```swift
        // M10: the first-run tutorial, shown on appear until this version of it has been finished or skipped, and
        // again whenever Settings › "Show the tutorial" resets it. A full-screen cover: it cannot be swiped away.
        .fullScreenCover(isPresented: $onboarding.shouldShowNow) {
            OnboardingView(model: onboarding)
        }
    }
```

  with

```swift
        // M10: the first-run tutorial, shown on appear until this version of it has been finished or skipped, and
        // again whenever Settings › "Show the tutorial" resets it. A full-screen cover: it cannot be swiped away.
        .fullScreenCover(isPresented: $onboarding.shouldShowNow) {
            OnboardingView(model: onboarding)
        }
        // M11 §2: outermost, after the cover — presented content inherits only the environment set outside the
        // presenting modifier, and the tutorial's Learning page promises tappable words.
        .environment(\.wordLookup, environment.wordLookup)
    }
```

- [ ] Step 5: Run. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/App/AppEnvironment.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/App/RootView.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/AppEnvironmentTests.swift && python3 scripts/dev/check-core-imports.py --all` — `AppEnvironment.swift` already imports ReVoxCore (`CaptureMode`, `Settings`); `RootView.swift` uses no core type. `ScreenHostingTests.testRootViewHostsAllThreeTabs` hosts `RootView(environment: AppEnvironment.testing(…))` on the simulator, so the environment modifier is exercised.

- [ ] Step 6: Commit.

```
git add ReVoxMobile/App/AppEnvironment.swift ReVoxMobile/App/RootView.swift ReVoxMobileTests/AppEnvironmentTests.swift
git commit -m "feat(app): the word lookup is built over the app's word speaker and reaches every screen, the tutorial included

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 5: Screenshots — a greyed Unsure row in `live-running`, the popover's content as `learning-word`; gates

- [ ] Step 1: Write the capture changes (screenshot tests are their own proof: `capture` asserts the image is not blank). In `/home/user/ReVoxMobile/ReVoxMobileTests/ScreenshotTests.swift` replace (current lines 148–152)

```swift
        for (index, (language, english)) in Self.sampleTranscript.enumerated() {
            let original = index == 0 ? "Buenos días, gracias por acompañarnos hoy." : ""
            running.handle(.entry(TranscriptEntry(timestamp: Date().addingTimeInterval(Double(index - 4) * 9), language: language,
                                                  original: original, english: english)))
        }
```

  with

```swift
        for (index, (language, english)) in Self.sampleTranscript.enumerated() {
            let original = index == 0 ? "Buenos días, gracias por acompañarnos hoy." : ""
            running.handle(.entry(TranscriptEntry(timestamp: Date().addingTimeInterval(Double(index - 4) * 9), language: language,
                                                  original: original, english: english)))
        }
        // M11 §3: a phrase the gates were unsure about — greyed, marked Unsure, never spoken — under the others.
        running.handle(.entry(TranscriptEntry(timestamp: Date().addingTimeInterval(-2), language: "es", original: "",
                                              english: "Could you repeat the last number?", isGuess: true)))
```

  and, after `testCapturesEveryScreenInTheReadme`'s closing `}` (before `static let sampleTranscript`), add:

```swift
    /// M11 §2: the popover's content, hosted on its own — a popover with its arrow cannot be captured without a
    /// presentation. Every service is answered, so the image shows the whole thing: pronunciation with a Say
    /// button, a meaning, the dictionary button and the sentence.
    func testCapturesTheLearningWordPopover() async throws {
        let sentence = SettingExamples.spanishOriginal
        let words = WordSplitter.words(in: sentence, language: "es")
        let word = try XCTUnwrap(words.first { $0.text == "estación" })
        let lookup = WordLookup(speaker: WordSpeaker(isMicrophoneRunning: { false }),
                                hasVoice: { _ in true },
                                hasDefinition: { _ in true },
                                translatorAvailability: { _ in .ready })
        let model = WordPopoverModel(word: word, language: "es", original: sentence, english: SettingExamples.spanishEnglish, lookup: lookup)
        await model.load()
        model.receiveMeaning("station")
        try capture("learning-word", VStack(spacing: 0) {
            WordPopoverView(model: model)
                .frame(maxWidth: 360)
                .padding(.top, 24)
            Spacer(minLength: 0)
        })
    }
```

  The `live-running` frame already runs with `running.isLearning = true` and a Spanish original on its first row, so the chips of §2 appear in that capture without any further change.

- [ ] Step 2: Run. CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/ScreenshotTests.swift`; `python3 scripts/dev/check-test-autoclosures.py` — the `await model.load()` is a statement, not inside an assertion autoclosure, so it passes.

- [ ] Step 3: Run every gate before the last commit:

```
python3 scripts/dev/check-core-imports.py --all
python3 scripts/dev/check-test-autoclosures.py
python3 scripts/dev/check-tests-are-discoverable.py
bash scripts/ci/check-constant-coverage.sh
/home/user/swift/usr/bin/swift test --package-path ReVoxCore
for f in ReVoxMobile/Screens/LiveTranscriptRowView.swift ReVoxMobile/Screens/SettingsView.swift ReVoxMobile/Screens/SettingExample.swift ReVoxMobile/Screens/SettingsViewModel.swift ReVoxMobile/App/RootView.swift ReVoxMobile/App/AppEnvironment.swift ReVoxMobileTests/RowAccessibilityTests.swift ReVoxMobileTests/SettingsViewModelTests.swift ReVoxMobileTests/AppEnvironmentTests.swift ReVoxMobileTests/ScreenshotTests.swift; do /home/user/swift/usr/bin/swiftc -parse "$f" || echo "PARSE FAILED: $f"; done
git grep -n -i -E "claude|anthropic|openai|gpt|gemini|copilot" -- ReVoxMobile ReVoxMobileTests ':!*.md' || echo "no model or product names"
```

  All four scripts print their green line, the core suite passes unchanged (this lane touches no core file), every file parses, and the grep finds nothing.

- [ ] Step 4: Commit.

```
git add ReVoxMobileTests/ScreenshotTests.swift
git commit -m "test(screenshots): live-running shows a greyed Unsure row; learning-word captures the popover's content

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

**Cross-lane needs**

- **L4 (must match before this lane compiles):** `OriginalWord` with `id`, `text`, `range`; `WordSplitter.words(in:language:)` callable from the main actor; `OriginalWordsLine(original:language:words:lookup:onSelect:)` taking `Binding<WordPopoverModel?>`; `WordPopoverModel(word:language:original:english:lookup:)` with `load() async` and `receiveMeaning(_:)`; `WordPopoverView(model:)` with its other parameters defaulted; `WordLookup` memberwise init `(speaker:hasVoice:hasDefinition:translatorAvailability:)`, `.unavailable`, `production(speaker:)` and `EnvironmentValues.wordLookup`; `WordTranslatorAvailability.ready`; `WordSpeaker(isMicrophoneRunning:)` with `isSpeaking` readable. If L4 lands different labels, the only call sites are `LiveTranscriptRowView.select`/`textColumn`, `AppEnvironment.init` and `ScreenshotTests.testCapturesTheLearningWordPopover` — adapt those, not L4.
- **L3:** `AppEnvironment.swift` is edited by both L3 (benchmark wiring) and this lane; the anchors quoted here (`let onboarding` / `private var interruptionTask`, the `LiveActivity` box, `activity.live = live` / `live.volume = voiceVolume`) are from the pre-L3 file — re-quote from the merged file if L3 moved them.
- **L1 (merged):** `SettingExample.swift` and `SettingsViewModel.swift` were L1's in wave 1; §7 assigns "the Learning copy" to L5 and the copy lives in those two files, so this lane edits them after the merge. `SettingsViewModelTests.swift` (the copy test) and `AppEnvironmentTests.swift` (unlisted in §7) are touched for the same reason.
- **L6:** the tutorial cover inherits `\.wordLookup` only because `RootView` applies it after `.fullScreenCover`; L6's `OnboardingTests` comparison `OnboardingDemo.learningText(learning: true, romanize: false) == SettingExamples.learning(true)` keeps holding with the new string.
- **L7:** place `docs/screenshots/learning-word.png` in the README (the design suggested the empty cell of the onboarding row, captioned as the popover's content, not a popover with an arrow), and refresh `live-running.png`'s caption for the greyed Unsure row and the word chips.
- **Owner-side (device):** VoiceOver on the Settings › Learning example (the combined row nested in `SettingExample`'s own combine) should list the "Look up ‹word›" actions; Voice Control does not reach chips inside an `.ignore` line — a known limit of v1.