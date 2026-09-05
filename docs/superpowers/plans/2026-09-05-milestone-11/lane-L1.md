## Lane L1: Live groups and You speak / They speak

Spec §1 and §7 row L1. Everything here is app-target code: CI (Xcode 26, simulator) is the compiler; locally every step ends with `/home/user/swift/usr/bin/swiftc -parse <files>`. `project.yml` globs `ReVoxMobile/` and `ReVoxMobileTests/`, so new files need no registration.

**Files**

Create:
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveControlsModel.swift` — the protocol and `extension LiveViewModel: LiveControlsModel {}`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveControlGroup.swift` — `LiveGroupCaption`, `LiveControlGroup`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveListenGroup.swift` — `LiveListenGroup`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveVoiceGroup.swift` — `LiveVoiceGroup`, `LiveVolumeRow`
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveLanguagesGroup.swift` — `LiveLanguagesGroup`

Modify:
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/LiveViewModel.swift` (two-way region L184–219 only)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/LiveView.swift` (copy block L288–349)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveControlStrip.swift` (strip body, `LiveLockedLine`, constants, `LiveDetailsPanel`)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/Live/LiveControlPill.swift` (`systemImage: String?`)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsViewModel.swift` (L111–130)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingExample.swift` (L59–81)
- `/home/user/ReVoxMobile/ReVoxMobile/Screens/SettingsView.swift` (L50, L53–69)

Test files:
- `/home/user/ReVoxMobile/ReVoxMobileTests/LiveControlsTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/TwoWayLiveTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/SettingsViewModelTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/PillFlowLayoutTests.swift`
- `/home/user/ReVoxMobile/ReVoxMobileTests/ScreenHostingTests.swift`

**Interfaces**

Consumes (all already on the branch):
- `SettingsStore.update(_ change: (inout Settings) -> Void)`; `SettingsStore.settings: Settings` with `language: String?`, `ignoredLanguage: String?`, `twoWay: Bool`, `twoWayLanguage: String?`, `ignored: String?`, `twoWayTarget: String?` (ReVoxCore)
- `SettingsViewModel.store: SettingsStore` (internal since the seam commit)
- `LanguageCatalog.concrete: [LanguageOption]`, `LanguageCatalog.displayName(_ code: String?, whenNil: String) -> String`
- `SystemSpeaker.hasVoice(for language: String) -> Bool`
- `PillFlowLayout.rows(sizes: [CGSize], available: CGFloat, spacing: CGFloat) -> [PillFlowLayout.Row]` (unchanged)
- `LiveState`, `CaptureMode`, `SegmenterPreset`, `LiveView.availableSources / title(for:) / symbol(for:) / description(for:)`, `SettingsView.title(for: SegmenterPreset)`, `SettingsViewModel.presetDescription(_:)`

Produces (other lanes rely on these):
- `@MainActor protocol LiveControlsModel: AnyObject, Observable { var state: LiveState { get }; var captureMode: CaptureMode { get set }; var latencyMode: SegmenterPreset { get set }; var ducking: Bool { get set }; var voiceVolume: Double { get set }; var isTwoWay: Bool { get set }; var isLearning: Bool { get set }; var ignoredLanguage: String? { get set }; var theySpeak: String { get set }; var twoWayVoiceNote: String? { get }; var canChooseYourLanguage: Bool { get }; var pinnedSourceNote: String? { get } }` and `extension LiveViewModel: LiveControlsModel {}`
- `LiveViewModel.theySpeak: String`, `LiveViewModel.canChooseYourLanguage: Bool`, `LiveViewModel.pinnedSourceNote: String?`, `static func pinnedSourceNote(pinned: String, you: String?) -> String`, reworded `static func voiceNote(for target: String?) -> String?`
- `LiveControlStrip(model: any LiveControlsModel, showsVolumeSlider: Binding<Bool>, isMoreExpanded: Binding<Bool>)`, `LiveDetailsPanel(model: any LiveControlsModel)`, `LiveLanguagesGroup(model: any LiveControlsModel)`, `LiveListenGroup(model:isMoreExpanded:)`, `LiveVoiceGroup(model:showsVolumeSlider:)`, `LiveVolumeRow(model:)`, `LiveLockedLine()`, `LiveControlGroup(caption: String, pills: () -> Pills)`, `LiveGroupCaption(title: String)`
- `LiveControlPill(systemImage: String?, title: String, value: String? = nil, isOn: Bool = false)`
- `LiveControlStrip` statics: `captionColumnWidth: CGFloat = 72`, `listenCaption = "Listen"`, `voiceCaption = "Voice"`, `languagesCaption = "Languages"`, `youSpeakTitle = "You speak"`, `theySpeakTitle = "They speak"`, `chooseLanguageTitle = "Choose…"`, `youSpeakHintText`, `theySpeakHintText`, `noVoiceValueSuffix = ", no voice on this iPhone"`, `volumeHelpText`, `lockedDetailText`, `static func theySpeakAccessibilityValue(name: String, hasVoice: Bool) -> String`
- `LiveView.noLanguageTitle = "Not set"`, `LiveView.twoWayHintText`, `static func twoWaySummary(you: String?, they: String?) -> String`, `static func twoWayOffSummary(you: String?) -> String`, and a forwarding `static func twoWaySummary(ignored: String?, target: String?) -> String` kept only for `OnboardingTwoWayDemo` (L6 deletes it)
- `SettingsViewModel.noIgnoredLanguageTitle` (= `LiveView.noLanguageTitle`), `ignoredLanguageHelpText`, `ignoredLanguageNeedsAutoDetectText`, new `sourceLanguageHelpText`; `SettingExamples.skipLanguageNone`, `skipLanguage(_:)`, `skipLanguageWhilePinned(ignored:pinned:)`, `sourceLanguageAuto` with the spec copy

### Task 1: The view model speaks for the two people

- [ ] Append to `LiveControlsTests` (before the closing brace of the class):

```swift
    // MARK: M11 — You speak / They speak

    func testTheySpeakShowsEnglishUntilOneIsStored() {
        let settings = store()
        let live = liveModel(settings)
        XCTAssertEqual(live.theySpeak, "en")
        XCTAssertNil(settings.settings.twoWayLanguage, "English is the stored nil, as on Windows")
        live.ignoredLanguage = "en"
        live.isTwoWay = true
        live.theySpeak = "es"
        XCTAssertEqual(settings.settings.twoWayLanguage, "es")
        XCTAssertEqual(live.twoWayPair?.source, "en")
        XCTAssertEqual(live.twoWayPair?.target, "es")
        live.theySpeak = "en"
        XCTAssertNil(settings.settings.twoWayLanguage, "choosing English stores nil")
        XCTAssertNil(live.twoWayPair)
        live.theySpeak = "zz"
        XCTAssertNotNil(live.twoWayVoiceNote, "the setter went through twoWayLanguage, so the voice note refreshed")
        live.theySpeak = "en"
        XCTAssertNil(live.twoWayVoiceNote)
    }

    func testYourLanguageCanBeChosenOnLiveOnlyWithAutoDetect() {
        let settings = store()
        let live = liveModel(settings)
        XCTAssertTrue(live.canChooseYourLanguage)
        XCTAssertNil(live.pinnedSourceNote)
        settings.update { $0.language = "fr" }
        XCTAssertFalse(live.canChooseYourLanguage)
        XCTAssertEqual(live.pinnedSourceNote,
                       "Source language is pinned to French in Settings, so the language you speak cannot be chosen here. Set it to Auto-detect for Two-way to work.")
        live.ignoredLanguage = "en"
        XCTAssertEqual(live.pinnedSourceNote,
                       "Source language is pinned to French in Settings, so nothing is heard as English. Set it to Auto-detect for Two-way to work.")
        XCTAssertEqual(live.pinnedSourceNote, LiveViewModel.pinnedSourceNote(pinned: "French", you: "English"))
        settings.update { $0.language = nil }
        XCTAssertTrue(live.canChooseYourLanguage)
        XCTAssertNil(live.pinnedSourceNote)
    }
