## Lane L4: Tappable words — splitter, popover, speaker, lookup

Spec: `/home/user/ReVoxMobile/docs/superpowers/specs/2026-09-05-milestone-11-design.md` §2 and §7 row L4. Root for every command below: the lane's checkout — `/home/user/ReVoxMobile` on `claude/revoxmobile-ios-app-hkajbf`, or the L4 worktree (`/home/user/ReVoxMobile/.claude/worktrees/m11-L4`); substitute that path wherever `cd /home/user/ReVoxMobile` appears. Every file here is app-target or test-target Swift, so nothing runs locally: `swiftc -parse` is the only check, and the CI simulator compiles and runs the tests.

**Files**

Create:
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordSplitter.swift` — `OriginalWord`, `WordSplitter` (NLTokenizer, code mapping, right-to-left list, main-actor cache with `resetCache()`)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordFlowLayout.swift` — `PillFlowLayout`'s packing copied, spacing 0, `explicitAlignment` for `.firstTextBaseline`
- `/home/user/ReVoxMobile/ReVoxMobile/Speech/WordSpeaker.swift` — own `AVSpeechSynthesizer`, `usesApplicationAudioSession = false`, lazy, `isSpeaking`, disabled during a microphone run
- `/home/user/ReVoxMobile/ReVoxMobile/Translation/WordTranslation.swift` — `WordTranslatorAvailability`, `WordTranslation` (iOS 18 `translationTask`), `WordTranslatorProbe`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordLookup.swift` — `WordLookup`, `EnvironmentValues.wordLookup`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverContent.swift` — pure `make(...)`, every string
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverModel.swift` — `@MainActor @Observable`, injected closures
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/DictionaryView.swift` — `DictionaryTerm`, `DictionaryView`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverView.swift` — the popover content
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/OriginalWordsLine.swift` — chips, highlight, per-row popover, dictionary hand-off, `WordLookUpActions`

Modify:
- `/home/user/ReVoxMobile/docs/hig-audit/checks.json` — four targets and one contrast pair

Test files (create):
- `/home/user/ReVoxMobile/ReVoxMobileTests/WordSplitterTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/WordSpeakerTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/WordPopoverTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/LearningHostingTests.swift`

Not touched by this lane (wave 2 wires them): `LiveTranscriptRowView.swift`, `RootView.swift`, `AppEnvironment.swift`, `PillFlowLayout.swift`, `SettingExample.swift`, `SettingsViewModel.swift`, `RowAccessibilityTests.swift`, `ScreenshotTests.swift`.

**Interfaces**

Consumes (existing code on the branch; none of it changes in wave 1):
- `SystemSpeaker.selectVoice(identifier: String?, language: String, voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice?` and `SystemSpeaker.isEnglish(_ language: String) -> Bool` (`ReVoxMobile/Speech/SystemSpeaker.swift`)
- `Romanizer.romanize(_ text: String) -> String?` (ReVoxCore)
- `LanguageCatalog.displayName(_ code: String?, whenNil: String) -> String` (`ReVoxMobile/Screens/LanguageCatalog.swift`)
- `struct LivePillButtonStyle: ButtonStyle` (`ReVoxMobile/Screens/Live/LiveControlPill.swift`; L1 keeps it, spec §1)
- `PillFlowLayout.rows(sizes:available:spacing:)` is *copied*, not called, so L1's rewrite of `PillFlowLayoutTests` cannot collide
- Test target: `LockedBox<Value>` (`ReVoxMobileTests/SileroVADTests.swift`), `waitUntil(_:timeout:file:line:details:_:)` (`ReVoxMobileTests/Support/AsyncAssertions.swift`)
- Seam commit: nothing directly; `LiveTranscriptRow.isGuess` is read by L5's row view, not here

Produces (exact API wave 2 calls):
- `struct OriginalWord: Identifiable, Equatable, Sendable { let id: Int; let text: String; let range: Range<String.Index> }`
- `WordSplitter.words(in text: String, language: String) -> [OriginalWord]`; `@MainActor WordSplitter.cachedWords(in text: String, language: String) -> [OriginalWord]`; `WordSplitter.isRightToLeft(_ whisperCode: String) -> Bool`; `WordSplitter.rightToLeftLanguages: Set<String>`; `WordSplitter.translatorCode(for whisperCode: String) -> String`; `WordSplitter.nlLanguage(for whisperCode: String) -> NLLanguage`; `@MainActor WordSplitter.resetCache()`; `@MainActor WordSplitter.cacheCount: Int`; `WordSplitter.cacheLimit = 512`
- `struct WordFlowLayout: Layout` (no parameters; `WordFlowLayout.spacing = 0`)
- `struct OriginalWordsLine: View { init(original: String, language: String, english: String, words: [OriginalWord], lookup: Binding<WordPopoverModel?>) }` — reads `@Environment(\.wordLookup)` itself; `OriginalWordsLine.chipMinimumHeight = 44`, `chipCornerRadius = 6`, `selectedFillOpacity = 0.22`, `customActionLimit = 12`; `OriginalWordsLine.actionWords(_ words: [OriginalWord]) -> [OriginalWord]`; `@MainActor OriginalWordsLine.select(_ word: OriginalWord, language: String, original: String, english: String, lookup service: WordLookup, into binding: Binding<WordPopoverModel?>)`
- `struct WordLookUpActions: ViewModifier { init(words: [OriginalWord], language: String, original: String, english: String, lookup: Binding<WordPopoverModel?>) }` — the row applies it to its combined entry element (`.modifier(WordLookUpActions(...))`)
- `@MainActor @Observable final class WordPopoverModel { init(word: OriginalWord, language: String, original: String, english: String, lookup: WordLookup); var content: WordPopoverContent; var translationRequest: String?; var speaker: WordSpeaker?; var languageName: String; func load() async; func receiveMeaning(_ text: String?); @discardableResult func speak() -> Bool }`
- `struct WordPopoverView: View { init(model: WordPopoverModel, onLookUp: @escaping (String) -> Void = { _ in }, onClose: @escaping () -> Void = {}) }`; `WordPopoverView.idealWidth = 300`, `maximumWidth = 360`, `buttonHeight = 44`; `static func highlightedSentence(_ example: WordPopoverContent.Example) -> Text`
- `struct WordPopoverContent: Equatable` with `enum MeaningResult { case pending, text(String), absent }`, `enum Meaning { case loading, found(String), note(String) }`, `struct Example { original, range, english }`, `static func make(word:languageName:latin:hasVoice:isMicrophoneRunning:hasDefinition:translator:meaning:original:range:english:)`, and the statics `pronunciationHeader`, `meaningHeader`, `exampleHeader`, `speakTitle(_:)`, `speakingTitle`, `speakAccessibilityLabel(word:languageName:)`, `speakHint(languageName:)`, `microphoneNote`, `noVoiceNote(languageName:)`, `translatingText`, `noMeaningText`, `needsIOS18Text`, `needsDownloadText(languageName:)`, `unsupportedText(languageName:)`, `dictionaryButtonTitle`, `dictionaryHint`, `noDictionaryNote(languageName:)`, `closeLabel`, `lookUpActionTitle(_:)`
- `struct WordLookup { var speaker: WordSpeaker?; var hasVoice: @MainActor (String) -> Bool; var hasDefinition: @MainActor (String) -> Bool; var translatorAvailability: @Sendable (String) async -> WordTranslatorAvailability; static var unavailable: WordLookup; @MainActor static func production(speaker: WordSpeaker) -> WordLookup }`; `EnvironmentValues.wordLookup: WordLookup` (default `.unavailable`)
- `@MainActor @Observable final class WordSpeaker { init(isMicrophoneRunning: @escaping @MainActor () -> Bool = { false }, voices: @escaping @MainActor () -> [AVSpeechSynthesisVoice] = { AVSpeechSynthesisVoice.speechVoices() }, speak: Speak? = nil, stop: Stop? = nil); private(set) var isSpeaking: Bool; var isMicrophoneRunning: Bool; func availableVoices() -> [AVSpeechSynthesisVoice]; static func utterance(for word: String, language: String, voices: [AVSpeechSynthesisVoice]) -> AVSpeechUtterance?; @discardableResult func speak(_ word: String, language: String) -> Bool; func stop(); func noteStarted(); func noteFinished() }`
- `enum WordTranslatorAvailability: Equatable, Sendable { case unavailableOnThisiOS, needsDownload, unsupported, ready }`; `WordTranslatorProbe.availability(language: String) async -> WordTranslatorAvailability`; `struct WordTranslation: ViewModifier { init(word: String?, language: String, onResult: @escaping @MainActor (String?) -> Void) }`
- `struct DictionaryTerm: Identifiable, Equatable { let term: String }`; `struct DictionaryView: UIViewControllerRepresentable { init(term: String) }`
- What L5 writes with these (given here so the wiring is one copy-paste; L5 owns the files):
  - `LiveTranscriptRowView`: `@State private var lookup: WordPopoverModel?`; `static func tapsWords(language: String, original: String, english: String) -> Bool { !original.isEmpty && original != english && !SystemSpeaker.isEnglish(language) && !WordSplitter.isRightToLeft(language) }`; in `textColumn`, replace `Text(original).font(.body).foregroundStyle(.secondary)` with `let words = Self.tapsWords(language: language, original: original, english: english) ? WordSplitter.cachedWords(in: original, language: language) : []` then `if words.isEmpty { Text(original).font(.body).foregroundStyle(.secondary) } else { OriginalWordsLine(original: original, language: language, english: english, words: words, lookup: $lookup) }`; on the combined entry row `.modifier(WordLookUpActions(words: words, language: language, original: original, english: english, lookup: $lookup))` (words empty when not tappable). The guess greying is applied outside `OriginalWordsLine`.
  - `AppEnvironment`: `let wordSpeaker: WordSpeaker`, `let wordLookup: WordLookup`; after `activity.live = live`: `let liveForWords = live; self.wordSpeaker = WordSpeaker(isMicrophoneRunning: { [weak liveForWords] in guard let liveForWords else { return false }; return liveForWords.captureMode == .microphone && (liveForWords.state == .running || liveForWords.state == .preparing) }); self.wordLookup = WordLookup.production(speaker: wordSpeaker)`.
  - `RootView`: `.environment(\.wordLookup, environment.wordLookup)` outermost, after `.fullScreenCover`, so the tutorial inherits it.

---

