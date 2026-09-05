# Milestone 11 design: grouped Live controls, You speak / They speak, tappable words, unsure phrases, History bar, on-device benchmark, tutorial refresh

**Status:** accepted 2026-09-05. Produced by a design panel (three independent Live-screen proposals judged by two personas, then synthesised) and one designer plus one sceptical critic per feature; the critics' blocking and should-fix findings are folded in below. The full panel output is not committed; this document is the contract every lane implements.

**Owner's request, verbatim:**
1. "Fix the main screen UI and make the arrangement of the buttons make more sense and group related buttons together."
2. "When using learning mode, i should be able to click on a specific word (it should be highlighted same as in the Apple Translate app) and it should give a small pop-up with the pronunciation and meaning of the word and example."
3. "Rename and make the 2 way conversation more clear for what the 2 languages in the 2 way conversation are. Currently it's very confusing, simplify it as much as possible."
4. "Fix in the Ui the location of the Merge button as it's currently being overlaid with the tab buttons. The merge button (and the other button next to it) are too low."
5. "Guessed sentences should appear as grayed out or something similar instead of completely dropped and there should be a toggle in the settings whether to continue including them in the history (or drop them)."
6. "Make sure the tutorial is updated with the latest UI graphics to not confuse new users."
7. "Re-evaluate and benchmark (on the user's device) the translation models to make expectations more realistic on speed and accuracy of inference. Update the recommendations accordingly."

## Global constraints (unchanged from earlier milestones)

- iOS 17 minimum; Swift 5 language mode; Xcode 26 on CI is the compiler for the app targets (nobody here has Xcode). `Translation.framework` is weak-linked and only used behind `#available(iOS 18, *)`.
- `ReVoxCore` is Foundation-only and must build and test on Linux (`swift test`). No UIKit, AVFoundation, SwiftUI, NaturalLanguage imports there.
- Windows parity: the gate constants (`noSpeechMax` 0.85, `averageLogProbMin` −1.2, `languageProbMin` 0.4, the hallucination list) and the settings JSON keys (`ignored_language`, `two_way`, `two_way_language`, …) do not change. New iOS-only settings use the same snake_case style and decode with a default.
- 44 pt targets, a VoiceOver label and hint on every control, state never carried by colour alone, Dynamic Type wraps rather than truncates, every setting shows an example (`SettingExample`) of what it does with its current value.
- No model identifier or AI product name in any committed file. British-neutral plain English copy.
- The broadcast extension is untouched.

## 1. Live screen: three captioned groups, and the two-way pair named by the people