```

- [ ] In `TwoWayLiveTests.testAReplyLanguageWithNoVoiceIsCalledOut`, after the line `XCTAssertNil(LiveViewModel.voiceNote(for: "en"), "every iPhone speaks English")` add:

```swift
        let note = LiveViewModel.voiceNote(for: "zz")
        XCTAssertEqual(note, "This iPhone has no zz voice, so what you say to them stays in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices.")
```

- [ ] Run: CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/LiveControlsTests.swift ReVoxMobileTests/TwoWayLiveTests.swift` (parses; on CI these fail until the members exist).
- [ ] Implement in `LiveViewModel.swift`. Replace L186 `/// The language ReVox leaves alone. nil = every language is translated, the pre-M8 behaviour.` with `/// The language you speak (Settings › Your language, the Live "You speak" pill): neither translated nor transcribed on` / `/// its own; with Two-way on, spoken to the other person in theirs. nil = everything is translated, the pre-M8 behaviour.` Replace L192 `/// Whether that language is spoken back in `twoWayLanguage` instead of being dropped.` with `/// Two-way conversation: what you say is spoken to the other person in `theySpeak` instead of being dropped.` Insert directly after the `twoWayLanguage` property (after its closing `}` at L204):

```swift
    /// The "They speak" pill's value: the stored code, or "en" while nothing is stored (that is what runs). Stores
    /// nil for English through `twoWayLanguage`, so the JSON stays as it was and the voice note refreshes.
    var theySpeak: String {
        get {
            let code = settings.settings.twoWayLanguage ?? ""
            return code.isEmpty ? "en" : code
        }
        set { twoWayLanguage = newValue == "en" ? nil : newValue }
    }

    /// The You-speak pill is live only while Source language is Auto-detect: a pinned language is never detected.
    var canChooseYourLanguage: Bool { settings.settings.language == nil }

    /// Why the You-speak pill is disabled — its hint and a details-panel line; nil while nothing is pinned.
    var pinnedSourceNote: String? {
        guard let pinned = settings.settings.language else { return nil }
        return Self.pinnedSourceNote(pinned: LanguageCatalog.displayName(pinned, whenNil: ""),
                                     you: ignoredLanguage.map { LanguageCatalog.displayName($0, whenNil: LiveView.noLanguageTitle) })
    }

    static func pinnedSourceNote(pinned: String, you: String?) -> String {
        if let you {
            return "Source language is pinned to \(pinned) in Settings, so nothing is heard as \(you). Set it to Auto-detect for Two-way to work."
        }
        return "Source language is pinned to \(pinned) in Settings, so the language you speak cannot be chosen here. Set it to Auto-detect for Two-way to work."
    }
```

  Replace the body of `voiceNote(for:)` (L215–219):

```swift
    static func voiceNote(for target: String?) -> String? {
        guard let target, !target.isEmpty, !SystemSpeaker.hasVoice(for: target) else { return nil }
        let name = LanguageCatalog.displayName(target, whenNil: LiveView.noLanguageTitle)
        return "This iPhone has no \(name) voice, so what you say to them stays in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices."
    }
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/LiveViewModel.swift ReVoxMobileTests/LiveControlsTests.swift ReVoxMobileTests/TwoWayLiveTests.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/LiveViewModel.swift ReVoxMobileTests/LiveControlsTests.swift ReVoxMobileTests/TwoWayLiveTests.swift && git commit -m "feat(live): the view model names the two people — theySpeak, canChooseYourLanguage, pinnedSourceNote

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 2: The Live copy — Not set, the hint, both directions by the people

- [ ] In `TwoWayLiveTests` replace the whole `testTheToggleSubtitleNamesWhatTwoWayWillDo` (L90–94) with:

```swift
    func testThePanelLineNamesBothDirectionsByThePeople() {
        XCTAssertEqual(LiveView.twoWaySummary(you: nil, they: nil), "Choose the language you speak.")
        let same = "You and they both speak English, so there is nothing to translate. Choose the language they speak."
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: nil), same, "nil is English, which is what runs")
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: ""), same)
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: "en"), same)
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: "es"),
                       "What you say in English is spoken to them in Spanish; what they say is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWaySummary(you: "es", they: nil),
                       "What you say in Spanish is spoken to them in English; what they say is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWayOffSummary(you: nil),
                       "Two-way is off: everything ReVox hears is spoken to you in English, including what you say.")
        XCTAssertEqual(LiveView.twoWayOffSummary(you: "en"),
                       "Two-way is off: English is not translated and not spoken back at you; everything else is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWaySummary(ignored: "en", target: "es"), LiveView.twoWaySummary(you: "en", they: "es"),
                       "the tutorial's call site forwards until lane L6 hosts the real group")
        XCTAssertEqual(LiveView.twoWayHintText, "Speaks what you say to the other person in their language")
        XCTAssertEqual(LiveView.noLanguageTitle, "Not set")
        for text in [LiveView.twoWaySummary(you: nil, they: nil), same, LiveView.twoWaySummary(you: "en", they: "es"),
                     LiveView.twoWayOffSummary(you: nil), LiveView.twoWayOffSummary(you: "en"), LiveView.twoWayHintText] {
            XCTAssertFalse(text.contains("left alone"), text)
            XCTAssertFalse(text.contains("Reply in"), text)
        }
    }
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/TwoWayLiveTests.swift`
- [ ] Implement in `LiveView.swift`. Replace L291 `static let noLanguageTitle = "None"` with `static let noLanguageTitle = "Not set"`; replace L293 `static let twoWayHintText = "Speaks the language ReVox is not translating back in another language"` with `static let twoWayHintText = "Speaks what you say to the other person in their language"`. Replace L340–347 (the doc comment and `twoWaySummary(ignored:target:)`) with:

```swift
    /// The details panel's Languages line while Two-way is on: both directions in the names of the two people, or
    /// what is still missing. `they` nil or "" is English — what actually runs (`Settings.twoWayLanguage`).
    static func twoWaySummary(you: String?, they: String?) -> String {
        guard let you else { return "Choose the language you speak." }
        let youName = LanguageCatalog.displayName(you, whenNil: noLanguageTitle)
        let theyCode = they.flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        guard theyCode != you else {
            return "You and they both speak \(youName), so there is nothing to translate. Choose the language they speak."
        }
        let theyName = LanguageCatalog.displayName(theyCode, whenNil: noLanguageTitle)
        return "What you say in \(youName) is spoken to them in \(theyName); what they say is spoken to you in English."
    }

    /// The same line while Two-way is off: the one place Settings › Your language shows on Live in that state.
    static func twoWayOffSummary(you: String?) -> String {
        guard let you else { return "Two-way is off: everything ReVox hears is spoken to you in English, including what you say." }
        let youName = LanguageCatalog.displayName(you, whenNil: noLanguageTitle)
        return "Two-way is off: \(youName) is not translated and not spoken back at you; everything else is spoken to you in English."
    }

    /// Kept for `OnboardingTwoWayDemo` only: wave 2 (lane L6) hosts `LiveLanguagesGroup` there and deletes this.
    static func twoWaySummary(ignored: String?, target: String?) -> String {
        twoWaySummary(you: ignored, they: target)
    }
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/LiveView.swift ReVoxMobileTests/TwoWayLiveTests.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/LiveView.swift ReVoxMobileTests/TwoWayLiveTests.swift && git commit -m "feat(live): Not set, and the panel line says what you say and what they say

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 3: Settings › Your language and the source-language footer