### Task 1: WordSplitter — words, code mapping, right-to-left list, cache

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordSplitter.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/WordSplitterTests.swift`.

- [ ] Write the failing test. Create `ReVoxMobileTests/WordSplitterTests.swift`:

```swift
import XCTest
import NaturalLanguage
@testable import ReVoxMobile

/// M11 §2: the words a Learning row offers for tapping. CJK boundaries are Apple's and are never pinned; the
/// tests hold the invariants — no punctuation, nothing lost, ranges that index the sentence.
final class WordSplitterTests: XCTestCase {
    func testSpanishSplitsOnSpacesAndDropsPunctuation() {
        XCTAssertEqual(WordSplitter.words(in: "¿Dónde está la estación?", language: "es").map(\.text), ["Dónde", "está", "la", "estación"])
        XCTAssertEqual(WordSplitter.words(in: "Buenos días.", language: "es").map(\.text), ["Buenos", "días"])
    }

    func testRangesIndexTheSentenceAndIdsAreTheWordOrder() {
        let sentence = "Buenos días, gracias por acompañarnos hoy."
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.map(\.id), Array(0..<words.count))
        XCTAssertEqual(words.count, 6)
        for word in words {
            XCTAssertEqual(String(sentence[word.range]), word.text)
        }
    }

    func testCJKIsSplitWithoutSpacesAndWithoutPunctuation() {
        let japanese = WordSplitter.words(in: "こんにちは、世界！", language: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertFalse(japanese.contains { $0.text.contains("、") || $0.text.contains("！") })
        XCTAssertEqual(japanese.map(\.text).joined(), "こんにちは世界")
        XCTAssertEqual(WordSplitter.words(in: "你好世界", language: "zh").map(\.text).joined(), "你好世界")
        XCTAssertEqual(WordSplitter.words(in: "東京タワー", language: "ja").map(\.text).joined(), "東京タワー")
    }

    func testMixedScriptsKeepEveryPart() {
        let words = WordSplitter.words(in: "Tokyo 東京", language: "ja").map(\.text)
        XCTAssertEqual(words.first, "Tokyo")
        XCTAssertEqual(words.dropFirst().joined(), "東京")
    }

    func testEmptyAndBlankGiveNoWords() {
        XCTAssertEqual(WordSplitter.words(in: "", language: "es"), [])
        XCTAssertEqual(WordSplitter.words(in: "   ", language: "es"), [])
        XCTAssertEqual(WordSplitter.words(in: "…", language: "es"), [])
    }

    func testWhisperCodesMapToNaturalLanguageAndTheTranslator() {
        XCTAssertEqual(WordSplitter.nlLanguage(for: "zh"), .simplifiedChinese)
        XCTAssertEqual(WordSplitter.nlLanguage(for: "yue"), .traditionalChinese)
        XCTAssertEqual(WordSplitter.nlLanguage(for: "jw"), NLLanguage(rawValue: "jv"))
        XCTAssertEqual(WordSplitter.nlLanguage(for: "es"), .spanish)
        XCTAssertEqual(WordSplitter.translatorCode(for: "zh"), "zh-Hans")
        XCTAssertEqual(WordSplitter.translatorCode(for: "yue"), "zh-Hant")
        XCTAssertEqual(WordSplitter.translatorCode(for: "jw"), "jv")
        XCTAssertEqual(WordSplitter.translatorCode(for: "es"), "es")
    }

    func testRightToLeftLanguagesAreNamed() {
        XCTAssertEqual(WordSplitter.rightToLeftLanguages, ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"])
        XCTAssertTrue(WordSplitter.isRightToLeft("ar"))
        XCTAssertTrue(WordSplitter.isRightToLeft("he"))
        XCTAssertFalse(WordSplitter.isRightToLeft("es"))
    }

    /// The cache is process-global and the hosting tests fill it too, so the test resets it first and reads
    /// counts only after that reset.
    @MainActor
    func testTheCacheAnswersTheSecondCallWithoutTokenisingAndClearsAtTheLimit() {
        WordSplitter.resetCache()
        XCTAssertEqual(WordSplitter.cacheCount, 0)
        let first = WordSplitter.cachedWords(in: "Buenos días.", language: "es")
        let second = WordSplitter.cachedWords(in: "Buenos días.", language: "es")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, WordSplitter.words(in: "Buenos días.", language: "es"))
        XCTAssertEqual(WordSplitter.cacheCount, 1, "one distinct (language, sentence)")
        _ = WordSplitter.cachedWords(in: "Buenos días.", language: "pt")
        XCTAssertEqual(WordSplitter.cacheCount, 2, "the language is part of the key")
        for index in 0..<(WordSplitter.cacheLimit - 2) {
            _ = WordSplitter.cachedWords(in: "frase \(index)", language: "es")
        }
        XCTAssertEqual(WordSplitter.cacheCount, WordSplitter.cacheLimit)
        _ = WordSplitter.cachedWords(in: "una más", language: "es")
        XCTAssertEqual(WordSplitter.cacheCount, 1, "cleared at the limit, then the new sentence")
        XCTAssertEqual(WordSplitter.cacheLimit, 512)
        WordSplitter.resetCache()
    }
}
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordSplitterTests.swift
```
(Parses; the test fails on CI until the type exists.)

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/WordSplitter.swift`:

```swift
import Foundation
import NaturalLanguage

/// One tappable word of a Learning row's original line (M11 §2). `id` is the word's index in the sentence, so a
/// repeated word ("la … la") is two chips with their own identity; `range` indexes the sentence it came from,
/// for the popover's highlighted example.
struct OriginalWord: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let range: Range<String.Index>
}

/// Splits a sentence into the words a reader can tap (M11 §2). `NLTokenizer` is what segments Japanese, Chinese
/// and Thai without spaces; punctuation and whitespace never become chips. App target only — NaturalLanguage is
/// not on Linux, and ReVoxCore stays Foundation-only.
enum WordSplitter {
    /// Cleared, not evicted: a session is a few hundred distinct sentences, and the cache exists to stop the
    /// 1 s TimelineView ticks re-tokenising, not to survive a long day.
    static let cacheLimit = 512
    /// Scripts written right to left, whose chips the left-to-right `WordFlowLayout` cannot lay out yet: the row
    /// shows their original as plain text (M11 §2).
    static let rightToLeftLanguages: Set<String> = ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"]

    @MainActor private static var cache: [String: [OriginalWord]] = [:]

    /// A token is kept only when it holds a letter or a digit, so "¿", "," and "。" never become chips.
    static func words(in text: String, language: String) -> [OriginalWord] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(nlLanguage(for: language))
        var words: [OriginalWord] = []
        for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            let token = String(text[range])
            guard token.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            words.append(OriginalWord(id: words.count, text: token, range: range))
        }
        return words
    }

    /// WhisperKit's two-letter codes are ISO 639-1; NLLanguage names Chinese by script and Javanese by "jv".
    static func nlLanguage(for whisperCode: String) -> NLLanguage {
        switch whisperCode.lowercased() {
        case "zh": return .simplifiedChinese
        case "yue": return .traditionalChinese
        case "jw": return NLLanguage(rawValue: "jv")
        default: return NLLanguage(rawValue: whisperCode.lowercased())
        }
    }

    /// The same mapping as a string, handed to `Locale.Language(identifier:)` for Apple's on-device translator.
    static func translatorCode(for whisperCode: String) -> String {
        switch whisperCode.lowercased() {
        case "zh": return "zh-Hans"
        case "yue": return "zh-Hant"
        case "jw": return "jv"
        default: return whisperCode.lowercased()
        }
    }

    static func isRightToLeft(_ whisperCode: String) -> Bool {
        rightToLeftLanguages.contains(whisperCode.lowercased())
    }

    /// Memoised per (language, sentence) on the main actor: the row body under the TimelineView is a dictionary hit.
    @MainActor
    static func cachedWords(in text: String, language: String) -> [OriginalWord] {
        let key = "\(language)\u{1F}\(text)"
        if let hit = cache[key] { return hit }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        let split = words(in: text, language: language)
        cache[key] = split
        return split
    }

    /// Test seams.
    @MainActor static var cacheCount: Int { cache.count }
    @MainActor static func resetCache() { cache.removeAll() }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/WordSplitter.swift ReVoxMobileTests/WordSplitterTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/WordSplitter.swift ReVoxMobileTests/WordSplitterTests.swift && git commit -F - <<'EOF'
feat(learning): WordSplitter — NLTokenizer words, code mapping, main-actor cache (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 2: WordFlowLayout — the tiled line with a first-text baseline

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordFlowLayout.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/LearningHostingTests.swift`.

- [ ] Write the failing test. Create `ReVoxMobileTests/LearningHostingTests.swift` (the popover, the line and the dictionary sheet are appended to this class in Tasks 7 and 8):

```swift
import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: the word chips, the popover and the dictionary sheet lay out in a `UIHostingController` at the
/// default and the largest accessibility text sizes, with the inert default lookup and with injected services.
/// SwiftUI has no unit-test renderer, so this proves the views build and do not trap on first layout — the bar
/// `ScreenHostingTests` holds every other screen to.
@MainActor
final class LearningHostingTests: XCTestCase {
    private let sentence = "Buenos días, gracias por acompañarnos hoy."
    private let english = "Good morning, thank you for joining us today."

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    // MARK: WordFlowLayout

    /// `PillFlowLayout`'s greedy in-order packing, copied with no gap: three 100 pt chips are 300 pt, a fourth
    /// needs 400 and wraps; an over-wide chip still gets a row of its own; a row is as tall as its tallest chip.
    func testWordFlowLayoutPacksLikeThePillLayoutWithNoGap() {
        func size(_ width: CGFloat, _ height: CGFloat = 44) -> CGSize { CGSize(width: width, height: height) }
        XCTAssertEqual(WordFlowLayout.spacing, 0)
        let rows = WordFlowLayout.rows(sizes: [size(100), size(100), size(100), size(100)], available: 320)
        XCTAssertEqual(rows.map(\.items), [[0, 1, 2], [3]])
        XCTAssertEqual(rows.map(\.height), [44, 44])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50), size(500), size(50)], available: 300).map(\.items), [[0], [1], [2]])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50, 44), size(50, 60)], available: 300)[0].height, 60)
        XCTAssertEqual(WordFlowLayout.rows(sizes: [], available: 300), [])
        XCTAssertEqual(WordFlowLayout.width(for: .unspecified, sizes: [size(100), size(100)]), 200)
        XCTAssertEqual(WordFlowLayout.width(for: ProposedViewSize(width: 150, height: nil), sizes: [size(100), size(100)]), 150)
    }

    func testWordFlowLayoutHostsInsideABaselineAlignedRow() {
        host(WordFlowLayout {
            Text("Buenos").font(.body)
            Text("días").font(.body)
        })
        host(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("10:41:07").font(.caption.monospacedDigit())
            WordFlowLayout {
                ForEach(0..<12, id: \.self) { index in
                    Text("palabra\(index)").font(.body).frame(minHeight: 44)
                }
            }
        }
        .frame(width: 390))
    }
}
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/LearningHostingTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/WordFlowLayout.swift`:

```swift
import SwiftUI

/// The wrapped line of word chips (M11 §2): `PillFlowLayout`'s greedy in-order packing with no gap between
/// chips, so the chips tile the line and every touch on it lands on a word, plus a first-text baseline — that of
/// the first chip — so the row's `HStack(alignment: .firstTextBaseline)` keeps the time and the language badge on
/// the first word's baseline rather than on the bottom of a 44 pt line. Copied rather than shared so this file
/// and the Live strip's layout stay in their own lanes.
struct WordFlowLayout: Layout {
    static let spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = Self.width(for: proposal, sizes: sizes)
        let rows = Self.rows(sizes: sizes, available: width)
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
        return CGSize(width: width, height: height)
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
            y += row.height
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
        return bounds.minY + (row.height - sizes[0].height) / 2 + first[VerticalAlignment.firstTextBaseline]
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
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/WordFlowLayout.swift ReVoxMobileTests/LearningHostingTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/WordFlowLayout.swift ReVoxMobileTests/LearningHostingTests.swift && git commit -F - <<'EOF'
feat(learning): WordFlowLayout — chips tiled at spacing 0 with a first-text baseline (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 3: WordSpeaker — one word through its own synthesizer

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Speech/WordSpeaker.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/WordSpeakerTests.swift`.

- [ ] Write the failing test. Create `ReVoxMobileTests/WordSpeakerTests.swift`:

```swift
import XCTest
import AVFAudio
@testable import ReVoxMobile

/// M11 §2: the popover's Say button. The synthesizer is never built here — `speak` and `stop` are injected
/// recorders — and a language the simulator has no voice for skips, as `SystemSpeakerTests` does.
@MainActor
final class WordSpeakerTests: XCTestCase {
    private final class Recorder {
        var utterances: [String] = []
        var stops = 0
    }

    private func makeSpeaker(microphoneRunning: Bool = false, voices: [AVSpeechSynthesisVoice], recorder: Recorder) -> WordSpeaker {
        WordSpeaker(isMicrophoneRunning: { microphoneRunning }, voices: { voices },
                    speak: { recorder.utterances.append($0.speechString) }, stop: { recorder.stops += 1 })
    }

    private func spanishVoices() throws -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard voices.contains(where: { $0.language.lowercased().hasPrefix("es") }) else {
            throw XCTSkip("this simulator has no Spanish voice installed")
        }
        return voices
    }

    func testAWordWithNoVoiceOrNoTextGivesNoUtterance() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        XCTAssertNil(WordSpeaker.utterance(for: "hola", language: "zz", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "   ", language: "es", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "hola", language: "es", voices: []))
    }

    /// An English row never shows chips (§2), so nothing may ask the speaker for English.
    func testEnglishGivesNoUtterance() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        XCTAssertNil(WordSpeaker.utterance(for: "hello", language: "en", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "hello", language: "en-GB", voices: voices))
    }

    func testAWordInALanguageWithAVoiceIsSaidWithThatVoice() throws {
        let voices = try spanishVoices()
        let utterance = try XCTUnwrap(WordSpeaker.utterance(for: " estación ", language: "es", voices: voices))
        XCTAssertEqual(utterance.speechString, "estación")
        XCTAssertEqual(utterance.voice?.language.lowercased().hasPrefix("es"), true)
        XCTAssertEqual(utterance.volume, 1)
    }

    func testSpeakStopsWhatIsInFlightFirst() throws {
        let voices = try spanishVoices()
        let recorder = Recorder()
        let speaker = makeSpeaker(voices: voices, recorder: recorder)
        XCTAssertTrue(speaker.speak("Buenos", language: "es"))
        XCTAssertTrue(speaker.speak("días", language: "es"))
        XCTAssertEqual(recorder.utterances, ["Buenos", "días"])
        XCTAssertEqual(recorder.stops, 2, "one stop before each word")
        XCTAssertFalse(speaker.speak("hola", language: "zz"))
        XCTAssertEqual(recorder.utterances.count, 2)
        XCTAssertEqual(recorder.stops, 2, "nothing to stop for when there is nothing to say")
    }

    /// A word said through the speaker would be heard by the microphone, segmented and translated back.
    func testAMicrophoneRunDisablesTheSpeaker() throws {
        let voices = try spanishVoices()
        let recorder = Recorder()
        let speaker = makeSpeaker(microphoneRunning: true, voices: voices, recorder: recorder)
        XCTAssertTrue(speaker.isMicrophoneRunning)
        XCTAssertFalse(speaker.speak("Buenos", language: "es"))
        XCTAssertEqual(recorder.utterances, [])
        XCTAssertEqual(recorder.stops, 0)
    }

    /// The first `speechVoices()` of a launch takes hundreds of milliseconds; the list is read once per speaker.
    func testTheVoiceListIsReadOnce() {
        let reads = LockedBox(0)
        let speaker = WordSpeaker(voices: { reads.mutate { $0 += 1 }; return [] }, speak: { _ in }, stop: {})
        _ = speaker.availableVoices()
        _ = speaker.availableVoices()
        XCTAssertFalse(speaker.speak("hola", language: "es"), "no voices, nothing said")
        XCTAssertEqual(reads.value, 1)
    }

    func testSpeakingEdgesFollowTheDelegateHooks() {
        let speaker = WordSpeaker(speak: { _ in }, stop: {})
        XCTAssertFalse(speaker.isSpeaking)
        speaker.noteStarted()
        XCTAssertTrue(speaker.isSpeaking)
        speaker.noteFinished()
        XCTAssertFalse(speaker.isSpeaking)
    }
}
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordSpeakerTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Speech/WordSpeaker.swift`:

```swift
import AVFAudio
import Foundation
import Observation

/// Says one word in its language (M11 §2): the popover's Say button. Its own `AVSpeechSynthesizer` with
/// `usesApplicationAudioSession = false`, so it mixes with whatever is playing, needs no session configuration
/// and never touches the resident mask, the ducking cycle or the pipeline's player. The synthesizer is built on
/// the first word, so a launch (and every test environment) pays nothing for it.
///
/// Silent while a microphone run is going: the word would come out of the speaker, be heard by the microphone,
/// segmented and translated — a feedback row every time. During an Other-apps run the ring carries other apps'
/// audio, not the speaker, so the word is allowed.
@MainActor
@Observable
final class WordSpeaker {
    typealias Speak = @MainActor (AVSpeechUtterance) -> Void
    typealias Stop = @MainActor () -> Void

    private(set) var isSpeaking = false

    private let isMicrophoneRunningNow: @MainActor () -> Bool
    private let loadVoices: @MainActor () -> [AVSpeechSynthesisVoice]
    private let injectedSpeak: Speak?
    private let injectedStop: Stop?
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var cachedVoices: [AVSpeechSynthesisVoice]?

    /// `speak` and `stop` nil = the real synthesizer; the tests inject recorders. `voices` is read once and kept.
    init(isMicrophoneRunning: @escaping @MainActor () -> Bool = { false },
         voices: @escaping @MainActor () -> [AVSpeechSynthesisVoice] = { AVSpeechSynthesisVoice.speechVoices() },
         speak: Speak? = nil, stop: Stop? = nil) {
        self.isMicrophoneRunningNow = isMicrophoneRunning
        self.loadVoices = voices
        self.injectedSpeak = speak
        self.injectedStop = stop
    }

    var isMicrophoneRunning: Bool { isMicrophoneRunningNow() }

    /// The installed voices, listed once per speaker: the first `speechVoices()` of a launch takes hundreds of
    /// milliseconds, and the popover asks on every tap.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        if let cachedVoices { return cachedVoices }
        let voices = loadVoices()
        cachedVoices = voices
        return voices
    }

    /// Pure: the utterance for one word, or nil when the text is blank, the language is English (an English row
    /// never shows chips, so nothing may ask) or this iPhone has no voice for the language.
    static func utterance(for word: String, language: String, voices: [AVSpeechSynthesisVoice]) -> AVSpeechUtterance? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SystemSpeaker.isEnglish(language) else { return nil }
        guard let voice = SystemSpeaker.selectVoice(identifier: nil, language: language, voices: voices) else { return nil }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.volume = 1
        return utterance
    }

    /// Stops anything in flight first. False, and nothing said, while a microphone run is going or when there is
    /// no utterance for the word.
    @discardableResult
    func speak(_ word: String, language: String) -> Bool {
        guard !isMicrophoneRunning else { return false }
        guard let utterance = Self.utterance(for: word, language: language, voices: availableVoices()) else { return false }
        stop()
        if let injectedSpeak {
            injectedSpeak(utterance)
        } else {
            synthesizerForSpeaking().speak(utterance)
        }
        return true
    }

    func stop() {
        if let injectedStop {
            injectedStop()
        } else {
            synthesizer?.stopSpeaking(at: .immediate)
        }
    }

    /// The delegate's edges, and the test seam for them.
    func noteStarted() { isSpeaking = true }
    func noteFinished() { isSpeaking = false }

    private func synthesizerForSpeaking() -> AVSpeechSynthesizer {
        if let synthesizer { return synthesizer }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = false
        let delegate = Delegate(owner: self)
        synthesizer.delegate = delegate
        self.delegate = delegate
        self.synthesizer = synthesizer
        return synthesizer
    }

    /// Not main-actor isolated (a nested type does not inherit the class's isolation); every edge hops to the owner.
    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        weak var owner: WordSpeaker?

        init(owner: WordSpeaker) {
            self.owner = owner
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteStarted() }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteFinished() }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteFinished() }
        }
    }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Speech/WordSpeaker.swift ReVoxMobileTests/WordSpeakerTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Speech/WordSpeaker.swift ReVoxMobileTests/WordSpeakerTests.swift && git commit -F - <<'EOF'
feat(speech): WordSpeaker — says one word through its own synthesizer, silent during a microphone run (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 4: WordTranslation (iOS 18 probe and task) and the WordLookup environment value

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Translation/WordTranslation.swift`, `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordLookup.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/WordPopoverTests.swift`.