**Layout** (`LiveControlStrip`, one `PillFlowLayout` per group, a fixed 72 pt caption column as the first subview of each group's layout so pills align across rows; at accessibility type sizes the caption moves above its pills):

```
LISTEN     (🎙 Mic ▾) (◔ Balanced ▾) (ⓘ)
VOICE      (≈ Duck on) (🔊 100%)
LANGUAGES  (⇄ Two-way on) (📖 Learn off)
           (You speak  English ▾) (They speak  Spanish ▾)      ← only while Two-way is on, full width
🔒 Stop to change                                               ← caption line, only while preparing/running
```

Heights at the default type size: 144 pt idle with Two-way off, 194 pt on; +24 pt while locked. Captions are `caption2` semibold, drawn uppercase, secondary, with an explicit `accessibilityLabel` in original case and the header trait; each group is an accessibility container labelled by its caption. The ⓘ is the last member of the LISTEN row and of its container. Every Start-time control keeps `.disabled(isLocked)` and dims to 45 %; the volume pill, the slider and the ⓘ stay live. The lock line is a `Label(lockedText, systemImage: "lock.fill")` in `.caption` under the groups (VoiceOver "Stop to change this"), so tapping Start moves nothing above it. The ⓘ panel (`LiveDetailsPanel`) repeats the three captions as headings, opens with a locked line while locked, and gains a volume line so every pill has an explanation.

**Naming.** The two languages are named by the two people, identically on every surface, and the mode keeps its name:

| Surface | Text |
|---|---|
| Live pill, Settings picker row, Picker title, VoiceOver label | **You speak** — value the language name, or **Choose…** on the pill while unset (VoiceOver value **Not set**) |
| Live pill, Picker title, VoiceOver label | **They speak** — value the language name; `nil`/`""` is shown as **English** (that is what runs); the menu has no None row; the stored value stays `nil` for English |
| Toggle pill | **Two-way on / Two-way off**, VoiceOver "Two-way conversation", hint "Speaks what you say to the other person in their language" |
| Settings section header | **Your language** (replaces "Skip a language"); its footer: "ReVox translates everything it hears into English except the language you speak, which it neither translates nor transcribes. With Two-way on (Live tab), what you say is spoken to the other person in their language instead." plus, while a source language is pinned, "This needs Source language set to Auto-detect, because a pinned language is never detected." |
| First row of the Settings picker | **Not set** (replaces "None"; `LiveView.noLanguageTitle = "Not set"`, `SettingsViewModel.noIgnoredLanguageTitle` reads it) |
| Panel line, Two-way on | "What you say in English is spoken to them in Spanish; what they say is spoken to you in English." / you unset: "Choose the language you speak." / both the same: "You and they both speak English, so there is nothing to translate. Choose the language they speak." |
| Panel line, Two-way off | you unset: "Two-way is off: everything ReVox hears is spoken to you in English, including what you say." / you set: "Two-way is off: English is not translated and not spoken back at you; everything else is spoken to you in English." |
| Settings examples (function names kept) | `skipLanguageNone`: "Everything is translated into English, including you. Choose the language you speak so a conversation is not echoed back at you." · `skipLanguage(name)`: "“Where is the station?” said in English is not translated and not transcribed. Turn on Two-way on the Live tab to have it spoken to the other person in their language instead." · `skipLanguageWhilePinned` same language: "Source language is pinned to English and English is the language you speak, so every phrase counts as yours and nothing is translated. Change one of the two." · pinned elsewhere: "Source language is pinned to French, so nothing is ever heard as English and everything is translated, including you. Set Source language to Auto-detect for You speak to work." |
| They-speak VoiceOver value without a voice | "Spanish, no voice on this iPhone" (`theySpeakAccessibilityValue(name:hasVoice:)`); the pill shows `speaker.slash` |
| Voice note (`LiveViewModel.voiceNote(for:)`) | "This iPhone has no Spanish voice, so what you say to them stays in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices." |
| Pinned-source note (`LiveViewModel.pinnedSourceNote`) | "Source language is pinned to French in Settings, so nothing is heard as English. Set it to Auto-detect for Two-way to work." (you unset: "…so the language you speak cannot be chosen here…") |
| Source-language footer and example (from §3) | "Auto-detect runs Whisper's language detection on every phrase. A phrase it is unsure about is shown greyed and marked Unsure, and is never spoken." · `sourceLanguageAuto`: "Auto-detect hears “¿Dónde está la estación?” as Spanish and translates it. A phrase it cannot place is shown greyed and marked Unsure, and is not spoken." |

"Leave alone", "Reply in", "Don't translate", "Skip a language", "ignored" and "left alone" disappear from every user-visible string, the README, docs/onboarding.md, ADR-0006/0007 and the bug template. Code identifiers (`ignoredLanguage`, `twoWayLanguage`, `ignored`, `twoWayTarget`) and the JSON keys do not change.

**View model additions** (`LiveViewModel`): `theySpeak: String` (get: `twoWayLanguage` or "en"; set: stores `nil` for "en", otherwise the code, through the existing `twoWayLanguage` setter so the voice note refreshes), `canChooseYourLanguage: Bool` (Settings.language == nil), `pinnedSourceNote: String?`, `voiceNote(for:)` reworded. The You-speak pill is disabled while a source language is pinned, with the pinned-source note as its hint and as a panel line.

**The strip becomes hostable by the tutorial** (§6): a protocol in `ReVoxMobile/Screens/Live/LiveControlsModel.swift`,

```swift
@MainActor protocol LiveControlsModel: AnyObject, Observable {
    var state: LiveState { get }
    var captureMode: CaptureMode { get set }
    var latencyMode: SegmenterPreset { get set }
    var ducking: Bool { get set }
    var voiceVolume: Double { get set }
    var isTwoWay: Bool { get set }
    var isLearning: Bool { get set }
    var ignoredLanguage: String? { get set }
    var theySpeak: String { get set }
    var twoWayVoiceNote: String? { get }
    var canChooseYourLanguage: Bool { get }
    var pinnedSourceNote: String? { get }
}
extension LiveViewModel: LiveControlsModel {}
```

`LiveControlStrip(model: any LiveControlsModel, showsVolumeSlider:isMoreExpanded:)` and `LiveDetailsPanel(model: any LiveControlsModel)` keep their initialiser labels; the three groups (`LiveListenGroup`, `LiveVoiceGroup`, `LiveLanguagesGroup`), `LiveLockedLine`, `LiveVolumeRow`, `LiveControlGroup` and `LiveGroupCaption` are internal views over `any LiveControlsModel` with `Binding(get:set:)` closures. `LiveControlPill.systemImage` becomes `String?` (the pair pills have no leading symbol; the memberwise init still accepts literals).

**Tests:** `PillFlowLayoutTests` re-written per group with CI-measured widths (estimates: caption 72, Mic 66, Balanced 108, ⓘ 44, Duck on 102, 100% 92, Two-way off 132, Learn off 106, You speak English ~150, They speak Spanish ~161); `LiveControlsTests` (theySpeak stores nil for English, canChooseYourLanguage, pinnedSourceNote, every new string), `TwoWayLiveTests` (summaries), `SettingsViewModelTests` (new copy), `ScreenHostingTests` (strip with you unset, pinned source, no voice, locked; each pass resets `settings.language`).

## 2. Tappable words in Learning mode (the popover)

With Learning on, the original (as-spoken) line of a row becomes `OriginalWordsLine`: word chips laid out by a flow layout (`WordFlowLayout`, a copy of `PillFlowLayout`'s packing with spacing 0 and a first-text-baseline guide, in `Screens/Learning/` so lane ownership stays clean), each chip a Button of at least 44 pt height (no minimum width: chips tile the line and every touch lands on a word), the selected word drawn with a rounded accent-tinted highlight and `Color.primary` (constant font weight, nothing shifts under the finger), and one popover per row.

**Where words are tappable** (`LiveTranscriptRowView.tapsWords(language:original:english:)`, pure): the original is non-empty and differs from the English, the language is not "en", and it is not right-to-left (ar, fa, he, ur, ps, sd, ug, yi: plain text for now). Learning off, English rows, guess rows with no original: the row renders exactly as today.

**Word splitting** (`WordSplitter.words(in:language:) -> [OriginalWord]`, `OriginalWord { id: Int, text: String, range: Range<String.Index> }`): `NLTokenizer(unit: .word)` with the language mapped to `NLLanguage` (zh → simplifiedChinese, yue → traditionalChinese, jw → jv, others pass through), punctuation and whitespace dropped, memoised per (language, sentence) on the main actor with a `resetCache()` test seam.

**The popover** (`WordPopoverView`, `.presentationCompactAdaptation(.popover)` at regular type sizes and `.sheet` with medium/large detents at accessibility sizes; `.frame(idealWidth: 300, maxWidth: 360)`):
- Header: the word, its language name, a 44 pt Close button.
- **Pronunciation:** the Latin form from `Romanizer.romanize(word)` (ReVoxCore, already per-word capable; "ohayou" style), and a **Say "word"** button. `WordSpeaker` (`Speech/WordSpeaker.swift`) uses its own `AVSpeechSynthesizer` with `usesApplicationAudioSession = false` (it mixes with other audio and needs no session configuration), picks the voice with `SystemSpeaker.selectVoice(identifier: nil, language:)`, and reports `isSpeaking`. While a microphone session is running the Say button is disabled with the note "Stop listening to hear words through the microphone" (a spoken word would be heard and translated); during an Other-apps session it is allowed. No voice for the language: the button is replaced by "This iPhone has no Spanish voice. Add one in Settings › Accessibility › Spoken Content › Voices."
- **Meaning:** on iOS 18, the single word translated to English by Apple's on-device translator through a self-contained `translationTask` attached to the popover content (`Translation/WordTranslation.swift`, the second and last file importing the framework, mirroring `TwoWayTranslation`); `WordTranslatorProbe.availability(language:)` returns `.unavailableOnThisiOS` on iOS 17 without touching the framework, `.needsDownload` / `.unsupported` / `.ready` on 18 (never triggers a download). While pending: a progress row; found: the text; absent: "No meaning found for this word." On iOS 17: "Meanings for single words need iOS 18. The whole sentence is translated below." Beneath, when `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)` is true, a **Look up in the dictionary** button opening `DictionaryView` (a `UIViewControllerRepresentable` sheet, presented after the popover has dismissed); `hasDefinition: Bool?` shows neither button nor note until known; false: "This word is not in this iPhone's dictionaries. You can add a Spanish one in Settings › General › Dictionary."
- **In this sentence:** the original with the word highlighted, and the sentence's English.

`WordPopoverContent.make(...)` is a pure value holding every string and decision; `WordPopoverModel` (`@MainActor @Observable`) resolves latin, voice, translator availability and dictionary availability (`hasVoice` from a voices list computed once per lookup) and receives the meaning. Services reach the row through one environment value `\.wordLookup` (`WordLookup { speaker, hasVoice, hasDefinition, translatorAvailability }`, default `.unavailable`, so every hosted test row is honest and inert); `AppEnvironment.wordLookup` is the production one and RootView applies `.environment(\.wordLookup, …)` outermost, after `.fullScreenCover`, so the tutorial inherits it.

**Accessibility:** the row stays one combined element that reads the sentence as today; the words line is `.accessibilityElement(children: .ignore)` and the row carries custom actions "Look up ‹word›" for the first twelve words. Selecting a word while another popover is open sets `lookup` to nil first and stages the new model on the next run-loop turn. `MeaningResult` cases are `.pending`, `.text(String)`, `.absent`.

**Copy:** `SettingExamples.learning(true)`: "The words as spoken appear above the translation. Tap a word to hear it and see what it means." `SettingsViewModel.learningHelpText` gains "Tap any word for its pronunciation and meaning." The tutorial's Learning page (§6) says the same.

**Tests:** `WordSplitterTests` (punctuation dropped, ranges index the sentence, CJK yields words, cache delta), `WordPopoverTests` (content for every availability combination and iOS path, model state machine with injected closures), `WordSpeakerTests` (utterance per language, no voice → nil, English → nil, disabled during a microphone run), hosting of the popover view at default and accessibility sizes, `RowAccessibilityTests` (custom actions count, combined label unchanged).

## 3. Unsure phrases ("guesses")

**Core.** `SpeechGate.classify(_ candidate: TranslationCandidate) -> GateOutcome` with

```swift
public enum LanguageOutcome: Sendable, Equatable { case confident, unsure, dropped }
public enum GateOutcome: Sendable, Equatable { case confident(Translation), guess(Translation), dropped }
public static let guessLogProbFloor: Float = -2.5   // asserted by name and value in SpeechGateTests
```

A segment with no-speech above 0.85, empty stripped text, or an average log-probability that is not finite is skipped; below `guessLogProbFloor` it is skipped too (noise, not a guess); between the floor and −1.2 it is an unsure part; at or above −1.2 a confident part. Confident parts win when any exist (byte-identical to today's output); otherwise the unsure parts form a guess. The hallucination set drops either. An auto-detected language below 0.4 (finite) makes the phrase a guess whatever its parts; NaN drops it. `evaluate(_:)` is re-implemented as `if case .confident(let t) = classify(candidate) { return t }; return nil` and `languagePasses(probability:)` as `languageOutcome(probability:) == .confident`, so the two can never disagree; the existing tests stay. `classify` sets `isGuess` from the case in one place.

`Translation.isGuess: Bool = false` and `TranscriptEntry.isGuess: Bool = false`, both decoded with `decodeIfPresent` (old JSON decodes) and encoded always. `TranslationStage.route`: an unsure detection while a language is ignored (`ignoredLanguage != nil`) returns nil in both two-way modes (the phrase may be the user's own language; the M8 guarantee holds); otherwise an unsure-language phrase is decoded and returned as `RoutedTranslation(route: .toEnglish, isSpoken: false)` with `isGuess`; the second direction never produces a guess. `PipelineConfiguration.keepsGuesses: Bool = true`; `PipelineActor.record` always yields `.entry(entry)` (Live shows it), writes it to the transcript sink only when `keepsGuesses || !entry.isGuess`, and never speaks a guess. `recordTranslation` (dead) is deleted. `TranscriptFormatter.guessPrefix = "(unsure) "` on the English line of a guess. `Settings.keepGuesses: Bool = true`, key `keep_guesses`. The deviation table in `docs/superpowers/specs/2026-09-02-revox-mobile-design.md` §2 gains row **W8**: "Unsure-language and low-log-probability phrases are kept as unspoken, greyed guesses instead of being dropped; Windows drops them" (W2 is retired for `.unsure`).

**App.** `Entry.isGuess: Bool = false` (SwiftData lightweight migration; `TranscriptMigrationTests` proves it with a pre-M11 `VersionedSchema` on an on-disk container at a temporary URL). `TranscriptStore.add` / `items(from:)`, `HistoryActions.merge`, `SessionDetailRows.row(for:)` carry the flag; `TranscriptSearch` predicates exclude guesses; `SessionSummary.guessCount`, `guessCountText` ("1 unsure phrase" / "3 unsure phrases"), `previewIsGuess`; `SessionDetailView` shows an **Unsure** header row after Skipped; `SessionRowView` renders a guess preview in secondary italic with `questionmark.circle` and prefixes its spoken sentence with "Unsure: ". `LiveViewModel.configuration(settings:captureMode:)` copies `keepsGuesses` from `Settings.keepGuesses`; `handle(.entry)` appends `LiveTranscriptRow(…, isGuess: entry.isGuess)` and leaves `detectedLanguage` alone for a guess. Live may show two drop markers around a discarded guess while History shows one (accepted).

**Row styling** (`LiveTranscriptRowView`): a guess has a visible caption line **Unsure** with `questionmark.circle` as the first line of the text column, secondary colour and italic English; VoiceOver reads "Unsure translation" in the combined element between the language and the English; the original line, when present, still gets the tappable words of §2 (the greying is applied outside `OriginalWordsLine`).

**Settings** (section **Unsure phrases**, directly under Source language): Toggle **Keep unsure phrases in History** (hint "Keeps phrases ReVox was unsure about in History as well as on the Live screen"), example on: "An unsure phrase stays in the session, greyed and marked Unsure, so you can read what ReVox thought it heard.", off: "An unsure phrase is shown on the Live screen only. History keeps the phrases ReVox was sure of.", footer: "When ReVox is not sure of the language or the words, the phrase is shown greyed and marked Unsure on the Live screen and is never spoken aloud. With this on, those phrases are also kept in History and in the exported file, marked (unsure). A change takes effect the next time you tap Start."

**Tests:** core `SpeechGateTests` (classify table, floor, NaN, hallucination on a guess, evaluate ≡ classify), `TranslationStageTests` (unsure decoded and kept as an unspoken guess; unsure dropped while a language is ignored; pinned language never a guess), `TranslationPipelineTests` (`FakeTranslator(segmentsPerCall:)`; keepsGuesses off → event but no sink; a guess never reaches the speaker), `TranscriptFormatterTests` (golden export with a guess between the 22:13:21 and 22:13:22 markers), `SettingsTests` (`keep_guesses` round-trip, default, inequality), `PipelineConfiguration` equality; app `TranscriptStoreTests`, `HistoryActionsTests` (merge keeps the flag), `SessionSummaryTests`, `TranscriptMigrationTests`, `LiveViewModelTests` (guess row, detectedLanguage untouched), hosting of a guess row and of the Settings section.

## 4. History: the Merge / Delete bar

The `ToolbarItemGroup(placement: .bottomBar)` inside `NavigationStack` inside `TabView` is drawn under the tab bar on the owner's device. Replace it with a `safeAreaInset(edge: .bottom)` bar on the List, shown only while editing and not searching: an `HStack` with the Merge and Delete buttons (44 pt, `.bordered`/`.borderedProminent`-free plain buttons with the same titles, hints and disabled rules as today), `.padding`, a `.bar` material background, and a top hairline. The tab bar contributes to the safe area, so the inset sits above it on iOS 17 and on the floating tab bars of newer releases. The screenshot test's `history-selecting` capture keeps its name; `HistoryActionsTests` keep the titles.

## 5. On-device benchmark and measurement-driven recommendations

**Core** (Linux-tested): `WordErrorRate` (`words`, `editDistance`, `rate(reference:hypothesis:)`, `accuracy`), `ModelBenchmark.swift` with `BenchmarkSentence { language, text, reference }`, `BenchmarkSentences` (Spanish "Buenos días, ¿dónde está la estación de tren?" → "Good morning, where is the train station?", French and German equivalents, an English fallback), `ModelBenchmarkResult { model: WhisperModelID, loadSeconds, firstSeconds, steadySeconds, audioSeconds, realTimeFactor, wordErrorRate, residentBeforeMB, peakDeltaMB, thermalState, skippedReason? }`, `BenchmarkRun { date, device, iOSVersion, memoryTierGB, whisperKitVersion, sentence, results }` (Codable), `BenchmarkVerdict` wording ("4.2× faster than real time · loads in 3 s · 88 % of words right · uses 240 MB"; "Keeps up" / "Too slow for live use" / "Slow to load"), `BenchmarkReport.markdown(run)` (the text the share sheet exports, one row per model, the shape of the docs table), and the rule `DeviceRecommendation.measured(memory:results:)`: among results for installed models inside the memory tier's suitable set, the lowest word error rate with `realTimeFactor < 0.5` and `loadSeconds < 10` (`maxRealTimeFactor`, `maxLoadSeconds` constants); none qualifies → the static tier.

**App** (`ReVoxMobile/Benchmark/`): `BenchmarkRunner` (actor; refuses while a session runs or a download is active; releases the cached Live pipeline; synthesises the sentence with the iPhone's voice through `SpeechWriteCollector`, converts to 16 kHz mono Float32 with the existing converter; for each installed and verified model, strictly one at a time with unload between: thermal check (skips at serious/critical), `ContinuousClock` around load, first translate and a second steady translate, `MemoryMeter` before/after, `SpeechGate.evaluate` on the output, WER against the reference, one `benchmark model=… load_ms=… first_ms=… steady_ms=… audio_ms=… rtf=… wer=… resident_before_mb=… peak_delta_mb=… thermal=…` log line under the `measurements` category), `BenchmarkStore` (JSON files under Application Support/ReVox/Benchmarks, newest run readable), `BenchmarkViewModel` + `BenchmarkView` (Settings › Models › **Benchmark this iPhone**: a Run button with progress per model, a results table with the verdicts, **Share results** as the markdown text, the date and device of the last run), `ModelsViewModel` reads the latest run and computes `recommendation = DeviceRecommendation.measured(...)` with the row note "Measured on this iPhone on ‹date›" (else the static tier as today). The translator seam is a protocol so simulator tests run the runner with a fake translator and a fake synthesiser.

**Docs:** `docs/measurements/m11-model-benchmark.md` with the published, cited reference numbers as expectations (the research rows: Argmax's WhisperKit benchmarks, with URLs) and an empty table the owner fills by pasting the app's shared text; the README's model table states expectations from that file.

**Tests:** core `WordErrorRateTests`, `ModelBenchmarkTests` (verdict wording, report shape, Codable), `DeviceRecommendationTests` (measured rule); app `BenchmarkRunnerTests` (fakes; skips at heat; refuses while running; one model at a time), `BenchmarkStoreTests`, `ModelsViewModelTests` (measured recommendation and note), hosting of `BenchmarkView`.

## 6. Tutorial refresh

The tutorial stops imitating the Live screen and hosts it: a small `@Observable` demo class `OnboardingLiveControls: LiveControlsModel` owned by `OnboardingViewModel` drives the real `LiveControlStrip`, `LiveDetailsPanel` and `LiveLanguagesGroup`. Pages stay seven: **Welcome**; **The Live controls** (replaces "Choose a source": the whole strip, a Start capsule that locks it, the ⓘ that unfolds the real panel); **Start and read** (real `LiveTranscriptRowView` rows; the script gains a greyed unsure line with a caption explaining it); **Two-way conversation** (the real Languages group, tap Two-way and the You speak / They speak pair appears; subtitle: "In a conversation ReVox should not echo your own language back at you; it should say what you say to the other person in theirs. Tell it what you speak and what they speak, then turn on Two-way to see both directions."; footnote on: "What you say in English is spoken to them in Spanish, and what they say is spoken to you in English. Both sides stay in the transcript."); **Learning mode** (the real group with Learn on, the Romanize toggle, rows with tappable words through the real row view; subtitle mentions tapping a word); **Models and voices** (unchanged cards, plus one line: "Settings › Models › Benchmark this iPhone measures them on your iPhone."); **You're ready**. Copy is built from the strip's and `LiveView`'s statics where it names controls (a test asserts it). `OnboardingViewModel.version = 2`. `docs/onboarding.md` describes each page. `OnboardingScreenshotTests` renders welcome, the Live controls page, transcript and Learning pages.

## 7. Lanes, ownership and waves

Wave 1 (parallel worktrees, no shared files):

| Lane | Owns | Produces for others |
|---|---|---|
| **L1 Live and naming** | `Screens/Live/*` (+ new `LiveControlsModel.swift`), `LiveView.swift`, `LiveViewModel.swift` (two-way region, protocol conformance), `SettingsView.swift`, `SettingsViewModel.swift`, `SettingExample.swift` (skip-language and source-language copy), tests `LiveControlsTests`, `TwoWayLiveTests`, `PillFlowLayoutTests`, `SettingsViewModelTests`, `ScreenHostingTests` | `LiveControlsModel`, `LiveLanguagesGroup(model:)`, `theySpeak`, the strings above |
| **L2 Unsure phrases and History bar** | ReVoxCore `SpeechGate`, `TranslationStage`, `PipelineTypes`, `TranslationPipeline`, `TranscriptFormatter`, `Settings`, core tests and fakes; app `Storage/*`, `SessionSummary`, `SessionDetailRows`, `SessionDetailView`, `SessionRowView`, `HistoryView`, new `SettingsViewModel+Guesses.swift`, `GuessesSettingsSection.swift`, `SettingExample+Guesses.swift`, the two small `LiveViewModel` hunks (`configuration`, `handle(.entry)`), tests listed in §3 and §4 plus new `GuessHostingTests` | `Translation.isGuess`, `TranscriptEntry.isGuess`, `Settings.keepGuesses`, `GuessesSettingsSection` |
| **L3 Benchmark** | ReVoxCore `WordErrorRate.swift`, `ModelBenchmark.swift`, `DeviceRecommendation.swift`; app `Benchmark/*`, `ModelsView.swift`, `ModelsViewModel.swift`, `ModelRow.swift`, `ModelRowView.swift`, `AppEnvironment.swift` (benchmark wiring only), `docs/measurements/m11-model-benchmark.md`, tests in §5 | nothing others need in this milestone |
| **L4 Word lookup** | `Screens/Learning/*` (new: `WordSplitter`, `WordFlowLayout`, `OriginalWordsLine`, `WordPopoverContent`, `WordPopoverModel`, `WordPopoverView`, `WordLookup`, `DictionaryView`), `Speech/WordSpeaker.swift`, `Translation/WordTranslation.swift`, `docs/hig-audit/checks.json`, tests in §2 | `OriginalWordsLine`, `WordLookup`, `\.wordLookup`, `WordPopoverModel` |

Wave 2 (after wave 1 is merged):

| Lane | Owns |
|---|---|
| **L5 Wiring** | `LiveTranscriptRowView.swift` (tappable words + guess styling), `RowAccessibilityTests`, `SettingsView.swift` insertions of `GuessesSettingsSection` and the Learning copy, `RootView.swift` (`.environment(\.wordLookup)`), `AppEnvironment.swift` (`wordSpeaker`, `wordLookup`), `SessionRowView` if L2 left it, `ScreenshotTests` if a capture changes |
| **L6 Tutorial** | `Screens/Onboarding/*`, `docs/onboarding.md`, `OnboardingTests`, `OnboardingHostingTests`, `OnboardingScreenshotTests` |
| **L7 Docs** | `README.md`, `docs/adr/0006`, `docs/adr/0007`, `.github/ISSUE_TEMPLATE/bug_report.md`, the spec deviation table if L2 left it, `CHANGELOG` if one exists |

Then: review workflow over the whole diff, CI green, screenshots refreshed from the artifact, PR, merge.

## 8. Acceptance

- CI green: core on Linux and simulator, the app suite, every gate.
- Screenshots show the three captioned rows, the pair line with You speak / They speak, the lock line while running, a greyed Unsure row, tappable word chips on a Learning row, the History edit bar above the tab bar (a capture inside a `TabView`), the Benchmark screen, and the four tutorial pages.
- Owner-side: run **Benchmark this iPhone** on the device and paste the shared text into `docs/measurements/m11-model-benchmark.md`; verify on device that the Merge/Delete bar sits above the tab bar, that a word popover opens and says the word, and that a pre-M11 History migrates.