- [ ] Append to `SettingsViewModelTests` (before the class's closing brace):

```swift
    // MARK: M11 — Your language, You speak

    func testTheYourLanguageCopyNamesThePeopleNotTheMechanism() {
        XCTAssertEqual(SettingsViewModel.noIgnoredLanguageTitle, "Not set")
        XCTAssertEqual(SettingsViewModel.noIgnoredLanguageTitle, LiveView.noLanguageTitle, "one word on both screens")
        XCTAssertEqual(SettingsViewModel.ignoredLanguageHelpText,
                       "ReVox translates everything it hears into English except the language you speak, which it neither translates nor transcribes. With Two-way on (Live tab), what you say is spoken to the other person in their language instead.")
        XCTAssertEqual(SettingsViewModel.ignoredLanguageNeedsAutoDetectText,
                       "This needs Source language set to Auto-detect, because a pinned language is never detected.")
        XCTAssertEqual(SettingExamples.skipLanguageNone,
                       "Everything is translated into English, including you. Choose the language you speak so a conversation is not echoed back at you.")
        XCTAssertEqual(SettingExamples.skipLanguage("English"),
                       "“Where is the station?” said in English is not translated and not transcribed. Turn on Two-way on the Live tab to have it spoken to the other person in their language instead.")
        XCTAssertEqual(SettingExamples.skipLanguageWhilePinned(ignored: "English", pinned: "English"),
                       "Source language is pinned to English and English is the language you speak, so every phrase counts as yours and nothing is translated. Change one of the two.")
        XCTAssertEqual(SettingExamples.skipLanguageWhilePinned(ignored: "English", pinned: "French"),
                       "Source language is pinned to French, so nothing is ever heard as English and everything is translated, including you. Set Source language to Auto-detect for You speak to work.")
        let model = SettingsViewModel(store: makeStore(), mute: PlaybackMute())
        XCTAssertEqual(model.ignoredLanguageOptions.first?.displayName, "Not set")
        for text in [SettingsViewModel.ignoredLanguageHelpText, SettingsViewModel.ignoredLanguageNeedsAutoDetectText,
                     SettingExamples.skipLanguageText(ignored: nil, pinned: nil), SettingExamples.skipLanguageText(ignored: "English", pinned: nil),
                     SettingExamples.skipLanguageText(ignored: "English", pinned: "English"), SettingExamples.skipLanguageText(ignored: "English", pinned: "French")] {
            for retired in ["left alone", "Leave alone", "Reply in", "Don't translate", "Skip a language", "ignored", "skipped"] {
                XCTAssertFalse(text.contains(retired), "\(retired) in: \(text)")
            }
        }
    }

    func testTheSourceLanguageCopyKeepsUnsurePhrasesInsteadOfDroppingThem() {
        XCTAssertEqual(SettingsViewModel.sourceLanguageHelpText,
                       "Auto-detect runs Whisper's language detection on every phrase. A phrase it is unsure about is shown greyed and marked Unsure, and is never spoken.")
        XCTAssertEqual(SettingExamples.sourceLanguageAuto,
                       "Auto-detect hears “¿Dónde está la estación?” as Spanish and translates it. A phrase it cannot place is shown greyed and marked Unsure, and is not spoken.")
        XCTAssertFalse(SettingExamples.sourceLanguageAuto.contains("dropped"))
    }

    func testLiveAndSettingsWriteTheSameYourLanguage() {
        let store = makeStore()
        let settings = SettingsViewModel(store: store, mute: PlaybackMute())
        let live = LiveViewModel(settings: store, mute: PlaybackMute(), permission: .fixed(.granted),
                                 modelReady: { _ in true }, supplier: { _, _ in FakeLivePipeline() })
        live.ignoredLanguage = "en"
        XCTAssertEqual(settings.ignoredLanguage, "en", "the Live pill and the Settings row are one setting")
        settings.ignoredLanguage = "es"
        XCTAssertEqual(live.ignoredLanguage, "es")
        settings.ignoredLanguage = nil
        XCTAssertNil(live.ignoredLanguage)
        XCTAssertNil(store.settings.ignoredLanguage, "Not set stores nil, the key the Windows app reads")
    }
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/SettingsViewModelTests.swift`
- [ ] Implement in `SettingsViewModel.swift`. Replace L111 `/// §8.2 (M8): the language ReVox leaves alone. "None" is the pre-M8 behaviour — everything is translated.` with `/// §8.2 (M8), M11 "You speak": the language you speak, which ReVox neither translates nor transcribes. Not set` / `/// (nil) is the pre-M8 behaviour — everything is translated, including you.` Replace L117 `/// The concrete languages the ignore picker offers, with "None" as the first row.` with `/// The concrete languages the You-speak picker offers, with "Not set" as the first row.` Replace L128–130 with:

```swift
    static let noIgnoredLanguageTitle = LiveView.noLanguageTitle
    static let ignoredLanguageHelpText = "ReVox translates everything it hears into English except the language you speak, which it neither translates nor transcribes. With Two-way on (Live tab), what you say is spoken to the other person in their language instead."
    static let ignoredLanguageNeedsAutoDetectText = "This needs Source language set to Auto-detect, because a pinned language is never detected."
    /// M11 (§3): an unsure phrase is kept greyed rather than dropped; the footer under Source language says so.
    static let sourceLanguageHelpText = "Auto-detect runs Whisper's language detection on every phrase. A phrase it is unsure about is shown greyed and marked Unsure, and is never spoken."
```

- [ ] Implement in `SettingExample.swift`. Replace L59 with `static let sourceLanguageAuto = "Auto-detect hears “\(spanishOriginal)” as Spanish and translates it. A phrase it cannot place is shown greyed and marked Unsure, and is not spoken."`. Replace L64–76 (from `static let skipLanguageNone` through the doc comment `/// The one the screen shows: ...`) with:

```swift
    static let skipLanguageNone = "Everything is translated into English, including you. Choose the language you speak so a conversation is not echoed back at you."
    static func skipLanguage(_ name: String) -> String {
        "“\(spanishEnglish)” said in \(name) is not translated and not transcribed. Turn on Two-way on the Live tab to have it spoken to the other person in their language instead."
    }
    /// M10/M11: a pinned source language is never detected, so You speak only ever matches when it names the pinned
    /// language itself — and then it matches every phrase.
    static func skipLanguageWhilePinned(ignored: String, pinned: String) -> String {
        if ignored == pinned {
            return "Source language is pinned to \(pinned) and \(ignored) is the language you speak, so every phrase counts as yours and nothing is translated. Change one of the two."
        }
        return "Source language is pinned to \(pinned), so nothing is ever heard as \(ignored) and everything is translated, including you. Set Source language to Auto-detect for You speak to work."
    }
    /// The one the screen shows: `ignored` and `pinned` are display names, nil for Not set and Auto-detect.
```

- [ ] Implement in `SettingsView.swift`. Replace L50 `Text("Auto-detect runs Whisper's language detection on every phrase and drops phrases it is unsure about.")` with `Text(SettingsViewModel.sourceLanguageHelpText)`. Replace L54 `Picker("Don't translate", selection: $model.ignoredLanguage) {` with `Picker("You speak", selection: $model.ignoredLanguage) {`. Replace L60 `SettingExample(symbol: "hand.raised",` with `SettingExample(symbol: "person.wave.2",`. Replace L64 `Text("Skip a language")` with `Text("Your language")`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/SettingsViewModel.swift ReVoxMobile/Screens/SettingExample.swift ReVoxMobile/Screens/SettingsView.swift ReVoxMobileTests/SettingsViewModelTests.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/SettingsViewModel.swift ReVoxMobile/Screens/SettingExample.swift ReVoxMobile/Screens/SettingsView.swift ReVoxMobileTests/SettingsViewModelTests.swift && git commit -m "feat(settings): Your language — You speak, Not set, examples and footers in the people's names

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 4: LiveControlsModel, the optional pill symbol, the strip's new words

- [ ] Append to `LiveControlsTests`:

```swift
    func testTheLiveViewModelIsTheStripsModel() {
        let live = liveModel(store())
        let controls: any LiveControlsModel = live
        controls.isTwoWay = true
        controls.theySpeak = "es"
        XCTAssertEqual(live.twoWayLanguage, "es", "the strip writes through the protocol into the same setting")
        XCTAssertEqual(controls.state, .idle)
        XCTAssertTrue(controls.canChooseYourLanguage)
        XCTAssertNil(controls.pinnedSourceNote)
        XCTAssertNil(controls.twoWayVoiceNote)
    }

    func testTheGroupsAndThePairPillsSayWhoSpeaksWhat() {
        XCTAssertEqual(LiveControlStrip.listenCaption, "Listen")
        XCTAssertEqual(LiveControlStrip.voiceCaption, "Voice")
        XCTAssertEqual(LiveControlStrip.languagesCaption, "Languages")
        XCTAssertEqual(Set([LiveControlStrip.listenCaption, LiveControlStrip.voiceCaption, LiveControlStrip.languagesCaption]).count, 3)
        XCTAssertEqual(LiveControlStrip.captionColumnWidth, 72)
        XCTAssertEqual(LiveControlStrip.youSpeakTitle, "You speak")
        XCTAssertEqual(LiveControlStrip.theySpeakTitle, "They speak")
        XCTAssertEqual(LiveControlStrip.chooseLanguageTitle, "Choose…")
        XCTAssertEqual(LiveControlStrip.youSpeakHintText, "The language you speak; what you say is spoken to them in their language")
        XCTAssertEqual(LiveControlStrip.theySpeakHintText, "The other person's language; what you say is spoken to them in it")
        XCTAssertEqual(LiveControlStrip.theySpeakAccessibilityValue(name: "Spanish", hasVoice: true), "Spanish")
        XCTAssertEqual(LiveControlStrip.theySpeakAccessibilityValue(name: "Spanish", hasVoice: false), "Spanish, no voice on this iPhone")
        XCTAssertEqual(LiveControlStrip.lockedDetailText, "Stop to change the dimmed controls — ReVox reads them once, at Start.")
        XCTAssertTrue(LiveControlStrip.lockedDetailText.hasPrefix(LiveControlStrip.lockedText))
        XCTAssertEqual(LiveControlStrip.volumeHelpText, "How loud ReVox's own voice is; other apps are not affected")
        XCTAssertNotEqual(LiveControlStrip.volumeHelpText, LiveControlStrip.duckingHelpText)
    }
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/LiveControlsTests.swift`
- [ ] Create `ReVoxMobile/Screens/Live/LiveControlsModel.swift`:

```swift
import Observation
import ReVoxCore

/// M11 §1: what the control strip and its groups read and write — `LiveViewModel` on the Live tab, a small demo
/// class in the tutorial (§6), so the tutorial hosts the real controls instead of imitating them. Every member is
/// one the strip already used; the three M11 additions (`theySpeak`, `canChooseYourLanguage`, `pinnedSourceNote`)
/// are documented on `LiveViewModel`.
@MainActor
protocol LiveControlsModel: AnyObject, Observable {
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

- [ ] In `LiveControlPill.swift` replace L14 `let systemImage: String` with `/// nil for the You speak / They speak pair, whose words are the symbol.` / `let systemImage: String?`, and replace L22–25 (`Image(systemName: systemImage)` through `.accessibilityHidden(true)`) with:

```swift
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
```

- [ ] In `LiveControlStrip.swift` replace L225–226 (`static let leaveAloneTitle = "Leave alone"`, `static let replyInTitle = "Reply in"`) and L229–230 (`static let leaveAloneHintText = …`, `static let replyInHintText = …`) — delete all four — and insert after L234 `static let lessHintText = "Hides the explanations"`:

```swift
    /// The caption column of every group: fixed so the pills align across the three rows (M11 §1).
    static let captionColumnWidth: CGFloat = 72
    static let listenCaption = "Listen"
    static let voiceCaption = "Voice"
    static let languagesCaption = "Languages"
    static let youSpeakTitle = "You speak"
    static let theySpeakTitle = "They speak"
    static let chooseLanguageTitle = "Choose…"
    static let youSpeakHintText = "The language you speak; what you say is spoken to them in their language"
    static let theySpeakHintText = "The other person's language; what you say is spoken to them in it"
    static let noVoiceValueSuffix = ", no voice on this iPhone"
    static let volumeHelpText = "How loud ReVox's own voice is; other apps are not affected"
    static let lockedDetailText = "Stop to change the dimmed controls — ReVox reads them once, at Start."

    /// "Spanish, no voice on this iPhone": the crossed speaker is never the only signal.
    static func theySpeakAccessibilityValue(name: String, hasVoice: Bool) -> String {
        hasVoice ? name : name + noVoiceValueSuffix
    }
```

  The strip body still references `leaveAloneTitle` etc. at L41–44 until Task 6; that is fine for `-parse` (no name resolution) and Task 6 lands before any push.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Live/LiveControlsModel.swift ReVoxMobile/Screens/Live/LiveControlPill.swift ReVoxMobile/Screens/Live/LiveControlStrip.swift ReVoxMobileTests/LiveControlsTests.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/Live/LiveControlsModel.swift ReVoxMobile/Screens/Live/LiveControlPill.swift ReVoxMobile/Screens/Live/LiveControlStrip.swift ReVoxMobileTests/LiveControlsTests.swift && git commit -m "feat(live): LiveControlsModel, a pill without a symbol, the captions and pair words

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 5: The three captioned groups

- [ ] Add to `ScreenHostingTests.testLiveViewHostsInEveryState`, after L231 `host(LiveControlPill(systemImage: "speaker.wave.2", title: "Volume", value: "80%", isOn: true).disabled(true))`:

```swift
        // M11 §1: the captioned groups and the pair line in every state — nothing chosen (Choose…), They speak
        // English with no voice note, a pinned source language (You speak disabled, the pinned note in the panel),
        // the caption-above-pills branch, the group the tutorial hosts, and the bare pair pill. The pinned pass
        // resets `settings.language`: the store is shared by every model in this test.
        twoWay.isTwoWay = true
        twoWay.ignoredLanguage = nil
        twoWay.theySpeak = "es"
        host(LiveControlStrip(model: twoWay, showsVolumeSlider: .constant(false), isMoreExpanded: .constant(true)))
        host(LiveDetailsPanel(model: twoWay))
        twoWay.theySpeak = "en"
        XCTAssertNil(twoWay.twoWayVoiceNote)
        host(LiveControlStrip(model: twoWay, showsVolumeSlider: .constant(false), isMoreExpanded: .constant(false)))
        twoWay.ignoredLanguage = "en"
        store.update { $0.language = "es" }
        XCTAssertFalse(twoWay.canChooseYourLanguage)
        host(LiveControlStrip(model: twoWay, showsVolumeSlider: .constant(false), isMoreExpanded: .constant(true)))
        host(LiveDetailsPanel(model: twoWay))
        store.update { $0.language = nil }
        XCTAssertTrue(twoWay.canChooseYourLanguage)
        host(LiveControlStrip(model: twoWay, showsVolumeSlider: .constant(false), isMoreExpanded: .constant(false)).dynamicTypeSize(.accessibility3))
        host(LiveLanguagesGroup(model: twoWay))
        host(LiveListenGroup(model: twoWay, isMoreExpanded: .constant(true)))
        host(LiveVoiceGroup(model: twoWay, showsVolumeSlider: .constant(true)))
        host(LiveVolumeRow(model: twoWay))
        host(LiveLockedLine())
        host(LiveControlPill(systemImage: nil, title: LiveControlStrip.youSpeakTitle, value: LiveControlStrip.chooseLanguageTitle))
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/ScreenHostingTests.swift`
- [ ] Create `ReVoxMobile/Screens/Live/LiveControlGroup.swift`:

```swift
import SwiftUI

/// The caption at the head of a group's row: drawn uppercase, read by VoiceOver in its own case as a heading.
struct LiveGroupCaption: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: LiveControlStrip.captionColumnWidth, minHeight: LiveControlPill.minimumHeight, alignment: .leading)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One captioned row of the strip (M11 §1): the caption is the first subview of the group's own `PillFlowLayout`,
/// so the pills align across rows and wrapping stays inside the group; at accessibility type sizes the caption
/// moves above its pills (the `LiveTranscriptRowView.entryRow` precedent). The group is one VoiceOver container
/// named by its caption.
struct LiveControlGroup<Pills: View>: View {
    let caption: String
    @ViewBuilder let pills: () -> Pills
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    LiveGroupCaption(title: caption)
                    PillFlowLayout(spacing: LiveControlStrip.pillSpacing) { pills() }
                }
            } else {
                PillFlowLayout(spacing: LiveControlStrip.pillSpacing) {
                    LiveGroupCaption(title: caption)
                    pills()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(caption)
    }
}
```

- [ ] Create `ReVoxMobile/Screens/Live/LiveListenGroup.swift`:

```swift
import SwiftUI
import ReVoxCore

/// LISTEN: the source, the latency preset and the ⓘ — the last member of the row and of its VoiceOver container.
/// Source and latency are read once at Start, so they lock; the ⓘ never does.
struct LiveListenGroup: View {
    let model: any LiveControlsModel
    @Binding var isMoreExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        LiveControlGroup(caption: LiveControlStrip.listenCaption) {
            sourcePill
            latencyPill
            morePill
        }
    }

    private var sourcePill: some View {
        Menu {
            Picker(LiveControlStrip.sourceAccessibilityLabel, selection: Binding(get: { model.captureMode }, set: { model.captureMode = $0 })) {
                ForEach(LiveView.availableSources, id: \.self) { mode in
                    Label(LiveView.title(for: mode), systemImage: LiveView.symbol(for: mode)).tag(mode)
                }
            }
        } label: {
            LiveControlPill(systemImage: LiveView.symbol(for: model.captureMode), title: LiveControlStrip.sourcePillTitle(for: model.captureMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.sourceAccessibilityLabel)
        .accessibilityValue(LiveView.title(for: model.captureMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.description(for: model.captureMode))
    }

    private var latencyPill: some View {
        Menu {
            Picker(LiveControlStrip.latencyAccessibilityLabel, selection: Binding(get: { model.latencyMode }, set: { model.latencyMode = $0 })) {
                ForEach(SegmenterPreset.allCases, id: \.self) { preset in
                    Label(SettingsView.title(for: preset), systemImage: LiveControlStrip.latencySymbol(for: preset)).tag(preset)
                }
            }
        } label: {
            LiveControlPill(systemImage: LiveControlStrip.latencySymbol(for: model.latencyMode), title: SettingsView.title(for: model.latencyMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.latencyAccessibilityLabel)
        .accessibilityValue(SettingsView.title(for: model.latencyMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : SettingsViewModel.presetDescription(model.latencyMode))
    }

    /// Symbol only, 44 pt round: the one control whose glyph says it all (ⓘ, the system's own "details").
    private var morePill: some View {
        Button {
            if reduceMotion { isMoreExpanded.toggle() } else { withAnimation(.default) { isMoreExpanded.toggle() } }
        } label: {
            Label(LiveControlStrip.moreTitle(expanded: isMoreExpanded), systemImage: isMoreExpanded ? "chevron.up.circle" : "info.circle")
                .labelStyle(.iconOnly)
                .font(.subheadline)
                .foregroundStyle(isMoreExpanded ? Color.accentColor : Color.secondary)
                .frame(width: LiveControlPill.minimumHeight, height: LiveControlPill.minimumHeight)
                .background(isMoreExpanded ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground), in: Circle())
                .overlay(Circle().strokeBorder(isMoreExpanded ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel(LiveControlStrip.moreAccessibilityLabel)
        .accessibilityValue(LiveControlStrip.moreTitle(expanded: isMoreExpanded))
        .accessibilityHint(isMoreExpanded ? LiveControlStrip.lessHintText : LiveControlStrip.moreHintText)
    }
}
```

- [ ] Create `ReVoxMobile/Screens/Live/LiveVoiceGroup.swift`:

```swift
import SwiftUI

/// VOICE: ducking (read at Start, so it locks) and the voice volume (live: the players read it per clip, M9).
struct LiveVoiceGroup: View {
    let model: any LiveControlsModel
    @Binding var showsVolumeSlider: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        LiveControlGroup(caption: LiveControlStrip.voiceCaption) {
            duckingPill
            volumePill
        }
    }

    private var duckingPill: some View {
        Toggle(isOn: Binding(get: { model.ducking }, set: { model.ducking = $0 })) {
            LiveControlPill(systemImage: "waveform.badge.minus",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.duckingPillName, isOn: model.ducking), isOn: model.ducking)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Ducking")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveControlStrip.duckingHelpText)
    }

    /// Live during a run: the pill shows the level and opens the slider under the strip rather than a sheet.
    private var volumePill: some View {
        Button {
            if reduceMotion { showsVolumeSlider.toggle() } else { withAnimation(.default) { showsVolumeSlider.toggle() } }
        } label: {
            LiveControlPill(systemImage: LiveControlStrip.volumeSymbol(for: model.voiceVolume),
                            title: LiveControlStrip.volumePillText(model.voiceVolume), isOn: showsVolumeSlider)
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel(LiveControlStrip.volumePillName)
        .accessibilityValue(LiveControlStrip.volumePercentText(model.voiceVolume))
        .accessibilityHint(showsVolumeSlider ? LiveControlStrip.hideVolumeHintText : LiveControlStrip.showVolumeHintText)
    }
}

/// The slider the volume pill unfolds under the whole strip.
struct LiveVolumeRow: View {
    let model: any LiveControlsModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: Binding(get: { model.voiceVolume }, set: { model.voiceVolume = $0 }), in: 0...1, step: 0.05) {
                Text(LiveControlStrip.volumePillName)
            }
            .accessibilityValue(LiveControlStrip.volumePercentText(model.voiceVolume))
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: LiveControlPill.minimumHeight)
        .padding(.horizontal)
    }
}
```

- [ ] Create `ReVoxMobile/Screens/Live/LiveLanguagesGroup.swift`:

```swift
import SwiftUI

/// LANGUAGES: Two-way and Learning, and — only while Two-way is on — the full-width pair line "You speak" /
/// "They speak" beneath them (M11 §1). The pair has its own flow, so long names wrap inside the pair line and never
/// into the toggles' row. The tutorial hosts this group as it is (§6).
struct LiveLanguagesGroup: View {
    let model: any LiveControlsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: LiveControlStrip.pillSpacing) {
            LiveControlGroup(caption: LiveControlStrip.languagesCaption) {
                twoWayPill
                learningPill
            }
            if model.isTwoWay {
                PillFlowLayout(spacing: LiveControlStrip.pillSpacing) {
                    youSpeakPill
                    theySpeakPill
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveControlStrip.languagesCaption)
        .animation(reduceMotion ? nil : .default, value: model.isTwoWay)
    }

    private var twoWayPill: some View {
        Toggle(isOn: Binding(get: { model.isTwoWay }, set: { model.isTwoWay = $0 })) {
            LiveControlPill(systemImage: "arrow.left.arrow.right",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.twoWayPillName, isOn: model.isTwoWay), isOn: model.isTwoWay)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Two-way conversation")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.twoWayHintText)
    }

    private var learningPill: some View {
        Toggle(isOn: Binding(get: { model.isLearning }, set: { model.isLearning = $0 })) {
            LiveControlPill(systemImage: model.isLearning ? "text.book.closed.fill" : "text.book.closed",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.learningPillName, isOn: model.isLearning), isOn: model.isLearning)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Learning mode")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveControlStrip.learningHelpText)
    }

    /// Backed by `Settings.ignoredLanguage`, the same setting as Settings › Your language. No "Not set" row here:
    /// the pill says "Choose…" until one is chosen, and unsetting lives in Settings. Disabled while a source
    /// language is pinned, with the note that says why and where.
    private var youSpeakPill: some View {
        let name = model.ignoredLanguage.map { LanguageCatalog.displayName($0, whenNil: LiveView.noLanguageTitle) }
        return Menu {
            Picker(LiveControlStrip.youSpeakTitle, selection: Binding(get: { model.ignoredLanguage }, set: { model.ignoredLanguage = $0 })) {
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code)
                }
            }
        } label: {
            LiveControlPill(systemImage: nil, title: LiveControlStrip.youSpeakTitle, value: name ?? LiveControlStrip.chooseLanguageTitle)
        }
        .disabled(isLocked || !model.canChooseYourLanguage)
        .accessibilityLabel(LiveControlStrip.youSpeakTitle)
        .accessibilityValue(name ?? LiveView.noLanguageTitle)
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : (model.pinnedSourceNote ?? LiveControlStrip.youSpeakHintText))
    }

    /// Backed by `Settings.twoWayLanguage` through `theySpeak`: English is a real, ticked row, never "None".
    private var theySpeakPill: some View {
        let name = LanguageCatalog.displayName(model.theySpeak, whenNil: LiveView.noLanguageTitle)
        let hasVoice = model.twoWayVoiceNote == nil
        return Menu {
            Picker(LiveControlStrip.theySpeakTitle, selection: Binding(get: { model.theySpeak }, set: { model.theySpeak = $0 })) {
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code ?? "en")
                }
            }
        } label: {
            LiveControlPill(systemImage: hasVoice ? nil : "speaker.slash", title: LiveControlStrip.theySpeakTitle, value: name)
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.theySpeakTitle)
        .accessibilityValue(LiveControlStrip.theySpeakAccessibilityValue(name: name, hasVoice: hasVoice))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : (model.twoWayVoiceNote ?? LiveControlStrip.theySpeakHintText))
    }
}
```

- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Live/LiveControlGroup.swift ReVoxMobile/Screens/Live/LiveListenGroup.swift ReVoxMobile/Screens/Live/LiveVoiceGroup.swift ReVoxMobile/Screens/Live/LiveLanguagesGroup.swift ReVoxMobileTests/ScreenHostingTests.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/Live/LiveControlGroup.swift ReVoxMobile/Screens/Live/LiveListenGroup.swift ReVoxMobile/Screens/Live/LiveVoiceGroup.swift ReVoxMobile/Screens/Live/LiveLanguagesGroup.swift ReVoxMobileTests/ScreenHostingTests.swift && git commit -m "feat(live): Listen, Voice and Languages groups with a You speak / They speak pair line

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 6: The strip composes the groups; the lock line; the panel with headings

- [ ] The tests for this step are the ScreenHostingTests passes from Task 5 (the running `broadcast` strip at L228 now shows the lock line under the groups; the panel hosts with headings) and `testTheStripLocksTheStartTimeControlsWhilePreparingAndRunning` (unchanged). Nothing new to write; run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/ScreenHostingTests.swift`.
- [ ] Implement in `LiveControlStrip.swift`. Replace L4–14 (the header doc comment) with:

```swift
/// M11: the Live screen's controls as three captioned rows of pills — LISTEN (source, latency, ⓘ), VOICE (ducking,
/// volume) and LANGUAGES (Two-way, Learning, and the You speak / They speak pair while Two-way is on) — each row
/// its own `PillFlowLayout` with a 72 pt caption column first, so the pills align and wrapping stays inside a
/// group. Everything the pipeline reads once at Start locks while a run is going: dimmed, with one "Stop to
/// change" line under the groups so tapping Start moves nothing above it. The volume and the ⓘ stay live. The
/// model is `any LiveControlsModel`, so the tutorial hosts the same strip (§6). Height at the default type size:
/// 144 pt idle with Two-way off, 194 pt on, +24 pt while locked.
```

  Replace L15–54 (from `struct LiveControlStrip: View {` through the closing `}` of `body`) with:

```swift
struct LiveControlStrip: View {
    let model: any LiveControlsModel
    @Binding var showsVolumeSlider: Bool
    @Binding var isMoreExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { Self.locksControls(in: model.state) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: Self.pillSpacing) {
                LiveListenGroup(model: model, isMoreExpanded: $isMoreExpanded)
                LiveVoiceGroup(model: model, showsVolumeSlider: $showsVolumeSlider)
                LiveLanguagesGroup(model: model)
                if isLocked {
                    LiveLockedLine()
                }
            }
            .padding(.horizontal)
            if showsVolumeSlider {
                LiveVolumeRow(model: model)
            }
        }
        .animation(reduceMotion ? nil : .default, value: showsVolumeSlider)
    }