- [ ] Write the failing test. Create `ReVoxMobileTests/WordPopoverTests.swift` (Tasks 5, 6 and 8 append to this class):

```swift
import XCTest
import SwiftUI
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: what the popover says for every source combination, the model that resolves a tapped word, the
/// services it reaches through the environment, and the row's selection hand-off.
@MainActor
final class WordPopoverTests: XCTestCase {
    private let sentence = "¿Dónde está la estación?"
    private let english = "Where is the station?"

    private func lookup(hasVoice: Bool = false, hasDefinition: Bool = false,
                        translator: WordTranslatorAvailability = .unavailableOnThisiOS, speaker: WordSpeaker? = nil) -> WordLookup {
        WordLookup(speaker: speaker, hasVoice: { _ in hasVoice }, hasDefinition: { _ in hasDefinition },
                   translatorAvailability: { _ in translator })
    }

    // MARK: The environment value

    /// Every hosted test row gets this: no speaker, no voice, no dictionary, iOS 17 copy — and no framework touched.
    func testTheDefaultLookupIsHonestAndInert() async {
        let lookup = WordLookup.unavailable
        XCTAssertNil(lookup.speaker)
        XCTAssertFalse(lookup.hasVoice("es"))
        XCTAssertFalse(lookup.hasDefinition("estación"))
        let availability = await lookup.translatorAvailability("es")
        XCTAssertEqual(availability, .unavailableOnThisiOS)
    }

    /// The production services: the speaker's cached voice list and the translator probe. The probe never
    /// downloads; the CI simulator runs iOS 18 or later, so the answer is one of the three iOS 18 cases.
    func testTheProductionLookupReadsTheSpeakersVoicesAndTheProbe() async {
        let speaker = WordSpeaker(voices: { AVSpeechSynthesisVoice.speechVoices() }, speak: { _ in }, stop: {})
        let lookup = WordLookup.production(speaker: speaker)
        XCTAssertTrue(lookup.speaker === speaker)
        XCTAssertFalse(lookup.hasVoice("zz"))
        XCTAssertTrue(lookup.hasVoice("en"), "every iPhone speaks English")
        let availability = await lookup.translatorAvailability("es")
        XCTAssertNotEqual(availability, .unavailableOnThisiOS, "the iOS 18 branch answered; which case depends on the simulator's packs")
        let probed = await WordTranslatorProbe.availability(language: "es")
        XCTAssertEqual(probed, availability)
    }
}
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordPopoverTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Translation/WordTranslation.swift` (the second and last file that imports the weak-linked framework; every reference sits in an `@available(iOS 18, *)` type reached through `#available`, mirroring `TwoWayTranslation`):

```swift
import SwiftUI
import Translation

/// Whether Apple's on-device translator can give the meaning of a single word (M11 §2).
enum WordTranslatorAvailability: Equatable, Sendable {
    /// iOS 17: the framework is not there, and nothing here touches it.
    case unavailableOnThisiOS
    /// iOS 18, the pair is supported but not downloaded; a word tap never triggers the download prompt.
    case needsDownload
    case unsupported
    case ready
}

/// Translates one word to English through a self-contained `translationTask` on the popover content (M11 §2):
/// source = the row's language, target = English. `nil` word = no task, on iOS 18 too. The two-way bridge and
/// its serving are never involved.
struct WordTranslation: ViewModifier {
    let word: String?
    let language: String
    let onResult: @MainActor (String?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(AppleWordTranslation(word: word, language: language, onResult: onResult))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct AppleWordTranslation: ViewModifier {
    let word: String?
    let language: String
    let onResult: @MainActor (String?) -> Void

    /// `Configuration` is `Equatable`, so SwiftUI starts one task per word and ends it when the word goes nil.
    private var configuration: TranslationSession.Configuration? {
        guard let word, !word.isEmpty else { return nil }
        return TranslationSession.Configuration(source: Locale.Language(identifier: WordSplitter.translatorCode(for: language)),
                                                target: Locale.Language(identifier: "en"))
    }

    func body(content: Content) -> some View {
        content.translationTask(configuration) { session in
            guard let word else { return }
            // Only a `.ready` (installed) pair ever gets here, so `prepareTranslation()` and its download prompt are not needed.
            let translated = try? await session.translate(word).targetText
            await onResult(translated)
        }
    }
}

/// Answers without ever downloading: `LanguageAvailability` on iOS 18, a constant on iOS 17.
enum WordTranslatorProbe {
    static func availability(language: String) async -> WordTranslatorAvailability {
        if #available(iOS 18, *) {
            return await AppleWordTranslatorProbe.availability(language: language)
        }
        return .unavailableOnThisiOS
    }
}

@available(iOS 18, *)
private enum AppleWordTranslatorProbe {
    static func availability(language: String) async -> WordTranslatorAvailability {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: WordSplitter.translatorCode(for: language)),
            to: Locale.Language(identifier: "en")
        )
        switch status {
        case .installed: return .ready
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
```

Create `ReVoxMobile/Screens/Learning/WordLookup.swift`:

```swift
import SwiftUI
import UIKit

/// The services a word popover needs (M11 §2), carried by the SwiftUI environment so the shared row view gains no
/// parameters and every hosted test row gets an honest, inert default: no speaker, no voice, no dictionary,
/// iOS 17 copy — without touching a framework. `AppEnvironment` builds the production one and `RootView` applies
/// it outermost, after `.fullScreenCover`, so the tutorial inherits it.
struct WordLookup {
    var speaker: WordSpeaker?
    /// Whether this iPhone has a voice for a language code.
    var hasVoice: @MainActor (String) -> Bool
    /// Whether this iPhone's dictionaries have an entry for a word.
    var hasDefinition: @MainActor (String) -> Bool
    /// Apple's on-device translator for a language code → English; never triggers a download.
    var translatorAvailability: @Sendable (String) async -> WordTranslatorAvailability

    static var unavailable: WordLookup {
        WordLookup(speaker: nil, hasVoice: { _ in false }, hasDefinition: { _ in false },
                   translatorAvailability: { _ in .unavailableOnThisiOS })
    }

    /// The production services: the speaker's voice list (read once), the iPhone's dictionaries, the probe.
    @MainActor
    static func production(speaker: WordSpeaker) -> WordLookup {
        WordLookup(
            speaker: speaker,
            hasVoice: { language in
                SystemSpeaker.selectVoice(identifier: nil, language: language, voices: speaker.availableVoices()) != nil
            },
            hasDefinition: { term in UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) },
            translatorAvailability: { language in await WordTranslatorProbe.availability(language: language) }
        )
    }
}

private struct WordLookupKey: EnvironmentKey {
    static var defaultValue: WordLookup { .unavailable }
}

extension EnvironmentValues {
    var wordLookup: WordLookup {
        get { self[WordLookupKey.self] }
        set { self[WordLookupKey.self] = newValue }
    }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Translation/WordTranslation.swift ReVoxMobile/Screens/Learning/WordLookup.swift ReVoxMobileTests/WordPopoverTests.swift && python3 scripts/dev/check-core-imports.py
```
(The import gate strips `import` lines, so ReVoxCore's `Translation` struct is not confused with the framework; `TranslationSession` and `LanguageAvailability` are not core names.)

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Translation/WordTranslation.swift ReVoxMobile/Screens/Learning/WordLookup.swift ReVoxMobileTests/WordPopoverTests.swift && git commit -F - <<'EOF'
feat(learning): WordTranslation probe and task modifier, WordLookup environment value (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 5: WordPopoverContent — every string and decision, pure

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverContent.swift`; modify `/home/user/ReVoxMobile/ReVoxMobileTests/WordPopoverTests.swift`.

- [ ] Write the failing test. In `ReVoxMobileTests/WordPopoverTests.swift`, insert the two helpers directly after the existing `lookup(...)` helper (before `// MARK: The environment value`), and the content tests inside the class before its final `}`:

```swift
    private func word(_ text: String, in sentence: String, language: String = "es") throws -> OriginalWord {
        try XCTUnwrap(WordSplitter.words(in: sentence, language: language).first { $0.text == text })
    }

    /// "estación" in the Spanish sample sentence, with every input at a sensible default.
    private func content(latin: String? = nil, hasVoice: Bool = true, isMicrophoneRunning: Bool = false, hasDefinition: Bool? = nil,
                         translator: WordTranslatorAvailability = .ready, meaning: WordPopoverContent.MeaningResult = .pending,
                         languageName: String = "Spanish") throws -> WordPopoverContent {
        let station = try word("estación", in: sentence)
        return WordPopoverContent.make(word: station.text, languageName: languageName, latin: latin, hasVoice: hasVoice,
                                       isMicrophoneRunning: isMicrophoneRunning, hasDefinition: hasDefinition, translator: translator,
                                       meaning: meaning, original: sentence, range: station.range, english: english)
    }
```

```swift
    // MARK: Content

    func testMakeKeepsTheLatinFormOnlyWhenThereIsOne() throws {
        XCTAssertEqual(try content(latin: "ohayou").latin, "ohayou")
        XCTAssertNil(try content(latin: nil).latin)
    }

    func testMakeShowsTheTranslatorsProgressTextAndAbsence() throws {
        XCTAssertEqual(try content(translator: .ready, meaning: .pending).meaning, .loading)
        XCTAssertEqual(try content(translator: .ready, meaning: .text("station")).meaning, .found("station"))
        XCTAssertEqual(try content(translator: .ready, meaning: .absent).meaning, .note(WordPopoverContent.noMeaningText))
        XCTAssertEqual(WordPopoverContent.noMeaningText, "No meaning found for this word.")
    }

    func testMakeExplainsEveryUnavailableTranslator() throws {
        XCTAssertEqual(try content(translator: .unavailableOnThisiOS).meaning, .note(WordPopoverContent.needsIOS18Text))
        XCTAssertEqual(WordPopoverContent.needsIOS18Text, "Meanings for single words need iOS 18. The whole sentence is translated below.")
        XCTAssertEqual(try content(translator: .needsDownload).meaning, .note(WordPopoverContent.needsDownloadText(languageName: "Spanish")))
        XCTAssertEqual(WordPopoverContent.needsDownloadText(languageName: "Spanish"),
                       "To see what a word means, download Spanish for Apple's on-device translator in Settings › Apps › Translate.")
        XCTAssertEqual(try content(translator: .unsupported).meaning, .note(WordPopoverContent.unsupportedText(languageName: "Spanish")))
        XCTAssertEqual(WordPopoverContent.unsupportedText(languageName: "Spanish"),
                       "Apple's on-device translator has no Spanish, so only the whole sentence is translated.")
        // A pending answer is a note, never progress, when no translator will ever answer.
        XCTAssertEqual(try content(translator: .unsupported, meaning: .pending).meaning,
                       .note(WordPopoverContent.unsupportedText(languageName: "Spanish")))
    }

    func testTheSayButtonFollowsTheVoiceAndTheMicrophone() throws {
        let live = try content(hasVoice: true, isMicrophoneRunning: false)
        XCTAssertTrue(live.hasVoice)
        XCTAssertTrue(live.canSpeak)
        XCTAssertNil(live.speakDisabledNote)
        XCTAssertNil(live.voiceNote)
        let listening = try content(hasVoice: true, isMicrophoneRunning: true)
        XCTAssertFalse(listening.canSpeak)
        XCTAssertEqual(listening.speakDisabledNote, WordPopoverContent.microphoneNote)
        XCTAssertEqual(WordPopoverContent.microphoneNote, "Stop listening to hear words through the microphone")
        let silent = try content(hasVoice: false, languageName: "Japanese")
        XCTAssertFalse(silent.canSpeak)
        XCTAssertNil(silent.speakDisabledNote)
        XCTAssertEqual(silent.voiceNote, "This iPhone has no Japanese voice. Add one in Settings › Accessibility › Spoken Content › Voices.")
    }

    /// `hasDefinition` is resolved last and can be slow: neither the button nor the note shows until it is known.
    func testTheDictionaryButtonAndNoteWaitUntilTheAnswerIsKnown() throws {
        let unknown = try content(hasDefinition: nil)
        XCTAssertFalse(unknown.showsDictionaryButton)
        XCTAssertNil(unknown.dictionaryNote)
        let known = try content(hasDefinition: true)
        XCTAssertTrue(known.showsDictionaryButton)
        XCTAssertNil(known.dictionaryNote)
        let missing = try content(hasDefinition: false)
        XCTAssertFalse(missing.showsDictionaryButton)
        XCTAssertEqual(missing.dictionaryNote,
                       "This word is not in this iPhone's dictionaries. You can add a Spanish one in Settings › General › Dictionary.")
    }

    func testTheExampleKeepsTheSentenceAndTheRange() throws {
        let example = try content().example
        XCTAssertEqual(example.original, sentence)
        XCTAssertEqual(String(sentence[example.range]), "estación")
        XCTAssertEqual(example.english, english)
    }

    func testCopyNamesTheWordAndTheLanguage() {
        XCTAssertEqual(WordPopoverContent.pronunciationHeader, "Pronunciation")
        XCTAssertEqual(WordPopoverContent.meaningHeader, "Meaning")
        XCTAssertEqual(WordPopoverContent.exampleHeader, "In this sentence")
        XCTAssertEqual(WordPopoverContent.speakTitle("estación"), "Say estación")
        XCTAssertEqual(WordPopoverContent.speakingTitle, "Speaking…")
        XCTAssertEqual(WordPopoverContent.speakAccessibilityLabel(word: "おはよう", languageName: "Japanese"), "Say おはよう in Japanese")
        XCTAssertEqual(WordPopoverContent.speakHint(languageName: "Spanish"), "Speaks the word with this iPhone's Spanish voice")
        XCTAssertEqual(WordPopoverContent.translatingText, "Translating…")
        XCTAssertEqual(WordPopoverContent.dictionaryButtonTitle, "Look up in the dictionary")
        XCTAssertEqual(WordPopoverContent.dictionaryHint, "Opens this iPhone's dictionary at this word")
        XCTAssertEqual(WordPopoverContent.closeLabel, "Close")
        XCTAssertEqual(WordPopoverContent.lookUpActionTitle("la"), "Look up la")
    }
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordPopoverTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/WordPopoverContent.swift`:

```swift
import Foundation

/// Everything the word popover shows and every decision about which source is shown (M11 §2), as a value built
/// by one pure function from plain inputs — the seam the tests read and the view renders.
struct WordPopoverContent: Equatable {
    /// What the translator has said so far.
    enum MeaningResult: Equatable, Sendable {
        case pending
        case text(String)
        case absent
    }

    /// What the Meaning section shows.
    enum Meaning: Equatable {
        case loading
        case found(String)
        case note(String)
    }

    struct Example: Equatable {
        let original: String
        let range: Range<String.Index>
        let english: String
    }

    let word: String
    let languageName: String
    /// `Romanizer.romanize(word)`: nil for a word already in Latin letters.
    let latin: String?
    let hasVoice: Bool
    /// The Say button is live: a voice exists and no microphone run is going.
    let canSpeak: Bool
    /// Under a disabled Say button: why it is disabled.
    let speakDisabledNote: String?
    /// In place of the Say button when there is no voice.
    let voiceNote: String?
    let meaning: Meaning
    let showsDictionaryButton: Bool
    let dictionaryNote: String?
    let example: Example

    static func make(word: String, languageName: String, latin: String?, hasVoice: Bool, isMicrophoneRunning: Bool,
                     hasDefinition: Bool?, translator: WordTranslatorAvailability, meaning: MeaningResult,
                     original: String, range: Range<String.Index>, english: String) -> WordPopoverContent {
        let shown: Meaning
        switch translator {
        case .ready:
            switch meaning {
            case .pending: shown = .loading
            case .text(let text): shown = .found(text)
            case .absent: shown = .note(noMeaningText)
            }
        case .unavailableOnThisiOS: shown = .note(needsIOS18Text)
        case .needsDownload: shown = .note(needsDownloadText(languageName: languageName))
        case .unsupported: shown = .note(unsupportedText(languageName: languageName))
        }
        return WordPopoverContent(
            word: word,
            languageName: languageName,
            latin: latin,
            hasVoice: hasVoice,
            canSpeak: hasVoice && !isMicrophoneRunning,
            speakDisabledNote: hasVoice && isMicrophoneRunning ? microphoneNote : nil,
            voiceNote: hasVoice ? nil : noVoiceNote(languageName: languageName),
            meaning: shown,
            showsDictionaryButton: hasDefinition == true,
            dictionaryNote: hasDefinition == false ? noDictionaryNote(languageName: languageName) : nil,
            example: Example(original: original, range: range, english: english)
        )
    }

    // MARK: Copy (M11 §2)

    static let pronunciationHeader = "Pronunciation"
    static let meaningHeader = "Meaning"
    static let exampleHeader = "In this sentence"
    static func speakTitle(_ word: String) -> String { "Say \(word)" }
    static let speakingTitle = "Speaking…"
    static func speakAccessibilityLabel(word: String, languageName: String) -> String { "Say \(word) in \(languageName)" }
    static func speakHint(languageName: String) -> String { "Speaks the word with this iPhone's \(languageName) voice" }
    /// A spoken word would be heard by the microphone and translated back.
    static let microphoneNote = "Stop listening to hear words through the microphone"
    static func noVoiceNote(languageName: String) -> String {
        "This iPhone has no \(languageName) voice. Add one in Settings › Accessibility › Spoken Content › Voices."
    }
    static let translatingText = "Translating…"
    static let noMeaningText = "No meaning found for this word."
    static let needsIOS18Text = "Meanings for single words need iOS 18. The whole sentence is translated below."
    static func needsDownloadText(languageName: String) -> String {
        "To see what a word means, download \(languageName) for Apple's on-device translator in Settings › Apps › Translate."
    }
    static func unsupportedText(languageName: String) -> String {
        "Apple's on-device translator has no \(languageName), so only the whole sentence is translated."
    }
    static let dictionaryButtonTitle = "Look up in the dictionary"
    static let dictionaryHint = "Opens this iPhone's dictionary at this word"
    /// `dictionaryHasDefinition` is also false for an inflected form the installed dictionary lacks, so the note
    /// never claims a dictionary is missing.
    static func noDictionaryNote(languageName: String) -> String {
        "This word is not in this iPhone's dictionaries. You can add a \(languageName) one in Settings › General › Dictionary."
    }
    static let closeLabel = "Close"
    static func lookUpActionTitle(_ word: String) -> String { "Look up \(word)" }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/WordPopoverContent.swift ReVoxMobileTests/WordPopoverTests.swift && python3 scripts/dev/check-test-autoclosures.py ReVoxMobileTests/WordPopoverTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/WordPopoverContent.swift ReVoxMobileTests/WordPopoverTests.swift && git commit -F - <<'EOF'
feat(learning): WordPopoverContent — every string and decision of the word popover (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 6: WordPopoverModel — resolves one tapped word

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverModel.swift`; modify `/home/user/ReVoxMobile/ReVoxMobileTests/WordPopoverTests.swift`.

- [ ] Write the failing test. Append inside `WordPopoverTests`, before the class's final `}`:

```swift
    // MARK: Model

    func testLoadResolvesEverythingAndAsksForATranslationOnlyWhenReady() async throws {
        let morning = try word("おはよう", in: "おはよう", language: "ja")
        let model = WordPopoverModel(word: morning, language: "ja", original: "おはよう", english: "Good morning.",
                                     lookup: lookup(hasVoice: true, hasDefinition: false, translator: .ready))
        XCTAssertNil(model.translationRequest, "nothing is asked before load")
        XCTAssertNil(model.hasDefinition, "unknown until resolved")
        XCTAssertFalse(model.isLoaded)
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.latin, "ohayou")
        XCTAssertTrue(model.hasVoice)
        XCTAssertEqual(model.hasDefinition, false)
        XCTAssertEqual(model.translator, .ready)
        XCTAssertEqual(model.translationRequest, "おはよう")
        XCTAssertEqual(model.languageName, "Japanese")
        let content = model.content
        XCTAssertEqual(content.meaning, .loading)
        XCTAssertEqual(content.latin, "ohayou")
        XCTAssertEqual(content.dictionaryNote, WordPopoverContent.noDictionaryNote(languageName: "Japanese"))
        XCTAssertEqual(content.word, "おはよう")
    }

    func testReceiveMeaningEndsTheRequest() async throws {
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: lookup(translator: .ready))
        await model.load()
        model.receiveMeaning(" station ")
        XCTAssertEqual(model.content.meaning, .found("station"))
        XCTAssertNil(model.translationRequest)
        model.receiveMeaning("platform")
        XCTAssertEqual(model.content.meaning, .found("station"), "the first answer stands")
        let blank = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: lookup(translator: .ready))
        await blank.load()
        blank.receiveMeaning("  ")
        XCTAssertEqual(blank.content.meaning, .note(WordPopoverContent.noMeaningText))
        XCTAssertNil(blank.translationRequest)
    }

    func testIOS17NeverRequestsATranslation() async throws {
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: .unavailable)
        await model.load()
        XCTAssertNil(model.translationRequest)
        XCTAssertEqual(model.content.meaning, .note(WordPopoverContent.needsIOS18Text))
        XCTAssertFalse(model.content.canSpeak)
        XCTAssertEqual(model.content.voiceNote, WordPopoverContent.noVoiceNote(languageName: "Spanish"))
        XCTAssertNil(model.speaker)
        XCTAssertFalse(model.speak())
        XCTAssertNil(model.content.latin, "Latin script already")
        XCTAssertEqual(String(model.content.example.original[model.content.example.range]), "estación")
    }

    func testTheModelReadsTheMicrophoneFromTheSpeaker() async throws {
        let recorded = LockedBox<[String]>([])
        let running = LockedBox(false)
        let speaker = WordSpeaker(isMicrophoneRunning: { running.value }, voices: { AVSpeechSynthesisVoice.speechVoices() },
                                  speak: { utterance in recorded.mutate { $0.append(utterance.speechString) } }, stop: {})
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english,
                                     lookup: lookup(hasVoice: true, speaker: speaker))
        await model.load()
        XCTAssertTrue(model.speaker === speaker)
        XCTAssertTrue(model.content.canSpeak)
        running.mutate { $0 = true }
        XCTAssertFalse(model.content.canSpeak)
        XCTAssertEqual(model.content.speakDisabledNote, WordPopoverContent.microphoneNote)
        XCTAssertFalse(model.speak())
        XCTAssertEqual(recorded.value, [])
        running.mutate { $0 = false }
        guard AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.language.lowercased().hasPrefix("es") }) else {
            throw XCTSkip("this simulator has no Spanish voice installed")
        }
        XCTAssertTrue(model.speak())
        XCTAssertEqual(recorded.value, ["estación"])
    }
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordPopoverTests.swift && python3 scripts/dev/check-test-autoclosures.py ReVoxMobileTests/WordPopoverTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/WordPopoverModel.swift`:

```swift
import Foundation
import Observation
import ReVoxCore

/// Resolves one tapped word (M11 §2): transliteration, voice, translator availability (async), dictionary
/// availability (last — the slow call, after the popover already has content), then the meaning the view's
/// translation task delivers. Created on tap by the row, held in the row's `@State`, so it survives the
/// TimelineView ticks and row appends; every field write re-derives `content`.
@MainActor
@Observable
final class WordPopoverModel {
    let word: OriginalWord
    let language: String
    let original: String
    let english: String
    private let lookup: WordLookup

    private(set) var latin: String?
    private(set) var hasVoice = false
    /// nil until resolved: neither the dictionary button nor its note shows before then.
    private(set) var hasDefinition: Bool?
    private(set) var translator: WordTranslatorAvailability = .unavailableOnThisiOS
    private(set) var meaning: WordPopoverContent.MeaningResult = .pending
    private(set) var isLoaded = false

    init(word: OriginalWord, language: String, original: String, english: String, lookup: WordLookup) {
        self.word = word
        self.language = language
        self.original = original
        self.english = english
        self.lookup = lookup
    }

    /// nil = no Say button ever (the hosted default).
    var speaker: WordSpeaker? { lookup.speaker }

    var languageName: String { LanguageCatalog.displayName(language, whenNil: language) }

    var isMicrophoneRunning: Bool { lookup.speaker?.isMicrophoneRunning ?? false }

    var content: WordPopoverContent {
        WordPopoverContent.make(word: word.text, languageName: languageName, latin: latin, hasVoice: hasVoice,
                                isMicrophoneRunning: isMicrophoneRunning, hasDefinition: hasDefinition, translator: translator,
                                meaning: meaning, original: original, range: word.range, english: english)
    }

    /// The word to translate: non-nil only while a translation is wanted and outstanding. The view attaches
    /// `WordTranslation(word:)` to it; the answer makes it nil, which ends the task and releases the session.
    var translationRequest: String? {
        isLoaded && translator == .ready && meaning == .pending ? word.text : nil
    }

    func load() async {
        guard !isLoaded else { return }
        latin = Romanizer.romanize(word.text)
        hasVoice = lookup.hasVoice(language)
        translator = await lookup.translatorAvailability(language)
        if translator != .ready { meaning = .absent }
        isLoaded = true
        hasDefinition = lookup.hasDefinition(word.text)
    }

    /// Trimmed non-empty → the meaning; blank → absent. The first answer stands.
    func receiveMeaning(_ text: String?) {
        guard meaning == .pending else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        meaning = trimmed.isEmpty ? .absent : .text(trimmed)
    }

    @discardableResult
    func speak() -> Bool {
        lookup.speaker?.speak(word.text, language: language) ?? false
    }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/WordPopoverModel.swift ReVoxMobileTests/WordPopoverTests.swift && python3 scripts/dev/check-core-imports.py
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/WordPopoverModel.swift ReVoxMobileTests/WordPopoverTests.swift && git commit -F - <<'EOF'
feat(learning): WordPopoverModel — resolves a tapped word through injected services (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 7: DictionaryView and WordPopoverView, hosted at default and accessibility sizes

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/DictionaryView.swift`, `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/WordPopoverView.swift`; modify `/home/user/ReVoxMobile/ReVoxMobileTests/LearningHostingTests.swift`.

- [ ] Write the failing test. Append inside `LearningHostingTests`, before the class's final `}` (the `lookup` helper is shared with Task 8):

```swift
    private func lookup(hasVoice: Bool, hasDefinition: Bool, translator: WordTranslatorAvailability, speaker: WordSpeaker? = nil) -> WordLookup {
        WordLookup(speaker: speaker, hasVoice: { _ in hasVoice }, hasDefinition: { _ in hasDefinition },
                   translatorAvailability: { _ in translator })
    }

    // MARK: WordPopoverView and DictionaryView

    /// Every source combination the popover can show, at the default size and at `.accessibility5`, where the
    /// content adapts to a sheet. `translationRequest` is nil in every hosted model, so no translation task is
    /// ever attached on the CI simulator.
    func testWordPopoverViewHostsEveryState() async throws {
        let gracias = try XCTUnwrap(WordSplitter.words(in: sentence, language: "es").first { $0.text == "gracias" })
        func model(_ lookup: WordLookup) -> WordPopoverModel {
            WordPopoverModel(word: gracias, language: "es", original: sentence, english: english, lookup: lookup)
        }
        // iOS 17 copy, the default lookup: no speaker, no voice, no dictionary.
        host(WordPopoverView(model: model(.unavailable)))
        for translator in [WordTranslatorAvailability.needsDownload, .unsupported] {
            let unavailable = model(lookup(hasVoice: false, hasDefinition: false, translator: translator))
            await unavailable.load()
            XCTAssertNil(unavailable.translationRequest)
            host(WordPopoverView(model: unavailable))
        }
        // No voice, a dictionary entry: the voice note and the Look up button.
        let noVoice = model(lookup(hasVoice: false, hasDefinition: true, translator: .unavailableOnThisiOS))
        await noVoice.load()
        host(WordPopoverView(model: noVoice, onLookUp: { _ in }, onClose: {}))
        // Ready and answered, with a live Say button.
        let speaker = WordSpeaker(voices: { [] }, speak: { _ in }, stop: {})
        let ready = model(lookup(hasVoice: true, hasDefinition: false, translator: .ready, speaker: speaker))
        await ready.load()
        ready.receiveMeaning("thank you")
        XCTAssertNil(ready.translationRequest)
        host(WordPopoverView(model: ready))
        host(WordPopoverView(model: ready).environment(\.dynamicTypeSize, .accessibility5))
        speaker.noteStarted()
        host(WordPopoverView(model: ready))                       // "Speaking…"
        speaker.noteFinished()
        // Say disabled while a microphone run is going.
        let listening = WordSpeaker(isMicrophoneRunning: { true }, voices: { [] }, speak: { _ in }, stop: {})
        let disabled = model(lookup(hasVoice: true, hasDefinition: false, translator: .ready, speaker: listening))
        await disabled.load()
        disabled.receiveMeaning(nil)
        XCTAssertEqual(disabled.content.speakDisabledNote, WordPopoverContent.microphoneNote)
        host(WordPopoverView(model: disabled))
        XCTAssertEqual(WordPopoverView.idealWidth, 300)
        XCTAssertEqual(WordPopoverView.maximumWidth, 360)
        XCTAssertEqual(WordPopoverView.buttonHeight, 44)
    }

    func testTheHighlightedSentenceKeepsEveryCharacter() throws {
        let words = WordSplitter.words(in: sentence, language: "es")
        for word in words {
            let example = WordPopoverContent.Example(original: sentence, range: word.range, english: english)
            host(WordPopoverView.highlightedSentence(example))
        }
        XCTAssertEqual(words.map(\.text), ["Buenos", "días", "gracias", "por", "acompañarnos", "hoy"])
    }

    func testDictionaryViewHosts() {
        host(DictionaryView(term: "station"))
        XCTAssertEqual(DictionaryTerm(term: "station").id, "station")
    }
```

- [ ] Run it. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/LearningHostingTests.swift && python3 scripts/dev/check-test-autoclosures.py ReVoxMobileTests/LearningHostingTests.swift
```

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/DictionaryView.swift`:

```swift
import SwiftUI
import UIKit

/// A word in the iPhone's own dictionaries (M11 §2). No API returns definition text, so this is the system view,
/// in a sheet the popover opens after it has dismissed itself. Only the dictionaries the user has downloaded in
/// Settings › General › Dictionary answer; the popover offers the sheet only when `dictionaryHasDefinition` said so.
struct DictionaryTerm: Identifiable, Equatable {
    let term: String
    var id: String { term }
}

struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
```

Create `ReVoxMobile/Screens/Learning/WordPopoverView.swift`:

```swift
import SwiftUI

/// The word popover's content (M11 §2): the word and its language with a 44 pt Close; Pronunciation (the Latin
/// form, the Say button or the voice note); Meaning (progress, the text or a note, then the dictionary button or
/// its note); In this sentence (the original with the word highlighted, and the English). A popover on iPhone at
/// the regular text sizes, a medium/large sheet at the accessibility sizes, where a 300 pt column would be one
/// narrow strip. Hostable on its own, which is how the tests and the screenshots render it.
struct WordPopoverView: View {
    let model: WordPopoverModel
    var onLookUp: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static let idealWidth: CGFloat = 300
    static let maximumWidth: CGFloat = 360
    /// The frame sits inside each button's label, so the hit area is the 44 pt the audit records, not the border.
    static let buttonHeight: CGFloat = 44

    var body: some View {
        let content = model.content
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(content)
                pronunciation(content)
                meaning(content)
                example(content)
            }
            .padding(16)
        }
        .frame(idealWidth: Self.idealWidth, maxWidth: Self.maximumWidth)
        .presentationCompactAdaptation(dynamicTypeSize.isAccessibilitySize ? .sheet : .popover)
        .presentationDetents([.medium, .large])
        .modifier(WordTranslation(word: model.translationRequest, language: model.language,
                                  onResult: { model.receiveMeaning($0) }))
        .task { await model.load() }
    }

    private func header(_ content: WordPopoverContent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.word).font(.title3.weight(.semibold))
                Text(content.languageName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WordPopoverContent.closeLabel)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func pronunciation(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.pronunciationHeader)
        if let latin = content.latin {
            Text(latin).font(.body)
        }
        if let speaker = model.speaker, content.hasVoice {
            Button {
                model.speak()
            } label: {
                Label(speaker.isSpeaking ? WordPopoverContent.speakingTitle : WordPopoverContent.speakTitle(content.word),
                      systemImage: speaker.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                    .frame(minHeight: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .disabled(!content.canSpeak)
            .accessibilityLabel(WordPopoverContent.speakAccessibilityLabel(word: content.word, languageName: content.languageName))
            .accessibilityHint(content.canSpeak ? WordPopoverContent.speakHint(languageName: content.languageName)
                                                : WordPopoverContent.microphoneNote)
            if let note = content.speakDisabledNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } else if let note = content.voiceNote {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func meaning(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.meaningHeader)
        switch content.meaning {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text(WordPopoverContent.translatingText).font(.callout).foregroundStyle(.secondary)
            }
        case .found(let text):
            Text(text).font(.body)
        case .note(let note):
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        if content.showsDictionaryButton {
            Button {
                onLookUp(content.word)
            } label: {
                Label(WordPopoverContent.dictionaryButtonTitle, systemImage: "book")
                    .frame(minHeight: Self.buttonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityHint(WordPopoverContent.dictionaryHint)
        } else if let note = content.dictionaryNote {
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func example(_ content: WordPopoverContent) -> some View {
        sectionHeader(WordPopoverContent.exampleHeader)
        Self.highlightedSentence(content.example).font(.body).foregroundStyle(.secondary)
        Text(content.example.english).font(.body)
    }

    /// The sentence with the word bold and underlined — two cues beside the chip's colour, never colour alone.
    static func highlightedSentence(_ example: WordPopoverContent.Example) -> Text {
        let sentence = example.original
        let before = String(sentence[sentence.startIndex..<example.range.lowerBound])
        let word = String(sentence[example.range])
        let after = String(sentence[example.range.upperBound..<sentence.endIndex])
        return Text(before) + Text(word).bold().underline() + Text(after)
    }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/DictionaryView.swift ReVoxMobile/Screens/Learning/WordPopoverView.swift ReVoxMobileTests/LearningHostingTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/DictionaryView.swift ReVoxMobile/Screens/Learning/WordPopoverView.swift ReVoxMobileTests/LearningHostingTests.swift && git commit -F - <<'EOF'
feat(learning): WordPopoverView and DictionaryView, hosted at default and accessibility sizes (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 8: OriginalWordsLine — chips, highlight, per-row popover, dictionary hand-off, VoiceOver actions

**Files:** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Learning/OriginalWordsLine.swift`; modify `/home/user/ReVoxMobile/ReVoxMobileTests/WordPopoverTests.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/LearningHostingTests.swift`.

- [ ] Write the failing tests. Append inside `WordPopoverTests`, before the class's final `}`:

```swift
    // MARK: Selection (the row's tap and its VoiceOver action)

    /// UIKit refuses to present while a dismissal is in flight: an open popover is closed first and the new
    /// model staged on the next run-loop turn, so `lookup` never points at a word with no popover.
    func testSelectingWhileAnotherPopoverIsOpenClosesItFirst() async throws {
        let holder = LockedBox<WordPopoverModel?>(nil)
        let binding = Binding<WordPopoverModel?>(get: { holder.value }, set: { model in holder.mutate { $0 = model } })
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 4)
        OriginalWordsLine.select(words[0], language: "es", original: sentence, english: english, lookup: .unavailable, into: binding)
        XCTAssertEqual(holder.value?.word, words[0], "nothing open: staged at once")
        OriginalWordsLine.select(words[3], language: "es", original: sentence, english: english, lookup: .unavailable, into: binding)
        XCTAssertNil(holder.value, "the open popover is closed first")
        await waitUntil("the new word staged on the next turn") { holder.value?.word == words[3] }
        XCTAssertEqual(holder.value?.language, "es")
        XCTAssertEqual(holder.value?.english, english)
    }

    func testCustomActionsAreCappedAtTwelveWords() {
        let many = WordSplitter.words(in: (1...20).map { "palabra\($0)" }.joined(separator: " "), language: "es")
        XCTAssertEqual(many.count, 20)
        XCTAssertEqual(OriginalWordsLine.actionWords(many).map(\.id), Array(0..<12))
        XCTAssertEqual(OriginalWordsLine.customActionLimit, 12)
        let few = WordSplitter.words(in: "Buenos días.", language: "es")
        XCTAssertEqual(OriginalWordsLine.actionWords(few), few)
        XCTAssertEqual(OriginalWordsLine.actionWords([]), [])
    }
```

Append inside `LearningHostingTests`, before the class's final `}`:

```swift
    // MARK: OriginalWordsLine

    /// The chips with and without a selection, at the default and the largest accessibility size, one- and
    /// two-character Japanese chips with no minimum width, the line inside the row's baseline-aligned HStack as
    /// the row view places it (wave 2), and the custom-action modifier on a combined element.
    func testOriginalWordsLineHostsWithAndWithoutASelection() throws {
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 6)
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil)))
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil))
            .environment(\.dynamicTypeSize, .accessibility5))
        let selected = WordPopoverModel(word: words[1], language: "es", original: sentence, english: english, lookup: .unavailable)
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(selected)))
        let tokyo = "東京タワーに行きます"
        let japanese = WordSplitter.words(in: tokyo, language: "ja")
        XCTAssertFalse(japanese.isEmpty)
        host(OriginalWordsLine(original: tokyo, language: "ja", english: "I am going to Tokyo Tower.", words: japanese, lookup: .constant(nil)))
        host(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("10:41:07").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("es").font(.caption2.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil))
                Text(english).font(.body)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 390))
        host(Text(sentence)
            .accessibilityElement(children: .combine)
            .modifier(WordLookUpActions(words: words, language: "es", original: sentence, english: english, lookup: .constant(nil))))
        XCTAssertEqual(OriginalWordsLine.chipMinimumHeight, 44)
        XCTAssertEqual(OriginalWordsLine.chipCornerRadius, 6)
        XCTAssertEqual(OriginalWordsLine.selectedFillOpacity, 0.22)
    }
```

- [ ] Run them. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/WordPopoverTests.swift ReVoxMobileTests/LearningHostingTests.swift && python3 scripts/dev/check-test-autoclosures.py
```

- [ ] Implement. Create `ReVoxMobile/Screens/Learning/OriginalWordsLine.swift`:

```swift
import SwiftUI

/// The original line of a Learning row as tappable words (M11 §2): chips tiled by `WordFlowLayout`, each a
/// Button at least 44 pt tall with no minimum width (the chips tile the line, so every touch lands on a word,
/// and a Japanese particle stays one character wide); the selected word under a rounded accent highlight in
/// `Color.primary` — two cues, constant weight, so nothing shifts under the finger; one popover per row through
/// the row's `lookup` state; and the dictionary sheet the popover hands over to after it has dismissed.
///
/// One VoiceOver element labelled with the sentence, so the combined row reads exactly as it does without chips;
/// the words are reached through `WordLookUpActions` on the row.
struct OriginalWordsLine: View {
    let original: String
    let language: String
    let english: String
    let words: [OriginalWord]
    @Binding var lookup: WordPopoverModel?

    @Environment(\.wordLookup) private var wordLookup
    @State private var dictionaryTerm: DictionaryTerm?
    @State private var pendingDictionaryTerm: String?

    /// The HIG target height (docs/hig-audit/checks.json, `learning-word-chip`).
    static let chipMinimumHeight: CGFloat = 44
    static let chipCornerRadius: CGFloat = 6
    /// Accent (#12788C) at 22 % over white ≈ #CBE1E6 — `learning-word-selected` in checks.json.
    static let selectedFillOpacity = 0.22
    static let chipHorizontalPadding: CGFloat = 4
    static let chipVerticalPadding: CGFloat = 2
    /// VoiceOver custom actions per row: a long row would otherwise put thirty actions before the row's own.
    static let customActionLimit = 12

    var body: some View {
        WordFlowLayout {
            ForEach(words) { word in
                chip(word)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(original)
        .sheet(item: $dictionaryTerm) { term in
            DictionaryView(term: term.term)
                .presentationDragIndicator(.visible)
                .ignoresSafeArea()
        }
    }

    static func actionWords(_ words: [OriginalWord]) -> [OriginalWord] {
        Array(words.prefix(customActionLimit))
    }

    /// The row's tap and its VoiceOver action. An open popover is closed first and the new model staged on the
    /// next run-loop turn: UIKit refuses to present while a dismissal is in flight, and flipping two
    /// `isPresented` bindings in one update would leave `lookup` pointing at a word with no popover.
    @MainActor
    static func select(_ word: OriginalWord, language: String, original: String, english: String,
                       lookup service: WordLookup, into binding: Binding<WordPopoverModel?>) {
        let model = WordPopoverModel(word: word, language: language, original: original, english: english, lookup: service)
        guard binding.wrappedValue != nil else {
            binding.wrappedValue = model
            return
        }
        binding.wrappedValue = nil
        Task { @MainActor in
            binding.wrappedValue = model
        }
    }

    private func chip(_ word: OriginalWord) -> some View {
        let isSelected = lookup?.word == word
        return Button {
            Self.select(word, language: language, original: original, english: english, lookup: wordLookup, into: $lookup)
        } label: {
            Text(word.text)
                .font(.body)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, Self.chipHorizontalPadding)
                .padding(.vertical, Self.chipVerticalPadding)
                .background(isSelected ? Color.accentColor.opacity(Self.selectedFillOpacity) : Color.clear,
                            in: RoundedRectangle(cornerRadius: Self.chipCornerRadius))
                .frame(minHeight: Self.chipMinimumHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(LivePillButtonStyle())
        .popover(isPresented: isPresented(word)) {
            if let model = lookup, model.word == word {
                WordPopoverView(
                    model: model,
                    onLookUp: { term in
                        // The sheet is presented from `onDisappear`, never while the popover is still animating away.
                        pendingDictionaryTerm = term
                        lookup = nil
                    },
                    onClose: { lookup = nil }
                )
                .onDisappear {
                    if let term = pendingDictionaryTerm {
                        pendingDictionaryTerm = nil
                        dictionaryTerm = DictionaryTerm(term: term)
                    }
                }
            }
        }
    }

    private func isPresented(_ word: OriginalWord) -> Binding<Bool> {
        Binding(
            get: { lookup?.word == word },
            set: { shown in
                if !shown, lookup?.word == word { lookup = nil }
            }
        )
    }
}

/// The row's VoiceOver custom actions, "Look up ‹word›" for the first `customActionLimit` words (M11 §2). The
/// row view applies it to its combined entry element beside the `OriginalWordsLine` it renders, so the actions
/// are on the row itself and certain to appear.
struct WordLookUpActions: ViewModifier {
    let words: [OriginalWord]
    let language: String
    let original: String
    let english: String
    @Binding var lookup: WordPopoverModel?
    @Environment(\.wordLookup) private var wordLookup

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(OriginalWordsLine.actionWords(words)) { word in
                Button(WordPopoverContent.lookUpActionTitle(word.text)) {
                    OriginalWordsLine.select(word, language: language, original: original, english: english,
                                             lookup: wordLookup, into: $lookup)
                }
            }
        }
    }
}
```

- [ ] Run. CI is the compiler: swiftc -parse only.
```
cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/OriginalWordsLine.swift ReVoxMobileTests/WordPopoverTests.swift ReVoxMobileTests/LearningHostingTests.swift
```

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Learning/OriginalWordsLine.swift ReVoxMobileTests/WordPopoverTests.swift ReVoxMobileTests/LearningHostingTests.swift && git commit -F - <<'EOF'
feat(learning): OriginalWordsLine — tappable chips, highlight, per-row popover, VoiceOver actions (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

---

### Task 9: HIG audit bookkeeping and the lane's gates

**Files:** Modify `/home/user/ReVoxMobile/docs/hig-audit/checks.json`.

- [ ] Write the failing check (a JSON load plus the five names that must be present):
```
cd /home/user/ReVoxMobile && python3 -c "
import json
names = {c['name'] for c in json.load(open('docs/hig-audit/checks.json'))['checks']}
missing = {'learning-word-chip', 'learning-popover-close', 'learning-popover-say-word', 'learning-popover-dictionary', 'learning-word-selected'} - names
assert not missing, missing
print('checks.json lists the Learning targets')"
```
(Fails with the five names missing.)

- [ ] Implement. In `docs/hig-audit/checks.json`, replace the line
```
    {"type": "target", "name": "about-licence-link", "w": 358, "h": 44},
```
with
```
    {"type": "target", "name": "about-licence-link", "w": 358, "h": 44},
    {"type": "target", "name": "learning-word-chip", "w": 22, "h": 44, "note": "Documented deviation (M11 §2): the chip is minHeight 44 and as wide as its word (22 pt is a two-letter Spanish word at the default size). Chips tile the line at spacing 0, so every touch on the 44 pt line lands on a word — the allowance HIG makes for inline text links; a 44 pt minimum width would turn a Japanese sentence into spaced-out cells."},
    {"type": "target", "name": "learning-popover-close", "w": 44, "h": 44},
    {"type": "target", "name": "learning-popover-say-word", "w": 140, "h": 44},
    {"type": "target", "name": "learning-popover-dictionary", "w": 220, "h": 44},
```
and replace the line
```
    {"type": "contrast", "name": "secondary-label-on-white", "fg": "#3C3C43", "bg": "#FFFFFF"}
```
with
```
    {"type": "contrast", "name": "secondary-label-on-white", "fg": "#3C3C43", "bg": "#FFFFFF"},
    {"type": "contrast", "name": "learning-word-selected", "fg": "#000000", "bg": "#CBE1E6"}
```
(`#CBE1E6` is the accent asset `#12788C` at `OriginalWordsLine.selectedFillOpacity` 0.22 over white; the selected word is drawn in `Color.primary`.)

- [ ] Run the check again, then every gate the lane must leave green:
```
cd /home/user/ReVoxMobile && python3 -c "
import json
names = {c['name'] for c in json.load(open('docs/hig-audit/checks.json'))['checks']}
missing = {'learning-word-chip', 'learning-popover-close', 'learning-popover-say-word', 'learning-popover-dictionary', 'learning-word-selected'} - names
assert not missing, missing
print('checks.json lists the Learning targets')" \
&& /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Learning/WordSplitter.swift ReVoxMobile/Screens/Learning/WordFlowLayout.swift ReVoxMobile/Screens/Learning/OriginalWordsLine.swift ReVoxMobile/Screens/Learning/WordPopoverContent.swift ReVoxMobile/Screens/Learning/WordPopoverModel.swift ReVoxMobile/Screens/Learning/WordPopoverView.swift ReVoxMobile/Screens/Learning/WordLookup.swift ReVoxMobile/Screens/Learning/DictionaryView.swift ReVoxMobile/Speech/WordSpeaker.swift ReVoxMobile/Translation/WordTranslation.swift ReVoxMobileTests/WordSplitterTests.swift ReVoxMobileTests/WordSpeakerTests.swift ReVoxMobileTests/WordPopoverTests.swift ReVoxMobileTests/LearningHostingTests.swift \
&& python3 scripts/dev/check-core-imports.py --all \
&& python3 scripts/dev/check-test-autoclosures.py \
&& python3 scripts/dev/check-tests-are-discoverable.py \
&& bash scripts/ci/check-constant-coverage.sh \
&& ! grep -rniE "claude|anthropic|openai|gemini|copilot" ReVoxMobile/Screens/Learning ReVoxMobile/Speech/WordSpeaker.swift ReVoxMobile/Translation/WordTranslation.swift ReVoxMobileTests/WordSplitterTests.swift ReVoxMobileTests/WordSpeakerTests.swift ReVoxMobileTests/WordPopoverTests.swift ReVoxMobileTests/LearningHostingTests.swift \
&& echo "L4 gates green"
```
(`check-constant-coverage.sh` reads `ReVoxCore/Tests/ReVoxCoreTests`, which this lane does not touch; it must still pass. The ReVoxCore package is untouched by this lane, so `swift test --package-path ReVoxCore` is unaffected; run `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter RomanizerTests` once to confirm nothing here broke the core build.)

- [ ] Commit.
```
cd /home/user/ReVoxMobile && git add docs/hig-audit/checks.json && git commit -F - <<'EOF'
docs(hig-audit): word chip, popover targets and the selected-word contrast; L4 gates green (M11 L4)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

**Cross-lane needs**

- **L5 (wave 2, `LiveTranscriptRowView.swift`, `AppEnvironment.swift`, `RootView.swift`)** — the wiring given verbatim under Produces: `tapsWords(language:original:english:)`, the `@State lookup`, the `OriginalWordsLine` substitution for `Text(original)` in `textColumn`, `.modifier(WordLookUpActions(...))` on the combined entry row, `AppEnvironment.wordSpeaker` / `wordLookup` with the `isMicrophoneRunning` closure over `live.captureMode` and `live.state`, and `.environment(\.wordLookup, environment.wordLookup)` outermost in `RootView` after `.fullScreenCover`. Apply the guess greying outside `OriginalWordsLine`.
- **L5 (`RowAccessibilityTests`)** — assert `OriginalWordsLine.actionWords(words).count == min(words.count, 12)` and `WordPopoverContent.lookUpActionTitle("estación") == "Look up estación"`; the combined label is unchanged because the line is `.accessibilityElement(children: .ignore)` with `accessibilityLabel(original)`.
- **L5 (`SettingsView.swift`, and whoever holds `SettingExample.swift` / `SettingsViewModel.swift` after L1 merges)** — the spec §2 copy: `SettingExamples.learning(true)` = "The words as spoken appear above the translation. Tap a word to hear it and see what it means." and `SettingsViewModel.learningHelpText` gains "Tap any word for its pronunciation and meaning." This lane does not edit those files.
- **L5 (`ScreenshotTests`) — optional** — a `learning-word` capture of `WordPopoverView(model:)` hosted alone (model for "estación" with a lookup of hasVoice true, hasDefinition true, translator `.ready`, after `await load()` and `receiveMeaning("station")`), captioned as the popover's content, if the README wants it.
- **L6 (tutorial)** — nothing beyond the environment: the Learning page's rows get chips through the real row view once L5 has wired it and `RootView` applies the environment outermost.
- **L1** — keep `LivePillButtonStyle` (`Screens/Live/LiveControlPill.swift`) with its current name and behaviour; the chips use it.
- **Device verification (owner, §8)** — the first `live-running` Learning row shows the time and badge on the first word's baseline (else change `WordFlowLayout.explicitAlignment` to drop `bounds.minY`); a word popover opens, says the word, and the Say button is disabled while listening through the microphone; `UIReferenceLibraryViewController` inside the sheet dismisses by the drag indicator (fallback: wrap `DictionaryView` in a `NavigationStack` with a Done item); the iOS 18 `Settings › Apps › Translate` path in `needsDownloadText` matches the phone.