```

  Delete L56–210 entirely (from `// MARK: The pills` through the closing `}` of `toggleWithMotion`: `lockedPill`, `sourcePill`, `latencyPill`, `duckingPill`, `learningPill`, `twoWayPill`, `volumePill`, `morePill`, `languagePill(title:systemImage:selection:hint:)`, `volumeRow`, `toggleWithMotion`) — the groups own them now. Replace L214–215 (the `pillSpacing` doc comment) with `/// 6 pt between pills and 10 pt inside them: each group is one row on a 393 pt phone at the default type size` / `/// (`PillFlowLayoutTests`); a narrower phone or a larger type size wraps inside the group.`
  Insert before `struct LiveDetailsPanel` (after the strip's closing brace):

```swift
/// The one visible word about the lock, under the groups: static text, not a control (about 18 pt), so tapping
/// Start dims the pills in place and moves nothing under the finger.
struct LiveLockedLine: View {
    var body: some View {
        Label(LiveControlStrip.lockedText, systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(LiveView.lockedWhileRunningText)
    }
}
```

  Replace `LiveDetailsPanel` (from its doc comment through the end of the file) with:

```swift
/// The rarely needed words behind the pills, folded away by default, under the same three headings as the rows so
/// VoiceOver can jump by heading: a locked line while a run is going, what the source listens to, what the preset
/// waits for, ducking, volume, what Two-way will do in the people's languages (plus the missing-voice and
/// pinned-source notes), and Learning. Expanded and collapsed per launch only (`@State` in `LiveView`).
struct LiveDetailsPanel: View {
    let model: any LiveControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if LiveControlStrip.locksControls(in: model.state) {
                detail(LiveControlStrip.lockedDetailText, systemImage: "lock.fill")
            }
            heading(LiveControlStrip.listenCaption)
            detail(LiveView.description(for: model.captureMode), systemImage: LiveView.symbol(for: model.captureMode))
            detail(LiveControlStrip.latencyDetailText(for: model.latencyMode), systemImage: LiveControlStrip.latencySymbol(for: model.latencyMode))
            heading(LiveControlStrip.voiceCaption)
            detail(LiveControlStrip.duckingHelpText, systemImage: "waveform.badge.minus")
            detail(LiveControlStrip.volumeHelpText, systemImage: "speaker.wave.2")
            heading(LiveControlStrip.languagesCaption)
            detail(model.isTwoWay ? LiveView.twoWaySummary(you: model.ignoredLanguage, they: model.theySpeak)
                                  : LiveView.twoWayOffSummary(you: model.ignoredLanguage),
                   systemImage: "arrow.left.arrow.right")
            if let note = model.twoWayVoiceNote {
                detail(note, systemImage: "speaker.slash")
            }
            if let note = model.pinnedSourceNote {
                detail(note, systemImage: "pin")
            }
            detail(LiveControlStrip.learningHelpText, systemImage: "text.book.closed")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveControlStrip.moreAccessibilityLabel)
    }

    private func heading(_ caption: String) -> some View {
        Text(caption)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .accessibilityLabel(caption)
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .accessibilityElement(children: .combine)
    }
}
```

- [ ] Check the strip file no longer mentions the retired names: `grep -n 'leaveAlone\|replyIn\|languagePill\|lockedPill\|toggleWithMotion' ReVoxMobile/Screens/Live/LiveControlStrip.swift` prints nothing. `LiveView.swift` L26–28 (`LiveControlStrip(model: model, …)`, `LiveDetailsPanel(model: model)`) compile unchanged: `LiveViewModel` is a `LiveControlsModel`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Live/LiveControlStrip.swift ReVoxMobile/Screens/LiveView.swift`
- [ ] Commit: `git add ReVoxMobile/Screens/Live/LiveControlStrip.swift && git commit -m "feat(live): the strip is three captioned rows, a lock line beneath them and a panel with headings

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

### Task 7: PillFlowLayoutTests per group, the gates, the lane's last commit

- [ ] In `PillFlowLayoutTests` replace L38–53 (the two strip tests and their doc comments, from `/// The seven pills of the idle strip fit two rows…` to the closing brace of `testTheLanguagePillsAreTheThirdRowWhileTwoWayIsOn`) with:

```swift
    // MARK: M11 — one captioned row per group on a 393 pt phone (361 pt inside the margins)

    /// The width a pill or caption renders at on this simulator at the default type size — measured here rather
    /// than typed in, so a title, padding or font change moves the packing with it. The M10 numbers CI run 107
    /// measured were Mic 66, Balanced 108, ⓘ 44, Duck on 102, 100% 92, Two-way off 132, Learn off 106; the pair
    /// pills are estimated at You speak English 150 and They speak Spanish 161, and the failure message prints
    /// what CI actually measured.
    @MainActor private func width<V: View>(_ view: V) -> CGFloat {
        let controller = UIHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(width: 1_000, height: LiveControlPill.minimumHeight)).width.rounded(.up)
    }

    private static let phone: CGFloat = 393 - 32
    private static let narrowPhone: CGFloat = 320 - 32

    @MainActor func testEachIdleGroupIsOneRowOnAThreeNinetyThreePointPhone() {
        let caption = width(LiveGroupCaption(title: LiveControlStrip.languagesCaption))
        XCTAssertEqual(caption, LiveControlStrip.captionColumnWidth, "the longest caption fits the fixed column")
        let listen = [caption, width(LiveControlPill(systemImage: "mic", title: "Mic")),
                      width(LiveControlPill(systemImage: LiveControlStrip.latencySymbol(for: .balanced), title: "Balanced")),
                      LiveControlPill.minimumHeight].map { size($0) }
        let voice = [caption, width(LiveControlPill(systemImage: "waveform.badge.minus", title: "Duck on", isOn: true)),
                     width(LiveControlPill(systemImage: "speaker.wave.3", title: "100%"))].map { size($0) }
        let languages = [caption, width(LiveControlPill(systemImage: "arrow.left.arrow.right", title: "Two-way off")),
                         width(LiveControlPill(systemImage: "text.book.closed", title: "Learn off"))].map { size($0) }
        for (name, group) in [("Listen", listen), ("Voice", voice), ("Languages", languages)] {
            let rows = PillFlowLayout.rows(sizes: group, available: Self.phone, spacing: LiveControlStrip.pillSpacing)
            XCTAssertEqual(rows.count, 1, "\(name) measured \(group.map(\.width)) at \(Self.phone) pt")
        }
    }

    @MainActor func testTheLanguagePairIsOneRowOnAThreeNinetyThreePointPhone() {
        let pair = [width(LiveControlPill(systemImage: nil, title: LiveControlStrip.youSpeakTitle, value: "English")),
                    width(LiveControlPill(systemImage: nil, title: LiveControlStrip.theySpeakTitle, value: "Spanish"))].map { size($0) }
        let rows = PillFlowLayout.rows(sizes: pair, available: Self.phone, spacing: LiveControlStrip.pillSpacing)
        XCTAssertEqual(rows.map(\.items), [[0, 1]], "measured \(pair.map(\.width))")
    }

    /// On a 320 pt phone a group wraps inside itself: the ⓘ drops under Listen, the pair becomes two lines.
    func testAGroupWrapsOnlyInsideItselfOnAThreeTwentyPointPhone() {
        let listen = [size(72), size(66), size(108), size(44)]
        XCTAssertEqual(PillFlowLayout.rows(sizes: listen, available: Self.narrowPhone, spacing: LiveControlStrip.pillSpacing).map(\.items), [[0, 1, 2], [3]])
        let pair = [size(150), size(161)]
        XCTAssertEqual(PillFlowLayout.rows(sizes: pair, available: Self.narrowPhone, spacing: LiveControlStrip.pillSpacing).map(\.items), [[0], [1]])
    }
```

  (`size(_:_:)` at L7 and the pure tests L9–36 stay. `UIHostingController` comes with `import SwiftUI`, already at L2.)
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/PillFlowLayoutTests.swift`. If CI's first run shows a group at two rows, the fix is the strip (a shorter word, `captionColumnWidth` 68), never the test.
- [ ] Run the gates: `python3 scripts/dev/check-core-imports.py --all && python3 scripts/dev/check-test-autoclosures.py && python3 scripts/dev/check-tests-are-discoverable.py && bash scripts/ci/check-constant-coverage.sh` — all four print their "no problems" line (this lane adds no ported constant). Then `grep -rn 'Leave alone\|Reply in\|Don.t translate\|Skip a language\|left alone' ReVoxMobile/Screens/Live ReVoxMobile/Screens/LiveView.swift ReVoxMobile/Screens/LiveViewModel.swift ReVoxMobile/Screens/Settings*.swift ReVoxMobile/Screens/SettingExample.swift` prints nothing (Onboarding's copies are L6's, wave 2). Finally `for f in ReVoxMobile/Screens/Live/*.swift ReVoxMobile/Screens/LiveView.swift ReVoxMobile/Screens/LiveViewModel.swift ReVoxMobile/Screens/SettingsView.swift ReVoxMobile/Screens/SettingsViewModel.swift ReVoxMobile/Screens/SettingExample.swift ReVoxMobileTests/LiveControlsTests.swift ReVoxMobileTests/TwoWayLiveTests.swift ReVoxMobileTests/PillFlowLayoutTests.swift ReVoxMobileTests/SettingsViewModelTests.swift ReVoxMobileTests/ScreenHostingTests.swift; do /home/user/swift/usr/bin/swiftc -parse "$f" || echo "PARSE FAIL $f"; done`.
- [ ] Commit: `git add ReVoxMobileTests/PillFlowLayoutTests.swift && git commit -m "test(live): each captioned group and the pair line pack into one row at 393 pt, measured on the simulator

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"`

**Cross-lane needs**

- L6 (Tutorial, wave 2): `ReVoxMobile/Screens/Onboarding/OnboardingView.swift` L457–458 calls `LiveView.twoWaySummary(ignored:target:)` and L467–468 show the literals "Don't translate" / "Reply in"; `OnboardingPage.swift` L36 and L110 say "left alone". This lane keeps a forwarding `LiveView.twoWaySummary(ignored:target:)` so the app target compiles in wave 1; L6 replaces the demo with `LiveLanguagesGroup(model:)` / `twoWaySummary(you:they:)` and deletes the forwarder and its `TwoWayLiveTests` assertion line.
- L7 (Docs): README alt text and the Two-way steps, `docs/onboarding.md`, ADR-0006/0007, the bug template — the retired words live there too.
- L5 (Wiring): the `GuessesSettingsSection` insertion point in `SettingsView.swift` is directly after the Source language section, whose footer is now `Text(SettingsViewModel.sourceLanguageHelpText)` (L49–51).
- L2 (Unsure phrases): its two `LiveViewModel.swift` hunks (`configuration(settings:captureMode:)` L173–182 and `handle(.entry)` past L504) are disjoint from this lane's L184–219 edits and the new members inserted after `twoWayLanguage`; merge cleanly.
- ScreenshotTests (L5/L7): `live-idle` / `live-running` captures need no code change; the README alt text must match the rendered captioned rows.