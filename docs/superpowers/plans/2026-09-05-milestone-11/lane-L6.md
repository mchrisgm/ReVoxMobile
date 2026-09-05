## Lane L6: Tutorial refresh (wave 2)

Spec §6 and §7 row L6. Runs after wave 1 is merged (L1's `LiveControlsModel`, the captioned groups, `theySpeak`, `LiveView.twoWaySummary(you:they:)` / `twoWayOffSummary(you:)` and L2's `LiveTranscriptRow.isGuess` are all on the branch already — verified against the files quoted below). The tutorial stops imitating the Live screen and hosts it: a demo `OnboardingLiveControls: LiveControlsModel` owned by `OnboardingViewModel.controls` drives the real `LiveControlStrip`, `LiveDetailsPanel` and `LiveLanguagesGroup`; the transcript demo ends with a greyed Unsure row; the Learning page uses the real row view so L4/L5's tappable words work without a tutorial change; `OnboardingViewModel.version = 2`.

Every code block below was written against the current files and passed `swiftc -parse`, `check-core-imports.py --all`, `check-test-autoclosures.py`, `check-tests-are-discoverable.py` and `check-no-host-time.sh` in a dry run; CI (Xcode 26) is the compiler for the app target, so each "run" step for an app-target or test file is a parse only.

**Files**

- Create: `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingLiveControls.swift` (picked up by `project.yml`'s folder source `- path: ReVoxMobile`)
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift`
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingPage.swift`
- Modify: `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingView.swift`
- Modify: `/home/user/ReVoxMobile/docs/onboarding.md`
- Test files: `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingHostingTests.swift`, `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingScreenshotTests.swift`

**Interfaces**

Consumes (all present on the branch after the wave-1 merges; file and line quoted):
- `@MainActor protocol LiveControlsModel: AnyObject, Observable { var state: LiveState { get }; var captureMode: CaptureMode { get set }; var latencyMode: SegmenterPreset { get set }; var ducking: Bool { get set }; var voiceVolume: Double { get set }; var isTwoWay: Bool { get set }; var isLearning: Bool { get set }; var ignoredLanguage: String? { get set }; var theySpeak: String { get set }; var twoWayVoiceNote: String? { get }; var canChooseYourLanguage: Bool { get }; var pinnedSourceNote: String? { get } }` — `ReVoxMobile/Screens/Live/LiveControlsModel.swift` L8-22
- `enum LiveState: Equatable, Sendable { case idle, preparing, running, error }` — `LiveViewModel.swift` L5-7
- `struct LiveControlStrip: View { let model: any LiveControlsModel; @Binding var showsVolumeSlider: Bool; @Binding var isMoreExpanded: Bool }` — `LiveControlStrip.swift` L35-38; statics `pillSpacing`, `lockedText = "Stop to change"`, `learningPillName = "Learn"`, `twoWayPillName = "Two-way"`, `moreAccessibilityLabel = "Details"`, `listenCaption = "Listen"`, `voiceCaption = "Voice"`, `languagesCaption = "Languages"`, `static func locksControls(in state: LiveState) -> Bool` (L66-106)
- `struct LiveDetailsPanel: View { let model: any LiveControlsModel }` — `LiveControlStrip.swift` L176-177 (pads itself `.padding(.horizontal)`)
- `struct LiveLanguagesGroup: View { let model: any LiveControlsModel }` — `LiveLanguagesGroup.swift` L6-7 (no horizontal padding of its own; the strip adds `.padding(.horizontal)` around the three groups)
- `LiveView.buttonTitle(for state: LiveState) -> String` ("Start" / "Stop"), `LiveView.description(for:)`, `LiveView.symbol(for:)`, `LiveView.microphoneDescription`, `LiveView.noLanguageTitle = "Not set"`, `LiveView.twoWaySummary(you: String?, they: String?) -> String`, `LiveView.twoWayOffSummary(you: String?) -> String` — `LiveView.swift` L290-359
- `LiveViewModel.voiceNote(for target: String?) -> String?` (static; walks the installed voices) — `LiveViewModel.swift` L244-248
- `LiveTranscriptRow.init(id: UUID = UUID(), time: Date, kind: Kind, isGuess: Bool = false)` and `let isGuess: Bool` — `LiveTranscriptRow.swift` L23-25 (seam commit)
- `LiveTranscriptRowView(row:now:timeDisplay:showsOriginal:romanizes:)` — `LiveTranscriptRowView.swift` L4-12; L5 renders `row.isGuess` greyed and marked Unsure, and the tappable words, inside this view with no new parameter (spec §2, §3, §7 row L5)
- `SettingExamples.sampleRow(original:)`, `SettingExamples.japaneseRow`, `SettingExamples.spanishOriginal`, `SettingExamples.sampleTime`, `SettingExamples.learning(_:)`, `SettingExamples.romanize(_:)`, `SettingExamples.keepModelWhenHot(_:model:)` — `SettingExample.swift` L45-124
- `SettingsView.showTutorialTitle`, `SettingsView(model:models:voices:onboarding:)` — `SettingsView.swift` L10, L172
- `ModelCatalog.defaultWhisperModel: WhisperModelID` (`.small`) — `ReVoxCore/Sources/ReVoxCore/ModelCatalog.swift` L106; `Settings()` (public no-arg init; `.ducking` true, `.voiceVolume` 1.0)
- `LanguageCatalog.displayName(_:whenNil:)` — `Screens/LanguageCatalog.swift`
- `ScreenshotTests.outputDirectory()`, `.makeWindow()`, `.distinctColors(in:)`, `.blankThreshold`; `ScreenHostingSupport(layout:store:)`; `waitFor(_:timeout:_:)` in `ReVoxMobileTests/Support/AsyncAssertions.swift` L27

Produces (for other lanes and for the README/screenshot pipeline):
- `@MainActor @Observable final class OnboardingLiveControls: LiveControlsModel` with `private(set) var state: LiveState`, `var isRunning: Bool`, `func start()`, `func stop()`, `func reset()`, `func refreshVoiceNote()`, and the twelve protocol members (`theySpeak` computed; `canChooseYourLanguage` always true; `pinnedSourceNote` always nil)
- `OnboardingViewModel.controls: OnboardingLiveControls`, `demoShowsDetails: Bool`, `demoShowsVolumeSlider: Bool`, `lastDemoRowIsGuess: Bool`, `static let version = 2`
- `enum OnboardingPage { case welcome, controls, transcript, twoWay, learning, models, ready }` (`.source` is gone)
- `OnboardingDemo.Line.isGuess`, `OnboardingDemo.transcriptScript` (5 lines, the last a guess), `guessText`, `bothSidesText`, `wordTapText`, `benchmarkText`, `twoWayOnText(you: String?, they: String) -> String`, `twoWayOffText(you: String?) -> String`, `recommendedModel = ModelCatalog.defaultWhisperModel`
- `struct OnboardingStartStopButton: View { isRunning, accessibilityLabel, accessibilityHint, action; static func title(running: Bool) -> String }`
- `struct OnboardingControlsDemo: View` with statics `tipText`, `lockedTipText`, `startAccessibilityLabel`, `stopAccessibilityLabel`, `startHint`, `stopHint`; `OnboardingTranscriptDemo.captionText(playing:lastIsGuess:)`, `.captionSymbol(playing:lastIsGuess:)`, `.startAccessibilityLabel`, `.stopAccessibilityLabel`, `.hintText`
- Screenshots CI writes to `Documents/screenshots`: `onboarding-welcome.png`, `onboarding-controls.png`, `onboarding-transcript.png`, `onboarding-learning.png` (the README cells are L7's; see Cross-lane needs)

### Task 1: The demo strip model, `OnboardingLiveControls`

- [ ] **Write the failing test.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift`, insert after the closing brace of `testANewerVersionShowsAgainAnOlderOneDoesNot` (today's L115) and before `// MARK: The transcript demo` (L117):

```swift
    // MARK: The demo strip model

    func testTheControlsDemoIsTheStripsOwnModel() {
        let model = OnboardingViewModel(defaults: defaults)
        let controls: any LiveControlsModel = model.controls   // the conformance is the compile
        XCTAssertEqual(controls.captureMode, .microphone)
        XCTAssertEqual(controls.latencyMode, .balanced)
        XCTAssertEqual(controls.ignoredLanguage, "en")
        XCTAssertEqual(controls.theySpeak, "es")
        XCTAssertTrue(controls.canChooseYourLanguage)
        XCTAssertNil(controls.pinnedSourceNote)
        XCTAssertNil(controls.twoWayVoiceNote, "no voice walk at init: the tutorial is built on every launch")
        XCTAssertFalse(LiveControlStrip.locksControls(in: controls.state))
        XCTAssertFalse(model.controls.isRunning)

        model.controls.start()
        XCTAssertEqual(model.controls.state, .running)
        XCTAssertTrue(model.controls.isRunning)
        XCTAssertTrue(LiveControlStrip.locksControls(in: controls.state), "Start locks the pills as a session does")
        model.controls.stop()
        XCTAssertEqual(model.controls.state, .idle)
        XCTAssertFalse(LiveControlStrip.locksControls(in: controls.state))

        model.controls.theySpeak = "zz"
        XCTAssertEqual(model.controls.theySpeak, "zz")
        XCTAssertEqual(model.controls.twoWayVoiceNote, LiveViewModel.voiceNote(for: "zz"), "the setter refreshes the note")
        XCTAssertNotNil(model.controls.twoWayVoiceNote)
        model.controls.theySpeak = "en"
        XCTAssertNil(model.controls.twoWayVoiceNote, "every iPhone has an English voice")

        model.controls.theySpeak = "zz"
        model.controls.reset()
        XCTAssertEqual(model.controls.theySpeak, OnboardingDemo.twoWayTarget)
        XCTAssertEqual(model.controls.twoWayVoiceNote, LiveViewModel.voiceNote(for: OnboardingDemo.twoWayTarget), "reset refreshes the note for the default language")
        model.controls.refreshVoiceNote()
        XCTAssertEqual(model.controls.twoWayVoiceNote, LiveViewModel.voiceNote(for: OnboardingDemo.twoWayTarget))
    }
```

- [ ] **Run it.** CI is the compiler: swiftc -parse only. `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift` must print nothing (the test is red on CI until the class and `controls` exist: `OnboardingLiveControls` and `model.controls` are undefined).

- [ ] **Implement: the class.** Create `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingLiveControls.swift`:

```swift
import Foundation
import Observation
import ReVoxCore

/// M11 §6: the tutorial's model for the Live strip. The same twelve members `LiveViewModel` gives the strip,
/// backed by memory instead of `SettingsStore`, so tapping a demo pill changes no setting; `start()` / `stop()`
/// flip `state` so the pills lock exactly as a session locks them. The voice note is refreshed lazily
/// (`refreshVoiceNote()`, from the page's `onAppear` and from `reset()`) and by the `theySpeak` setter, never in
/// `init`: `AppEnvironment` builds the tutorial on every launch and walking the installed voices is not free.
@MainActor
@Observable
final class OnboardingLiveControls: LiveControlsModel {
    private(set) var state: LiveState = .idle
    var captureMode: CaptureMode = .microphone
    var latencyMode: SegmenterPreset = .balanced
    var ducking: Bool = Settings().ducking
    var voiceVolume: Double = Settings().voiceVolume
    var isTwoWay = false
    var isLearning = false
    var ignoredLanguage: String? = OnboardingDemo.twoWayIgnored
    private(set) var twoWayVoiceNote: String?
    let canChooseYourLanguage = true
    let pinnedSourceNote: String? = nil

    private var storedTheySpeak: String = OnboardingDemo.twoWayTarget

    /// Computed over a stored property rather than `didSet`, so the note follows every change (the `@Observable`
    /// macro and property observers are a corner the repo avoids).
    var theySpeak: String {
        get { storedTheySpeak }
        set {
            storedTheySpeak = newValue
            refreshVoiceNote()
        }
    }

    var isRunning: Bool { state == .running }

    func start() { state = .running }
    func stop() { state = .idle }

    /// The same note Live shows: nil while this iPhone has a voice for the language.
    func refreshVoiceNote() {
        twoWayVoiceNote = LiveViewModel.voiceNote(for: storedTheySpeak)
    }

    /// Every member back to its first value, stopped, with the voice note refreshed for the default language.
    func reset() {
        stop()
        captureMode = .microphone
        latencyMode = .balanced
        ducking = Settings().ducking
        voiceVolume = Settings().voiceVolume
        isTwoWay = false
        isLearning = false
        ignoredLanguage = OnboardingDemo.twoWayIgnored
        theySpeak = OnboardingDemo.twoWayTarget
    }
}
```

- [ ] **Implement: `controls` on the view model.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift` replace L22-24

```swift
    // The demos. Each page's control is bound to one of these, and `reset()` puts them back.
    var demoSource: CaptureMode = .microphone
    var demoTwoWay = false
```

with

```swift
    // The demos. The strip's model is `controls` (M11 §6); the rest are bound to one page each, and `reset()`
    // puts them all back.
    let controls: OnboardingLiveControls
    var demoSource: CaptureMode = .microphone
    var demoTwoWay = false
```

and replace the init at L36-39

```swift
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shouldShowNow = Self.shouldShow(defaults: defaults)
    }
```

with (assigned inside the already-isolated init rather than as a stored default, the LiveViewModel L99-103 precedent):

```swift
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.controls = OnboardingLiveControls()
        self.shouldShowNow = Self.shouldShow(defaults: defaults)
    }
```

- [ ] **Run.** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingLiveControls.swift && /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift && python3 /home/user/ReVoxMobile/scripts/dev/check-core-imports.py --all` (the new file uses `CaptureMode`, `SegmenterPreset`, `Settings`; it imports ReVoxCore).

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Onboarding/OnboardingLiveControls.swift ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift ReVoxMobileTests/OnboardingTests.swift && git commit -m "feat(tutorial): OnboardingLiveControls — the demo model behind the real Live strip

The twelve LiveControlsModel members backed by memory, start()/stop() for the lock,
the voice note refreshed by the theySpeak setter and reset(), never in init.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 2: Version 2, the strip's per-launch states, and a guess at the end of the script

- [ ] **Write the failing tests.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift` replace `testResetShowsAgainFromTheFirstPageWithFreshDemos` (L84-106, from `func testResetShowsAgainFromTheFirstPageWithFreshDemos() {` through its closing `}`) with:

```swift
    func testResetShowsAgainFromTheFirstPageWithFreshDemos() {
        let model = OnboardingViewModel(defaults: defaults)
        model.show(.models)
        model.controls.captureMode = .broadcast
        model.controls.latencyMode = .veryFast
        model.controls.ducking = false
        model.controls.voiceVolume = 0.2
        model.controls.isTwoWay = true
        model.controls.isLearning = true
        model.controls.ignoredLanguage = "fr"
        model.controls.theySpeak = "de"
        model.controls.start()
        model.demoShowsDetails = true
        model.demoShowsVolumeSlider = true
        model.demoRomanize = true
        model.demoModel = .largeV3
        model.demoKeepModelWhenHot = true
        model.finish()
        XCTAssertFalse(model.shouldShowNow)
        XCTAssertEqual(model.controls.state, .idle, "finishing stops the demo session")
        model.reset()
        XCTAssertTrue(model.shouldShowNow)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertNil(defaults.object(forKey: OnboardingViewModel.storageKey))
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults))
        XCTAssertEqual(model.controls.captureMode, .microphone)
        XCTAssertEqual(model.controls.latencyMode, .balanced)
        XCTAssertEqual(model.controls.ducking, Settings().ducking)
        XCTAssertEqual(model.controls.voiceVolume, Settings().voiceVolume)
        XCTAssertFalse(model.controls.isTwoWay)
        XCTAssertFalse(model.controls.isLearning)
        XCTAssertEqual(model.controls.ignoredLanguage, OnboardingDemo.twoWayIgnored)
        XCTAssertEqual(model.controls.theySpeak, OnboardingDemo.twoWayTarget)
        XCTAssertEqual(model.controls.state, .idle)
        XCTAssertFalse(model.demoShowsDetails)
        XCTAssertFalse(model.demoShowsVolumeSlider)
        XCTAssertFalse(model.demoRomanize)
        XCTAssertEqual(model.demoModel, .small)
        XCTAssertFalse(model.demoKeepModelWhenHot)
    }
```

Replace `testANewerVersionShowsAgainAnOlderOneDoesNot` (L108-115) with:

```swift
    func testANewerVersionShowsAgainAnOlderOneDoesNot() {
        XCTAssertEqual(OnboardingViewModel.version, 2, "M11 §6: everyone who finished the M10 tutorial sees the refreshed one once")
        defaults.set(1, forKey: OnboardingViewModel.storageKey)
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults), "finished M10's tutorial: the redesigned pages show once")
        defaults.set(OnboardingViewModel.version - 1, forKey: OnboardingViewModel.storageKey)
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults), "an older completed version means the tutorial changed")
        defaults.set(OnboardingViewModel.version, forKey: OnboardingViewModel.storageKey)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults))
        defaults.set(OnboardingViewModel.version + 1, forKey: OnboardingViewModel.storageKey)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults), "a newer record (a downgrade) does not nag")
    }
```

Replace `testDemoRowsFollowTheScriptAndStopAtItsEnd` (L119-143) with:

```swift
    func testDemoRowsFollowTheScriptAndStopAtItsEnd() {
        let model = OnboardingViewModel(defaults: defaults)
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertTrue(model.demoRows.isEmpty)
        XCTAssertFalse(model.lastDemoRowIsGuess)
        model.startDemo()
        XCTAssertTrue(model.isDemoPlaying)
        let script = OnboardingDemo.transcriptScript
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, line) in script.enumerated() {
            XCTAssertTrue(model.appendNextDemoRow(now: base.addingTimeInterval(Double(index))))
            XCTAssertEqual(model.demoRows.count, index + 1)
            XCTAssertEqual(model.demoRows[index].kind, .entry(language: line.language, original: line.original, english: line.english))
            XCTAssertEqual(model.demoRows[index].time, base.addingTimeInterval(Double(index)))
            XCTAssertEqual(model.demoRows[index].isGuess, line.isGuess)
            XCTAssertEqual(model.lastDemoRowIsGuess, line.isGuess)
        }
        XCTAssertTrue(model.isDemoComplete)
        XCTAssertTrue(model.lastDemoRowIsGuess, "the script ends with the guess")
        XCTAssertFalse(model.appendNextDemoRow(), "the script is spent")
        XCTAssertEqual(model.demoRows.count, script.count)
        XCTAssertTrue(model.isDemoPlaying, "the demo keeps running so the ages count up, until Stop")
        model.stopDemo()
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertEqual(model.demoRows.count, script.count, "Stop keeps the transcript, like the Live screen")
        XCTAssertTrue(model.lastDemoRowIsGuess, "the greyed row stays after Stop, and so does its caption")
        model.startDemo()
        XCTAssertTrue(model.demoRows.isEmpty, "Start begins the conversation again")
        model.stopDemo()
    }
```

Replace `testFinishStopsTheDemo` (L157-163) with:

```swift
    func testFinishStopsTheDemo() {
        let model = OnboardingViewModel(defaults: defaults)
        model.show(.transcript)
        model.startDemo()
        model.controls.start()
        model.finish()
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertEqual(model.controls.state, .idle, "the demo session is stopped too")
    }
```

In `testCopyBehindTheDemos`, replace L175 `XCTAssertEqual(OnboardingDemo.transcriptScript.count, 4)` with:

```swift
        XCTAssertEqual(OnboardingDemo.transcriptScript.count, 5)
        XCTAssertEqual(OnboardingDemo.transcriptScript.filter(\.isGuess).count, 1)
        XCTAssertEqual(OnboardingDemo.transcriptScript.last?.isGuess, true)
        XCTAssertEqual(OnboardingDemo.transcriptScript.last?.language, "pt")
        XCTAssertEqual(OnboardingDemo.guessText, "The greyed phrase is marked Unsure: ReVox was not sure of it, so it is kept but not spoken.")
```

- [ ] **Run it.** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift` (red on CI: `demoShowsDetails`, `demoShowsVolumeSlider`, `lastDemoRowIsGuess`, `Line.isGuess`, `guessText` do not exist; `version` is 1).

- [ ] **Implement: the script's guess line.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingPage.swift` replace L85-101

```swift
    /// A scripted conversation for the transcript demo, one row at a time.
    struct Line: Equatable, Sendable {
        let language: String
        let original: String
        let english: String
    }

    static let transcriptScript: [Line] = [
        Line(language: "es", original: "Buenos días, ¿cómo estás?", english: "Good morning, how are you?"),
        Line(language: "fr", original: "Le train part à neuf heures.", english: "The train leaves at nine."),
        Line(language: "de", original: "Könnten Sie das wiederholen?", english: "Could you repeat that?"),
        Line(language: "es", original: "Claro, no hay problema.", english: "Of course, no problem."),
    ]
    /// Seconds between two demo rows: long enough to read one before the next slides in.
    static let rowInterval: TimeInterval = 1.4
    static let transcriptEmptyText = "Tap Start to hear a short conversation."
    static let speakingText = "Speaking the translation aloud"
```

with

```swift
    /// A scripted conversation for the transcript demo, one row at a time. The last line is a guess (M11 §3):
    /// `LiveTranscriptRowView` greys it and marks it Unsure exactly as on Live.
    struct Line: Equatable, Sendable {
        let language: String
        let original: String
        let english: String
        var isGuess = false
    }

    static let transcriptScript: [Line] = [
        Line(language: "es", original: "Buenos días, ¿cómo estás?", english: "Good morning, how are you?"),
        Line(language: "fr", original: "Le train part à neuf heures.", english: "The train leaves at nine."),
        Line(language: "de", original: "Könnten Sie das wiederholen?", english: "Could you repeat that?"),
        Line(language: "es", original: "Claro, no hay problema.", english: "Of course, no problem."),
        Line(language: "pt", original: "Até logo, então.", english: "See you later, then.", isGuess: true),
    ]
    /// Seconds between two demo rows: long enough to read one before the next slides in.
    static let rowInterval: TimeInterval = 1.4
    static let transcriptEmptyText = "Tap Start to hear a short conversation."
    static let speakingText = "Speaking the translation aloud"
    /// Under the rows once the guess has arrived, and after Stop while the greyed row is still there.
    static let guessText = "The greyed phrase is marked Unsure: ReVox was not sure of it, so it is kept but not spoken."
```

- [ ] **Implement: the view model.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift`:

Replace L12-13

```swift
    /// Bump when the tutorial changes enough that someone who finished the old one should see the new one.
    static let version = 1
```

with

```swift
    /// Bump when the tutorial changes enough that someone who finished the old one should see the new one.
    /// 2: M11 §6, the pages host the real Live controls.
    static let version = 2
```

Replace (after Task 1) the lines

```swift
    let controls: OnboardingLiveControls
    var demoSource: CaptureMode = .microphone
    var demoTwoWay = false
    var demoLearning = false
    var demoRomanize = false
```

with

```swift
    let controls: OnboardingLiveControls
    /// The strip's per-launch states, which `LiveView` keeps in `@State`: here so `reset()` folds them and a
    /// test can render both.
    var demoShowsDetails = false
    var demoShowsVolumeSlider = false
    var demoSource: CaptureMode = .microphone
    var demoTwoWay = false
    var demoLearning = false
    var demoRomanize = false
```

(`demoSource`, `demoTwoWay`, `demoLearning` stay until Task 4 removes their last readers in `OnboardingView.swift`, so every commit compiles.)

Replace `complete()` (today's L71-75)

```swift
    private func complete() {
        defaults.set(Self.version, forKey: Self.storageKey)
        stopDemo()
        shouldShowNow = false
    }
```

with

```swift
    private func complete() {
        defaults.set(Self.version, forKey: Self.storageKey)
        stopDemo()
        controls.stop()
        shouldShowNow = false
    }
```

Replace `reset()` (today's L78-89)

```swift
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        currentIndex = 0
        stopDemo()
        demoSource = .microphone
        demoTwoWay = false
        demoLearning = false
        demoRomanize = false
        demoModel = OnboardingDemo.recommendedModel
        demoKeepModelWhenHot = false
        shouldShowNow = true
    }
```

with

```swift
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        currentIndex = 0
        stopDemo()
        controls.reset()
        demoShowsDetails = false
        demoShowsVolumeSlider = false
        demoSource = .microphone
        demoTwoWay = false
        demoLearning = false
        demoRomanize = false
        demoModel = OnboardingDemo.recommendedModel
        demoKeepModelWhenHot = false
        shouldShowNow = true
    }
```

Replace L115-125

```swift
    var isDemoComplete: Bool { demoRows.count >= OnboardingDemo.transcriptScript.count }

    /// The next scripted row, stamped `now`; false when the script is spent. Public so a test — or a
    /// screenshot — can play the demo through without waiting.
    @discardableResult
    func appendNextDemoRow(now: Date = Date()) -> Bool {
        guard demoRows.count < OnboardingDemo.transcriptScript.count else { return false }
        let line = OnboardingDemo.transcriptScript[demoRows.count]
        demoRows.append(LiveTranscriptRow(time: now, kind: .entry(language: line.language, original: line.original, english: line.english)))
        return true
    }
```

with

```swift
    var isDemoComplete: Bool { demoRows.count >= OnboardingDemo.transcriptScript.count }
    /// The last row on screen is the script's guess: the caption under the rows explains the greying.
    var lastDemoRowIsGuess: Bool { demoRows.last?.isGuess ?? false }

    /// The next scripted row, stamped `now`; false when the script is spent. Public so a test — or a
    /// screenshot — can play the demo through without waiting.
    @discardableResult
    func appendNextDemoRow(now: Date = Date()) -> Bool {
        guard demoRows.count < OnboardingDemo.transcriptScript.count else { return false }
        let line = OnboardingDemo.transcriptScript[demoRows.count]
        demoRows.append(LiveTranscriptRow(time: now, kind: .entry(language: line.language, original: line.original, english: line.english),
                                          isGuess: line.isGuess))
        return true
    }
```

- [ ] **Run.** `cd /home/user/ReVoxMobile && for f in ReVoxMobile/Screens/Onboarding/OnboardingPage.swift ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift ReVoxMobileTests/OnboardingTests.swift; do /home/user/swift/usr/bin/swiftc -parse $f || exit 1; done && python3 scripts/dev/check-core-imports.py --all`

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Onboarding ReVoxMobileTests/OnboardingTests.swift && git commit -m "feat(tutorial): version 2, the strip's per-launch states on the model, and a guess at the end of the script

Everyone who finished the M10 tutorial sees the refreshed one once. The details panel and
volume slider states live on OnboardingViewModel so reset() folds them; the fifth scripted
line is a Portuguese guess, carried as LiveTranscriptRow.isGuess.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 3: One Start/Stop capsule for both pages, the guess caption, and the demos pad themselves

- [ ] **Write the failing tests.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift` insert after `testFinishStopsTheDemo`:

```swift
    func testTheTranscriptCaptionExplainsTheGuessWhileItIsOnScreen() {
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: false, lastIsGuess: false), LiveView.microphoneDescription)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: true, lastIsGuess: false), OnboardingDemo.speakingText)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: true, lastIsGuess: true), OnboardingDemo.guessText)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: false, lastIsGuess: true), OnboardingDemo.guessText, "after Stop the grey row is still there")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: true, lastIsGuess: true), "questionmark.circle")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: true, lastIsGuess: false), "speaker.wave.2")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: false, lastIsGuess: false), "speaker.wave.2")
    }
```

In `testCopyBehindTheDemos` replace L171-172

```swift
        XCTAssertEqual(OnboardingTranscriptDemo.buttonTitle(playing: false), "Start")
        XCTAssertEqual(OnboardingTranscriptDemo.buttonTitle(playing: true), "Stop")
```

with

```swift
        XCTAssertEqual(OnboardingStartStopButton.title(running: false), "Start")
        XCTAssertEqual(OnboardingStartStopButton.title(running: true), "Stop")
        XCTAssertEqual(OnboardingStartStopButton.title(running: false), LiveView.buttonTitle(for: .idle))
        XCTAssertEqual(OnboardingStartStopButton.title(running: true), LiveView.buttonTitle(for: .running))
```

In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingHostingTests.swift` replace `testProgressBarAndCardHost` (L81-86)

```swift
    func testProgressBarAndCardHost() {
        host(OnboardingProgressBar(progress: 0.5, step: 4, count: 7).frame(width: 300))
        host(OnboardingProgressBar(progress: 1, step: 7, count: 7).frame(width: 300))
        host(OnboardingDemoCard { Text("card") })
        host(OnboardingPointsList(points: OnboardingDemo.welcomePoints))
    }
```

with

```swift
    func testProgressBarCardAndPiecesHost() {
        host(OnboardingProgressBar(progress: 0.5, step: 4, count: 7).frame(width: 300))
        host(OnboardingProgressBar(progress: 1, step: 7, count: 7).frame(width: 300))
        host(OnboardingDemoCard { Text("card") })
        host(OnboardingPointsList(points: OnboardingDemo.welcomePoints))
        host(OnboardingStartStopButton(isRunning: false, accessibilityLabel: "x", accessibilityHint: "y") {})
        host(OnboardingStartStopButton(isRunning: true, accessibilityLabel: "x", accessibilityHint: "y") {})
        let controls = OnboardingLiveControls()
        host(LiveLanguagesGroup(model: controls))
        host(LiveControlStrip(model: controls, showsVolumeSlider: .constant(true), isMoreExpanded: .constant(true)))
        host(LiveDetailsPanel(model: controls))
    }
```

and in `testTranscriptDemoHostsEmptyPlayingAndStopped` replace L74-77

```swift
        while model.appendNextDemoRow() {}
        host(OnboardingPageView(page: .transcript, index: 2, count: model.pages.count, model: model))   // the whole script
        model.stopDemo()
        host(OnboardingView(model: model))                                   // stopped, rows kept
```

with

```swift
        while model.appendNextDemoRow() {}
        XCTAssertTrue(model.lastDemoRowIsGuess, "the script ends with the greyed Unsure row")
        host(OnboardingPageView(page: .transcript, index: 2, count: model.pages.count, model: model))   // the whole script, guess caption
        model.stopDemo()
        host(OnboardingView(model: model))                                   // stopped, rows kept, caption still the guess
```

- [ ] **Run it.** `cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingTests.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingHostingTests.swift` (red on CI: `OnboardingStartStopButton`, `captionText`, `captionSymbol` do not exist).

- [ ] **Implement: the page column and the card.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingView.swift` replace L208-231

```swift
/// One page: the title (a heading to VoiceOver), one sentence, and the demo. Scrolls when Dynamic Type asks.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let count: Int
    @Bindable var model: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                demo
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
```

with

```swift
/// One page: the title (a heading to VoiceOver), one sentence, and the demo. Scrolls when Dynamic Type asks.
/// The column itself is not padded: the title and sentence take 20 pt each, and every demo pads itself, so the
/// strip and the Languages group get the same width they have on Live (393 − 2 × 16) and pack identically.
struct OnboardingPageView: View {
    let page: OnboardingPage
    let index: Int
    let count: Int
    @Bindable var model: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                demo
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
```

Replace L271-287 (`OnboardingDemoCard`)

```swift
/// The card every demo sits in: the Live screen's card, so the tutorial looks like the app it is about.
struct OnboardingDemoCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
```

with

```swift
/// The card every demo sits in: the Live screen's card, so the tutorial looks like the app it is about. It
/// carries the page's 20 pt side margin itself (see `OnboardingPageView`).
struct OnboardingDemoCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }
}
```

- [ ] **Implement: the shared capsule.** Insert after the closing brace of `OnboardingPointsList` (today's L323) and before `// MARK: - Choose a source`:

```swift
/// The Live screen's Start / Stop capsule, shared by the controls page and the transcript demo: the same words
/// `LiveView.buttonTitle(for:)` gives the real one, red while running. No side margin of its own — the caller
/// places it (inside a card, or at the page's 20 pt).
struct OnboardingStartStopButton: View {
    let isRunning: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    static func title(running: Bool) -> String {
        LiveView.buttonTitle(for: running ? .running : .idle)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? "stop.fill" : "mic.fill")
                    .accessibilityHidden(true)
                Text(Self.title(running: isRunning))
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(isRunning ? .red : .accentColor)
        .animation(.default, value: isRunning)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
```

- [ ] **Implement: the transcript demo.** Replace the whole `OnboardingTranscriptDemo` (today's L373-444, from the doc comment `/// The Live screen in miniature: …` through the struct's closing `}`, which ends with `private var rowAnimation: Animation { … }`) with:

```swift
// MARK: - Start and read

/// The Live screen in miniature: a transcript whose rows slide in one by one, ages counting up under them, and
/// the same capsule that starts and stops the real thing. The script ends with a guess, which the row view greys
/// and marks Unsure (M11 §3); the caption under the rows says so for as long as the greyed row is there.
struct OnboardingTranscriptDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let startAccessibilityLabel = "Start the demo"
    static let stopAccessibilityLabel = "Stop the demo"
    static let hintText = "A short conversation appears in the transcript, one phrase at a time"

    /// The guess explanation whenever the greyed row is on screen, even after Stop; otherwise what Live says.
    static func captionText(playing: Bool, lastIsGuess: Bool) -> String {
        if lastIsGuess { return OnboardingDemo.guessText }
        return playing ? OnboardingDemo.speakingText : LiveView.microphoneDescription
    }

    static func captionSymbol(playing: Bool, lastIsGuess: Bool) -> String {
        lastIsGuess ? "questionmark.circle" : "speaker.wave.2"
    }

    var body: some View {
        OnboardingDemoCard {
            // Ticks every second only while the demo runs, like the Live screen with ages on.
            TimelineView(.periodic(from: .now, by: model.isDemoPlaying ? 1 : 3_600)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if model.demoRows.isEmpty {
                        Label(OnboardingDemo.transcriptEmptyText, systemImage: "waveform.and.mic")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                    ForEach(model.demoRows) { row in
                        LiveTranscriptRowView(row: row, now: context.date, timeDisplay: .age)
                            .transition(rowTransition)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .animation(rowAnimation, value: model.demoRows)
            }
            HStack(spacing: 6) {
                Image(systemName: Self.captionSymbol(playing: model.isDemoPlaying, lastIsGuess: model.lastDemoRowIsGuess))
                    .symbolEffect(.variableColor.iterative, isActive: model.isDemoPlaying && !model.lastDemoRowIsGuess && !reduceMotion)
                    .accessibilityHidden(true)
                Text(Self.captionText(playing: model.isDemoPlaying, lastIsGuess: model.lastDemoRowIsGuess))
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .animation(.default, value: model.isDemoPlaying)
            .animation(.default, value: model.lastDemoRowIsGuess)
            OnboardingStartStopButton(isRunning: model.isDemoPlaying,
                                      accessibilityLabel: model.isDemoPlaying ? Self.stopAccessibilityLabel : Self.startAccessibilityLabel,
                                      accessibilityHint: Self.hintText) {
                if model.isDemoPlaying {
                    model.stopDemo()
                } else {
                    model.startDemo()
                }
            }
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var rowAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.25)
    }
}
```

(Today's `// MARK: - Start and read` line at L373 is included in the replaced range; the replacement re-emits it. `OnboardingTranscriptDemo.buttonTitle(playing:)` is gone; its only reader was the test line replaced above.)

- [ ] **Run.** `cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/Onboarding/OnboardingView.swift && grep -rn "buttonTitle(playing" ReVoxMobile ReVoxMobileTests --include=*.swift` (the grep must print nothing).

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Onboarding/OnboardingView.swift ReVoxMobileTests/OnboardingTests.swift ReVoxMobileTests/OnboardingHostingTests.swift && git commit -m "feat(tutorial): one Start/Stop capsule for both pages, the guess caption, and the demos pad themselves

OnboardingStartStopButton takes its words from LiveView.buttonTitle(for:); the transcript
caption explains the greyed Unsure row for as long as it is on screen; the page column no
longer pads the demos, so the real strip packs at the width it has on Live.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 4: The pages host the real strip, panel and Languages group

- [ ] **Write the failing tests.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingTests.swift` replace `testPagesAreTheSevenInOrder` (L21-34) with:

```swift
    func testPagesAreTheSevenInOrder() {
        let model = OnboardingViewModel(defaults: defaults)
        XCTAssertEqual(model.pages, [.welcome, .controls, .transcript, .twoWay, .learning, .models, .ready])
        XCTAssertEqual(OnboardingPage.ordered, OnboardingPage.allCases)
        XCTAssertEqual(OnboardingPage.controls.title, "The Live controls")
        XCTAssertEqual(OnboardingPage.controls.symbol, "slider.horizontal.3")
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertEqual(model.page, .welcome)
        XCTAssertTrue(model.isFirstPage)
        XCTAssertFalse(model.isLastPage)
        for page in OnboardingPage.allCases {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.subtitle.isEmpty)
            XCTAssertFalse(page.symbol.isEmpty)
        }
    }
```

In `testCopyBehindTheDemos` replace the line `XCTAssertEqual(OnboardingDemo.recommendedModel, .small)` with:

```swift
        XCTAssertEqual(OnboardingDemo.recommendedModel, ModelCatalog.defaultWhisperModel)
        XCTAssertEqual(OnboardingDemo.benchmarkText, "Settings › Models › Benchmark this iPhone measures them on your iPhone.")
        XCTAssertEqual(OnboardingDemo.wordTapText, "Tap any word for its pronunciation and meaning.")
        XCTAssertEqual(OnboardingControlsDemo.tipText,
                       "The volume applies at once; everything else is read when a session starts. This Start is a demo — nothing is recorded.")
        XCTAssertEqual(OnboardingControlsDemo.startAccessibilityLabel, "Start a demo session")
        XCTAssertEqual(OnboardingControlsDemo.stopAccessibilityLabel, "Stop the demo session")
```

Insert after `testCopyBehindTheDemos`'s closing brace and before `testAppEnvironmentOwnsTheTutorial`:

```swift
    func testTheTwoWayFootnotesFollowThePills() {
        XCTAssertEqual(OnboardingDemo.twoWayOnText(you: "en", they: "es"),
                       "What you say in English is spoken to them in Spanish, and what they say is spoken to you in English. Both sides stay in the transcript.")
        XCTAssertEqual(OnboardingDemo.twoWayOnText(you: "fr", they: "de"),
                       "What you say in French is spoken to them in German, and what they say is spoken to you in English. Both sides stay in the transcript.")
        XCTAssertEqual(OnboardingDemo.twoWayOnText(you: nil, they: "es"), LiveView.twoWaySummary(you: nil, they: "es"), "nothing chosen: Live's own line")
        XCTAssertEqual(OnboardingDemo.twoWayOnText(you: "en", they: "en"), LiveView.twoWaySummary(you: "en", they: "en"), "both the same: Live's own line")
        XCTAssertEqual(OnboardingDemo.twoWayOffText(you: "en"),
                       "\(LiveView.twoWayOffSummary(you: "en")) Turn on Two-way to answer them in their language.")
        XCTAssertTrue(OnboardingDemo.twoWayOffText(you: "en").hasPrefix(LiveView.twoWayOffSummary(you: "en")))
        XCTAssertTrue(OnboardingDemo.twoWayOffText(you: nil).hasPrefix(LiveView.twoWayOffSummary(you: nil)))
        XCTAssertTrue(OnboardingDemo.twoWayOffText(you: nil).contains(LiveControlStrip.twoWayPillName))
        // The default demo state (You speak English, They speak Spanish) reads consistently with the page's subtitle.
        let controls = OnboardingLiveControls()
        XCTAssertEqual(OnboardingDemo.twoWayOffText(you: controls.ignoredLanguage),
                       "Two-way is off: English is not translated and not spoken back at you; everything else is spoken to you in English. Turn on Two-way to answer them in their language.")
    }

    /// M11 §6: where a page names a control it reads the strip's static, so a rename on Live reaches the tutorial.
    func testTheTutorialNamesTheStripsControls() {
        XCTAssertTrue(OnboardingPage.controls.subtitle.contains(LiveControlStrip.listenCaption))
        XCTAssertTrue(OnboardingPage.controls.subtitle.contains(LiveControlStrip.voiceCaption))
        XCTAssertTrue(OnboardingPage.controls.subtitle.contains(LiveControlStrip.languagesCaption))
        XCTAssertTrue(OnboardingPage.controls.subtitle.contains(LiveControlStrip.moreAccessibilityLabel))
        XCTAssertTrue(OnboardingPage.twoWay.subtitle.contains(LiveControlStrip.twoWayPillName))
        XCTAssertEqual(OnboardingPage.twoWay.subtitle,
                       "In a conversation ReVox should not echo your own language back at you; it should say what you say to the other person in theirs. Tell it what you speak and what they speak, then turn on Two-way to see both directions.")
        XCTAssertTrue(OnboardingPage.learning.subtitle.contains(LiveControlStrip.learningPillName))
        XCTAssertTrue(OnboardingPage.learning.subtitle.hasSuffix(OnboardingDemo.wordTapText))
        XCTAssertTrue(OnboardingControlsDemo.lockedTipText.contains(LiveControlStrip.lockedText))
        XCTAssertTrue(OnboardingDemo.twoWayOffText(you: "en").contains(LiveControlStrip.twoWayPillName))
        let everyString = OnboardingPage.allCases.map(\.subtitle) + OnboardingPage.allCases.map(\.title) + [
            OnboardingDemo.privacyText, OnboardingDemo.readyFootnote, OnboardingDemo.transcriptEmptyText, OnboardingDemo.speakingText,
            OnboardingDemo.guessText, OnboardingDemo.bothSidesText, OnboardingDemo.wordTapText, OnboardingDemo.benchmarkText,
            OnboardingDemo.systemVoiceText, OnboardingDemo.pocketVoiceText,
            OnboardingDemo.twoWayOnText(you: "en", they: "es"), OnboardingDemo.twoWayOnText(you: nil, they: "es"),
            OnboardingDemo.twoWayOffText(you: "en"), OnboardingDemo.twoWayOffText(you: nil),
            OnboardingControlsDemo.tipText, OnboardingControlsDemo.lockedTipText, OnboardingControlsDemo.startHint, OnboardingControlsDemo.stopHint,
            OnboardingTranscriptDemo.hintText,
        ] + OnboardingDemo.welcomePoints.map(\.text) + OnboardingDemo.readyPoints.map(\.text) + WhisperModelID.allCases.map(OnboardingDemo.modelNote)
        for text in everyString {
            for banned in ["left alone", "Reply in", "Don't translate", "Skip a language", "ignored"] {
                XCTAssertFalse(text.contains(banned), "\(banned) in: \(text)")
            }
        }
    }
```

In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingHostingTests.swift` replace `testEveryPageHostsAloneInBothDemoStates` (L42-63) with:

```swift
    func testEveryPageHostsAloneInBothDemoStates() {
        let model = OnboardingViewModel(defaults: defaults)
        let count = model.pages.count
        for (index, page) in model.pages.enumerated() {
            host(OnboardingPageView(page: page, index: index, count: count, model: model))
        }
        // Every demo switched on: the strip with Other apps, Very fast, Duck off, a low volume, Two-way and Learn on
        // (the pair line shows), the details panel unfolded and the slider out.
        model.controls.captureMode = .broadcast
        model.controls.latencyMode = .veryFast
        model.controls.ducking = false
        model.controls.voiceVolume = 0.3
        model.controls.isTwoWay = true
        model.controls.isLearning = true
        model.demoShowsDetails = true
        model.demoShowsVolumeSlider = true
        model.demoRomanize = true
        model.demoModel = .largeV3
        model.demoKeepModelWhenHot = true
        for (index, page) in model.pages.enumerated() {
            host(OnboardingPageView(page: page, index: index, count: count, model: model))
        }
        // Every model chip selected in turn.
        for id in WhisperModelID.allCases {
            model.demoModel = id
            host(OnboardingPageView(page: .models, index: 5, count: count, model: model))
        }
        model.reset()
        XCTAssertFalse(model.controls.isTwoWay, "reset between passes: the demo model is shared")
    }
```

- [ ] **Run it.** `cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingTests.swift && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingHostingTests.swift` (red on CI: `.controls`, `twoWayOnText(you:they:)`, `OnboardingControlsDemo`, `bothSidesText`, `wordTapText`, `benchmarkText` do not exist; `demoTwoWay` is still read by the view).

- [ ] **Implement: the pages and copy.** Replace the whole of `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingPage.swift` with the file below. What changes from today's file: the header comment (L4-6); `case welcome, source, …` → `case welcome, controls, …` (L8); `"Choose a source"` → `"The Live controls"` (L18); the `.source`, `.twoWay`, `.learning` subtitles (L31-38) become `.controls`, `.twoWay`, `.learning` built from the strip's statics; `"dot.radiowaves.left.and.right"` → `"slider.horizontal.3"` (L49); `twoWayOffText` / `twoWayOnText` constants (L109-110: `"With Two-way off, what you say is translated into English too — and echoed back at you."` and `"English is left alone and spoken back in Spanish. Both sides stay in the transcript."`) become the two functions; `recommendedModel: WhisperModelID = .small` (L129) becomes `ModelCatalog.defaultWhisperModel`; `bothSidesText`, `wordTapText`, `benchmarkText` are new; everything from Task 2 is kept.

```swift
import Foundation
import ReVoxCore

/// The first-run tutorial's pages (M10, refreshed in M11 §6), in the order they are shown. Each page is a title,
/// one sentence under it, the symbol the hero morphs into, and — on the view side — a demo the reader can tap:
/// the real Live control strip, the real Languages group and the real transcript rows over a demo model, so what
/// the tutorial shows is what the app does and nothing can drift.
enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, controls, transcript, twoWay, learning, models, ready

    var id: Int { rawValue }

    /// The pages in the order the tutorial walks through them.
    static let ordered: [OnboardingPage] = allCases

    var title: String {
        switch self {
        case .welcome: return "Welcome to ReVox"
        case .controls: return "The Live controls"
        case .transcript: return "Start and read"
        case .twoWay: return "Two-way conversation"
        case .learning: return "Learning mode"
        case .models: return "Models and voices"
        case .ready: return "You're ready"
        }
    }

    /// Where a sentence names a control it reads the strip's own static, so a rename on Live shows up here
    /// without an edit (`OnboardingTests.testTheTutorialNamesTheStripsControls`).
    var subtitle: String {
        switch self {
        case .welcome:
            return "ReVox hears speech, translates it into English on this iPhone, speaks the translation and keeps a transcript. Nothing you say or hear leaves the phone."
        case .controls:
            return "Three groups of pills sit above the transcript: \(LiveControlStrip.listenCaption), \(LiveControlStrip.voiceCaption) and \(LiveControlStrip.languagesCaption). A pill says what it is set to — tap it to change it, \(LiveControlStrip.moreAccessibilityLabel) to read what each one does, and Start to see them lock."
        case .transcript:
            return "Tap Start and speak. Each finished phrase appears with its language and its English translation, is spoken aloud, and shows how long ago it was said. A phrase ReVox is not sure about arrives greyed and marked Unsure: kept in the transcript, never spoken."
        case .twoWay:
            return "In a conversation ReVox should not echo your own language back at you; it should say what you say to the other person in theirs. Tell it what you speak and what they speak, then turn on \(LiveControlStrip.twoWayPillName) to see both directions."
        case .learning:
            return "\(LiveControlStrip.learningPillName) shows the words as they were spoken above the translation, so you can follow the other language as well as understand it. \(OnboardingDemo.wordTapText)"
        case .models:
            return "ReVox translates with a Whisper model you download once. Voices are optional; the iPhone's own voice needs no download."
        case .ready:
            return "That is all there is to it. You can show this tutorial again any time from Settings."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "waveform.and.mic"
        case .controls: return "slider.horizontal.3"
        case .transcript: return "text.bubble"
        case .twoWay: return "arrow.left.arrow.right"
        case .learning: return "text.book.closed"
        case .models: return "cpu"
        case .ready: return "checkmark.circle"
        }
    }
}

/// One line of a demo list: a symbol and a sentence.
struct OnboardingPoint: Identifiable, Equatable, Sendable {
    let symbol: String
    let text: String
    var id: String { symbol + text }
}

/// The copy and the scripted rows behind the demos, kept off the views so the tests can read them.
enum OnboardingDemo {
    /// What ReVox does, one line each, revealed one after another on the Welcome page.
    static let welcomePoints: [OnboardingPoint] = [
        OnboardingPoint(symbol: "ear", text: "Hears the microphone, or other apps"),
        OnboardingPoint(symbol: "iphone", text: "Translates on the iPhone itself"),
        OnboardingPoint(symbol: "speaker.wave.2", text: "Speaks the translation aloud"),
        OnboardingPoint(symbol: "clock", text: "Keeps a transcript in History"),
    ]
    static let privacyText = "Nothing leaves the phone."

    /// The recap on the Ready page.
    static let readyPoints: [OnboardingPoint] = [
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Pick a source on the Live tab"),
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Tap Start, then Stop when you are done"),
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Every session is saved to History"),
    ]
    static let readyFootnote = "ReVox needs a Whisper model before the first translation. The Live tab asks you to download one; you can also find it under Settings › Models."

    /// A scripted conversation for the transcript demo, one row at a time. The last line is a guess (M11 §3):
    /// `LiveTranscriptRowView` greys it and marks it Unsure exactly as on Live.
    struct Line: Equatable, Sendable {
        let language: String
        let original: String
        let english: String
        var isGuess = false
    }

    static let transcriptScript: [Line] = [
        Line(language: "es", original: "Buenos días, ¿cómo estás?", english: "Good morning, how are you?"),
        Line(language: "fr", original: "Le train part à neuf heures.", english: "The train leaves at nine."),
        Line(language: "de", original: "Könnten Sie das wiederholen?", english: "Could you repeat that?"),
        Line(language: "es", original: "Claro, no hay problema.", english: "Of course, no problem."),
        Line(language: "pt", original: "Até logo, então.", english: "See you later, then.", isGuess: true),
    ]
    /// Seconds between two demo rows: long enough to read one before the next slides in.
    static let rowInterval: TimeInterval = 1.4
    static let transcriptEmptyText = "Tap Start to hear a short conversation."
    static let speakingText = "Speaking the translation aloud"
    /// Under the rows once the guess has arrived, and after Stop while the greyed row is still there.
    static let guessText = "The greyed phrase is marked Unsure: ReVox was not sure of it, so it is kept but not spoken."

    /// The two-way demo: what they said, translated to English, and your reply, spoken back in Spanish. The
    /// reply row carries the Spanish in its translation column, exactly as the Live screen shows it.
    static let theirLine = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, time: SettingExamples.sampleTime,
                                             kind: .entry(language: "es", original: "¿Nos vemos en la estación?", english: "Shall we meet at the station?"))
    static let yourReply = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, time: SettingExamples.sampleTime.addingTimeInterval(6),
                                             kind: .entry(language: "en", original: "Yes, at nine.", english: "Sí, a las nueve."))
    static let twoWayIgnored = "en"
    static let twoWayTarget = "es"
    static let bothSidesText = "Both sides stay in the transcript."

    /// The card's footnote while Two-way is on, following the pills' languages (M11 §6: "What you say in English is
    /// spoken to them in Spanish, and what they say is spoken to you in English. Both sides stay in the
    /// transcript."). With nothing chosen, or both the same, Live's own line says what is still missing.
    static func twoWayOnText(you: String?, they: String) -> String {
        guard let you, you != they else { return LiveView.twoWaySummary(you: you, they: they) }
        let youName = LanguageCatalog.displayName(you, whenNil: LiveView.noLanguageTitle)
        let theyName = LanguageCatalog.displayName(they, whenNil: LiveView.noLanguageTitle)
        return "What you say in \(youName) is spoken to them in \(theyName), and what they say is spoken to you in English. \(bothSidesText)"
    }

    /// The footnote while Two-way is off: Live's own line, then the invitation.
    static func twoWayOffText(you: String?) -> String {
        "\(LiveView.twoWayOffSummary(you: you)) Turn on \(LiveControlStrip.twoWayPillName) to answer them in their language."
    }

    /// The second sentence of the Learning page (M11 §2): the same words Settings › Learning gains.
    static let wordTapText = "Tap any word for its pronunciation and meaning."

    static func learningText(learning: Bool, romanize: Bool) -> String {
        guard learning else { return SettingExamples.learning(false) }
        return romanize ? SettingExamples.romanize(true) : SettingExamples.learning(true)
    }

    /// One line per model: which to pick, and what it costs.
    static func modelNote(_ id: WhisperModelID) -> String {
        switch id {
        case .tiny: return "The quickest and the roughest. For an older iPhone, or when speed matters more than accuracy."
        case .base: return "Quick, with fewer mistakes than tiny. A good fallback when small runs warm."
        case .small: return "The default, and the right choice for most iPhones: accurate enough, quick enough, cool enough."
        case .medium: return "Noticeably more accurate, noticeably slower, and warm on a long session. Needs a recent iPhone."
        case .largeV3: return "The most accurate, and the slowest and hottest. Only for the newest iPhones, and short sessions."
        }
    }
    /// The chip that says "default": the catalogue's default, so the word stays true whatever the benchmark
    /// (M11 §5) recommends on a given iPhone.
    static let recommendedModel: WhisperModelID = ModelCatalog.defaultWhisperModel
    /// M11 §6: the one line the Models page gains.
    static let benchmarkText = "Settings › Models › Benchmark this iPhone measures them on your iPhone."
    static let systemVoiceText = "The iPhone's own voice — works at once, no download."
    static let pocketVoiceText = "pocket-tts — optional, four natural voices, downloaded once from Settings › Voices."
}
```

- [ ] **Implement: the views.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingView.swift`:

(a) Replace L4-7 (the type's doc comment)

```swift
/// The first-run tutorial (M10): seven pages, each with a demo the reader taps rather than a paragraph they read.
/// Presented as a full-screen cover from the root, so it cannot be swiped away half-read; Skip is always in the
/// corner. Pages slide in from the side they come from and fade; under Reduce Motion they crossfade and nothing
/// bounces. Every control is at least 44 pt tall; every colour is a semantic one, so dark mode needs no work.
```

with

```swift
/// The first-run tutorial (M10, refreshed in M11 §6): seven pages, each with a demo the reader taps rather than a
/// paragraph they read — the Live controls themselves, over a demo model. Presented as a full-screen cover from
/// the root, so it cannot be swiped away half-read; Skip is always in the corner. Pages slide in from the side
/// they come from and fade; under Reduce Motion they crossfade and nothing bounces. Every control is at least
/// 44 pt tall; every colour is a semantic one, so dark mode needs no work.
```

(b) Replace L33 `        .onDisappear { model.stopDemo() }` with

```swift
        .onAppear { model.controls.refreshVoiceNote() }
        .onDisappear { model.stopDemo() }
```

(c) In `OnboardingPageView.demo` replace

```swift
        case .source:
            OnboardingSourceDemo(model: model)
```

with

```swift
        case .controls:
            OnboardingControlsDemo(model: model)
```

(d) Replace the whole `OnboardingSourceDemo` block — from the line `// MARK: - Choose a source` (today's L325) through the struct's closing `}` (L371, after `private var symbolTransition`; today's static reads `static let tipText = "The source is read once, at Start. Stop and start again to change it."`) — with:

```swift
// MARK: - The Live controls

/// The Live strip itself over the demo model (M11 §6): every pill, menu, the details panel and the volume slider
/// are the real views, so nothing here can drift from Live. Under the strip, the current source's line and a tip;
/// then a Start capsule that locks the pills the way a session does, and Stop that unlocks them.
struct OnboardingControlsDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tipText = "The volume applies at once; everything else is read when a session starts. This Start is a demo — nothing is recorded."
    static let lockedTipText = "A session is running: the dimmed pills say “\(LiveControlStrip.lockedText)” because ReVox read them at Start. Tap Stop to change them."
    static let startAccessibilityLabel = "Start a demo session"
    static let stopAccessibilityLabel = "Stop the demo session"
    static let startHint = "Locks the pills the way a real session does; nothing is recorded"
    static let stopHint = "Unlocks the pills"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveControlStrip(model: model.controls, showsVolumeSlider: $model.demoShowsVolumeSlider, isMoreExpanded: $model.demoShowsDetails)
            if model.demoShowsDetails {
                LiveDetailsPanel(model: model.controls)
            }
            OnboardingDemoCard {
                Label {
                    Text(LiveView.description(for: model.controls.captureMode))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: LiveView.symbol(for: model.controls.captureMode))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(symbolTransition)
                }
                .accessibilityElement(children: .combine)
                Divider()
                Text(model.controls.isRunning ? Self.lockedTipText : Self.tipText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingStartStopButton(isRunning: model.controls.isRunning,
                                      accessibilityLabel: model.controls.isRunning ? Self.stopAccessibilityLabel : Self.startAccessibilityLabel,
                                      accessibilityHint: model.controls.isRunning ? Self.stopHint : Self.startHint) {
                if model.controls.isRunning {
                    model.controls.stop()
                } else {
                    model.controls.start()
                }
            }
            .padding(.horizontal, 20)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.controls.state)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.1), value: model.controls.captureMode)
        .animation(reduceMotion ? nil : .default, value: model.demoShowsDetails)
    }

    private var symbolTransition: ContentTransition {
        if reduceMotion { return .opacity }
        return .symbolEffect(.replace)
    }
}
```

(e) Replace the whole `OnboardingTwoWayDemo` and `OnboardingLearningDemo` blocks — from `// MARK: - Two-way` (today's L446) through `OnboardingLearningDemo`'s closing `}` (L526; the block today contains the bespoke `Toggle(isOn: $model.demoTwoWay)`, the `languageRow(title: "Don't translate", …)` / `languageRow(title: "Reply in", …)` rows, `Toggle("Learning", isOn: $model.demoLearning)` and reads `OnboardingDemo.twoWayOnText` / `twoWayOffText` as constants and `LiveView.twoWaySummary(ignored:target:)`) — with:

```swift
// MARK: - Two-way

/// The real Languages group over the demo model: tap Two-way and the You speak / They speak pills appear beneath
/// it exactly as on Live, the reply row appears under the other person's line, and the footnote says what will be
/// spoken to whom in the languages the pills show.
struct OnboardingTwoWayDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveLanguagesGroup(model: model.controls)
                .padding(.horizontal)
            OnboardingDemoCard {
                LiveTranscriptRowView(row: OnboardingDemo.theirLine)
                if model.controls.isTwoWay {
                    LiveTranscriptRowView(row: OnboardingDemo.yourReply)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
                Text(model.controls.isTwoWay
                     ? OnboardingDemo.twoWayOnText(you: model.controls.ignoredLanguage, they: model.controls.theySpeak)
                     : OnboardingDemo.twoWayOffText(you: model.controls.ignoredLanguage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2), value: model.controls.isTwoWay)
    }
}

// MARK: - Learning

/// The same real group: tap Learn and the example rows show the words as spoken above the translation, through
/// the real row view (so its words are tappable, M11 §2). Romanize has no pill on Live, so the card keeps the
/// Settings-shaped toggle for it.
struct OnboardingLearningDemo: View {
    @Bindable var model: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiveLanguagesGroup(model: model.controls)
                .padding(.horizontal)
            OnboardingDemoCard {
                Toggle("Romanize", isOn: $model.demoRomanize)
                    .frame(minHeight: 44)
                    .disabled(!model.controls.isLearning)
                    .accessibilityHint("Adds how the original sounds in Latin letters")
                Divider()
                LiveTranscriptRowView(row: SettingExamples.sampleRow(original: SettingExamples.spanishOriginal),
                                      showsOriginal: model.controls.isLearning)
                LiveTranscriptRowView(row: SettingExamples.japaneseRow,
                                      showsOriginal: model.controls.isLearning, romanizes: model.controls.isLearning && model.demoRomanize)
                Text(OnboardingDemo.learningText(learning: model.controls.isLearning, romanize: model.demoRomanize))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: model.controls.isLearning)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: model.demoRomanize)
    }
}
```

(f) In `OnboardingModelsDemo` insert after the model-note `Text` (today's L547-551, ending `.fixedSize(horizontal: false, vertical: true)`) and before the first `Divider()`:

```swift
            Label(OnboardingDemo.benchmarkText, systemImage: "stopwatch")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
```

- [ ] **Implement: drop the three imitated demo fields.** In `/home/user/ReVoxMobile/ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift` delete the three lines

```swift
    var demoSource: CaptureMode = .microphone
    var demoTwoWay = false
    var demoLearning = false
```

and, in `reset()`, the three lines

```swift
        demoSource = .microphone
        demoTwoWay = false
        demoLearning = false
```

- [ ] **Run.** `cd /home/user/ReVoxMobile && for f in ReVoxMobile/Screens/Onboarding/*.swift ReVoxMobileTests/OnboardingTests.swift ReVoxMobileTests/OnboardingHostingTests.swift; do /home/user/swift/usr/bin/swiftc -parse $f || exit 1; done && python3 scripts/dev/check-core-imports.py --all && grep -rn "demoSource\|demoTwoWay\|demoLearning\|OnboardingSourceDemo\|twoWaySummary(ignored" ReVoxMobile ReVoxMobileTests --include=*.swift` — the grep must show only `LiveView.swift:361` and `TwoWayLiveTests.swift:104` (L1's forwarding shim and its test, not this lane's files; see Cross-lane needs).

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobile/Screens/Onboarding ReVoxMobileTests/OnboardingTests.swift ReVoxMobileTests/OnboardingHostingTests.swift && git commit -m "feat(tutorial): the pages host the real strip, panel and Languages group over the demo model

\"Choose a source\" becomes \"The Live controls\": the whole strip, the details panel, a demo
Start that locks it. Two-way and Learning render LiveLanguagesGroup; the footnotes follow the
pills through LiveView's summaries; copy that names a control reads the strip's statics; the
Models page points at Benchmark this iPhone.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 5: Every page hosts idle and locked, the pair line's edge states, accessibility sizes

- [ ] **Write the failing tests.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingHostingTests.swift` replace the class doc comment (L7-9)

```swift
/// Hosts the tutorial (M10) in a `UIHostingController` on every page, with every demo in both of its states:
/// SwiftUI has no unit-test renderer, so this proves the views build against the model and do not trap on
/// first layout — the same bar `ScreenHostingTests` holds the other screens to.
```

with

```swift
/// Hosts the tutorial (M10, refreshed in M11 §6) in a `UIHostingController` on every page, with every demo in
/// both of its states — the real Live strip over the demo model included, idle and locked, at the default and
/// an accessibility type size: SwiftUI has no unit-test renderer, so this proves the views build against the
/// model and do not trap on first layout — the same bar `ScreenHostingTests` holds the other screens to.
```

and insert after `testEveryPageHostsAloneInBothDemoStates` (as replaced in Task 4) and before `testTranscriptDemoHostsEmptyPlayingAndStopped`:

```swift
    /// The pair line's edge states inside the tutorial: a language with no voice (the crossed speaker and the
    /// panel's note), You speak unset (the "Choose…" pill and Live's nil footnote), and the caption-above-pills
    /// branch at an accessibility size.
    func testTheLanguagesGroupHostsItsEdgeStatesInsideTheTutorial() {
        let model = OnboardingViewModel(defaults: defaults)
        let count = model.pages.count
        model.controls.isTwoWay = true
        model.demoShowsDetails = true
        model.controls.theySpeak = "zz"
        XCTAssertNotNil(model.controls.twoWayVoiceNote, "no iPhone has a voice for a code that is not a language")
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))
        host(OnboardingPageView(page: .twoWay, index: 3, count: count, model: model))
        model.controls.ignoredLanguage = nil
        host(OnboardingPageView(page: .twoWay, index: 3, count: count, model: model))
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))
        model.reset()
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model).environment(\.dynamicTypeSize, .accessibility3))
        model.controls.isTwoWay = true
        host(OnboardingPageView(page: .twoWay, index: 3, count: count, model: model).environment(\.dynamicTypeSize, .accessibility3))
        host(OnboardingPageView(page: .learning, index: 4, count: count, model: model).environment(\.dynamicTypeSize, .accessibility3))
        model.reset()
    }

    /// M11 §6: the demo Start locks the strip exactly as a session does — dimmed pills, the lock line, the panel's
    /// locked line and the red Stop — and Stop unlocks it.
    func testTheControlsPageLocksOnStartAndUnlocksOnStop() {
        let model = OnboardingViewModel(defaults: defaults)
        let count = model.pages.count
        model.demoShowsDetails = true
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))
        XCTAssertFalse(LiveControlStrip.locksControls(in: model.controls.state))
        model.controls.start()
        XCTAssertTrue(LiveControlStrip.locksControls(in: model.controls.state))
        XCTAssertTrue(model.controls.isRunning)
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))
        host(OnboardingView(model: model))
        model.controls.isTwoWay = true
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))   // locked with the pair line
        model.controls.stop()
        XCTAssertFalse(LiveControlStrip.locksControls(in: model.controls.state))
        host(OnboardingPageView(page: .controls, index: 1, count: count, model: model))
        model.reset()
    }
```

- [ ] **Run it.** `cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingHostingTests.swift && python3 scripts/dev/check-tests-are-discoverable.py` (both tests are inside the `XCTestCase`; everything they call exists after Task 4, so on CI these go green on first run — the hosting itself is the assertion, as in `ScreenHostingTests`).

- [ ] **Implement.** Nothing: the views under test landed in Task 4. If CI reports a trap in `LiveLanguagesGroup` when hosted with `ignoredLanguage = nil`, that is a Live-side issue for the `Choose…` pill (`LiveLanguagesGroup.swift` L56-64) and is a Cross-lane need, not a tutorial edit.

- [ ] **Run.** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/OnboardingHostingTests.swift`

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobileTests/OnboardingHostingTests.swift && git commit -m "test(tutorial): every page hosts idle and locked, the pair line's edge states, accessibility sizes

The controls and two-way pages host with a voiceless language, You speak unset, the demo
session running (dimmed pills, lock line, locked panel line) and at accessibility3; the demo
model is reset between passes because it is shared.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 6: Screenshots of the welcome, controls, transcript and Learning pages

- [ ] **Write the test.** In `/home/user/ReVoxMobile/ReVoxMobileTests/OnboardingScreenshotTests.swift` replace the class doc comment (L7-10)

```swift
/// Renders the tutorial (M10) to PNGs in the same `Documents/screenshots` folder `ScreenshotTests` fills, so
/// the README's pictures of the first run are generated from the real views by CI. The capture is the one
/// `ScreenshotTests.capture` uses — a window attached to the app's scene, the layer tree rendered, the result
/// checked for actual content — and it shares that class's window, colour-count and output-folder helpers.
```

with

```swift
/// Renders the tutorial (M10, refreshed in M11 §6) to PNGs in the same `Documents/screenshots` folder
/// `ScreenshotTests` fills, so the README's pictures of the first run are generated from the real views by CI.
/// The capture is the one `ScreenshotTests.capture` uses — a window attached to the app's scene, the layer tree
/// rendered, the result checked for actual content — and it shares that class's window, colour-count and
/// output-folder helpers.
```

and replace `testCapturesTheWelcomeAndTranscriptPages` (L66-83, the whole method) with:

```swift
    /// The four tutorial pages the README shows: welcome, the Live controls (the real strip, idle, Two-way off,
    /// the panel folded), the transcript mid-conversation with the greyed Unsure row last, and Learning with Learn
    /// and Romanize on.
    func testCapturesTheWelcomeControlsTranscriptAndLearningPages() throws {
        let model = OnboardingViewModel(defaults: defaults)
        // The welcome card's lines land one after another (`OnboardingPointsList.stagger` plus a 0.4 s spring), so
        // this capture waits for the last one; at 0.25 s CI's image showed them mid-fade (run 106).
        try capture("onboarding-welcome", settle: 1.5, OnboardingView(model: model))

        // The Live controls page as the reader first sees it: three captioned rows, the microphone line, Start.
        model.show(.controls)
        XCTAssertFalse(model.controls.isTwoWay)
        XCTAssertFalse(model.demoShowsDetails)
        try capture("onboarding-controls", settle: 0.5, OnboardingView(model: model))

        // The transcript demo mid-conversation: the script played through with the rows a few seconds apart, so
        // the ages read "36 s … now" as they would on the Live screen, the last row is the greyed Unsure guess
        // with its caption under the rows, and the capsule is the red Stop.
        model.show(.transcript)
        model.startDemo()
        let now = Date()
        for (index, _) in OnboardingDemo.transcriptScript.enumerated() {
            let age = Double(OnboardingDemo.transcriptScript.count - 1 - index) * 9
            model.appendNextDemoRow(now: now.addingTimeInterval(-age))
        }
        XCTAssertTrue(model.lastDemoRowIsGuess)
        try capture("onboarding-transcript", OnboardingView(model: model))
        model.stopDemo()

        // Learning with Learn on (the real pill) and Romanize on: the words as spoken above both rows, the Latin
        // form under the Japanese one.
        model.show(.learning)
        model.controls.isLearning = true
        model.demoRomanize = true
        try capture("onboarding-learning", settle: 0.5, OnboardingView(model: model))
        model.reset()
    }
```

- [ ] **Run it.** `cd /home/user/ReVoxMobile && /home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/OnboardingScreenshotTests.swift && bash scripts/ci/check-no-host-time.sh` (`Date()` here is the same use the existing capture makes; the host-time gate scans for the forbidden host APIs, not `Date()`).

- [ ] **Implement.** Nothing in the app target. `scripts/ci/collect-screenshots.sh` copies every PNG in `Documents/screenshots`, so `onboarding-controls.png` and `onboarding-learning.png` arrive in the CI artifact alongside the two existing names with no script change. Committing the PNGs into `docs/screenshots/` and the README cells happen after the first green run (Cross-lane needs: README is L7's; the PNG commit is the milestone's "screenshots refreshed from the artifact" step).

- [ ] **Run.** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/OnboardingScreenshotTests.swift`

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add ReVoxMobileTests/OnboardingScreenshotTests.swift && git commit -m "test(tutorial): screenshots of the welcome, controls, transcript and Learning pages

onboarding-controls.png is the real strip idle with Two-way off; onboarding-transcript.png now
ends with the greyed Unsure row and its caption; onboarding-learning.png has Learn and Romanize on.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

### Task 7: `docs/onboarding.md`, the gates, the last commit

- [ ] **Rewrite the doc.** Replace the whole of `/home/user/ReVoxMobile/docs/onboarding.md` (today's three paragraphs; L3 describes "Choose a source is the Live screen's Microphone / Other apps control" and "the \"Don't translate / Reply in\" pair explained"; L7 lists `onboarding-welcome.png` / `onboarding-transcript.png`) with:

```markdown
# The first-run tutorial

The first time ReVox opens it shows a short tutorial over the Live tab: seven pages that walk through what the app does, each with a small working demo rather than a paragraph — and since milestone 11 the demos are the Live controls themselves, driven by a demo model, so nothing in the tutorial can drift from the app. **Welcome** says what ReVox is (it hears, translates on the phone, speaks, keeps a transcript — nothing leaves the iPhone). **The Live controls** is the Live strip itself — the Listen, Voice and Languages rows of pills — so every pill, menu, the Details panel and the volume slider work exactly as on the Live tab without changing a setting; under it, the current source's line and a tip, and a Start capsule that locks the pills the way a session does, with the "Stop to change" line beneath them and the panel's locked line; Stop unlocks them. **Start and read** is a miniature transcript: tap Start and a scripted conversation arrives one phrase at a time, with the language badge, the English translation and the age counting up; the last phrase arrives greyed and marked Unsure, and a line under the rows says it is kept but not spoken. **Two-way conversation** shows the real Languages group: turn on Two-way and the You speak / They speak pills appear, the Spanish reply appears under the other person's line, and the footnote says what will be spoken to whom in the languages the pills show. **Learning mode** uses the same group: tap Learn and the original line appears above the translation in both example rows (its words tappable, as on Live), and the Romanize toggle adds the Latin form under the Japanese one. **Models and voices** lets you tap through the five Whisper models and reads what each costs, says that voices are optional, points to Settings › Models › Benchmark this iPhone, and shows what Keep my model when hot does. **You're ready** recaps the three steps; Start translating closes the tutorial. Skip is in the top corner throughout, Back and Next at the bottom, and a swipe turns the page. Under Reduce Motion the pages crossfade and nothing bounces; every page is one VoiceOver unit with a heading, and the strip's rows are the same VoiceOver containers with headings they are on Live.

To see it again, go to **Settings** and tap **Show the tutorial** in the last group, under About. That forgets the completion and presents the tutorial from the first page with the demos reset — the demo strip back to Mic, Balanced, Duck on, full volume, Two-way and Learn off, You speak English, They speak Spanish.

Completion is one integer in `UserDefaults.standard`, key `onboarding_completed_version`: the version of the tutorial that was finished or skipped. The constant is `OnboardingViewModel.version` in `ReVoxMobile/Screens/Onboarding/OnboardingViewModel.swift`; it is 2 since milestone 11, so everyone who finished or skipped the milestone 10 tutorial sees the refreshed one once. Bump it when the tutorial changes enough that someone who finished the old one should see the new one; a stored version lower than the constant shows the tutorial at the next launch, a higher one (a downgrade) does not. The pages and their copy live in `OnboardingPage.swift` (where a sentence names a control it reads the strip's own static), the demo strip model in `OnboardingLiveControls.swift`, the screens in `OnboardingView.swift`, and `OnboardingTests`, `OnboardingHostingTests` and `OnboardingScreenshotTests` cover the model, every page in both demo states (idle and locked, at the default and an accessibility type size), and the `onboarding-welcome.png` / `onboarding-controls.png` / `onboarding-transcript.png` / `onboarding-learning.png` screenshots CI collects with the others.
```

- [ ] **Run every gate.**

```
cd /home/user/ReVoxMobile && for f in ReVoxMobile/Screens/Onboarding/*.swift ReVoxMobileTests/OnboardingTests.swift ReVoxMobileTests/OnboardingHostingTests.swift ReVoxMobileTests/OnboardingScreenshotTests.swift; do /home/user/swift/usr/bin/swiftc -parse $f || exit 1; done && python3 scripts/dev/check-core-imports.py --all && python3 scripts/dev/check-test-autoclosures.py && python3 scripts/dev/check-tests-are-discoverable.py && bash scripts/ci/check-constant-coverage.sh && bash scripts/ci/check-no-host-time.sh && grep -rniE "claude|anthropic|gpt|openai|gemini|copilot" ReVoxMobile/Screens/Onboarding docs/onboarding.md ReVoxMobileTests/Onboarding*.swift; echo "name grep exit $? (1 = clean)"
```

Expected: every parse silent, `core imports verified`, `no await inside an XCTest autoclosure`, `every test method is inside an XCTestCase`, `All … ported constants are asserted`, `No host-time API`, and the name grep printing nothing (exit 1). Also `grep -rn "left alone\|Reply in\|Don't translate\|Skip a language" ReVoxMobile/Screens/Onboarding docs/onboarding.md` must print nothing.

- [ ] **Commit.**

```
cd /home/user/ReVoxMobile && git add docs/onboarding.md && git commit -m "docs(tutorial): docs/onboarding.md describes the seven refreshed pages

The Live controls page, the Unsure row in the transcript demo, the real Languages group on
the Two-way and Learning pages, the benchmark line, version 2, and the four screenshots.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
```

**Cross-lane needs**

- **L5 (`LiveTranscriptRowView.swift`), ordering:** the fifth script line, `guessText`, the transcript caption and `onboarding-transcript.png`'s description all describe greying that the row view does not do today (`LiveTranscriptRowView.swift` L127-135 has no `isGuess` branch). The tutorial compiles either way (the row view takes no new parameter), but the `onboarding-transcript.png` from a CI run must be committed to `docs/screenshots/` only after L5's guess styling is on the branch. Likewise the Learning page's tappable words and `wordTapText` ("Tap any word for its pronunciation and meaning.") rely on L5 wiring `OriginalWordsLine` into the row view behind `showsOriginal` and applying `.environment(\.wordLookup, …)` outermost on `RootView` (spec §2) so the full-screen cover inherits it; no tutorial parameter is needed.
- **L1's shim in `LiveView.swift` L360-363:** `static func twoWaySummary(ignored: String?, target: String?) -> String` is documented "Kept for `OnboardingTwoWayDemo` only: wave 2 (lane L6) hosts `LiveLanguagesGroup` there and deletes this." After Task 4 its last reader is gone; deleting the four lines and the assertion at `ReVoxMobileTests/TwoWayLiveTests.swift` L104-105 (`XCTAssertEqual(LiveView.twoWaySummary(ignored: "en", target: "es"), …, "the tutorial's call site forwards until lane L6 hosts the real group")`) is a two-file edit outside this lane's ownership (`LiveView.swift`, `TwoWayLiveTests`); whoever owns them in wave 2 (or the merge step) should make it.
- **L7 (`README.md`):** L36's tutorial table has an empty third cell and the transcript alt text says "four phrases … \"Speaking the translation aloud\""; L111 says "let you try the source picker". After the first green run: add `docs/screenshots/onboarding-controls.png` and `onboarding-learning.png` cells with alt text ("The tutorial's controls page: \"The Live controls\", the Live strip itself — Listen: Mic, Balanced and Details; Voice: Duck on and 100%; Languages: Two-way off and Learn off — a line about the microphone under it, and a teal Start capsule"; "The tutorial's Learning page: the Languages row with Learn on, a Romanize toggle, two rows showing the words as spoken above the translation and the Latin form under the Japanese one"), change the transcript alt text to "five phrases and their ages, the last greyed and marked Unsure, a note that the greyed phrase is kept but not spoken", and reword L111 to "put the Live controls themselves in your hands — the strip of pills, Two-way, Learning and Romanize — show a demo transcript typing itself in, an Unsure phrase included, and let you tap through the model choice, all without changing a setting". The four PNGs are committed from the CI artifact in the milestone's screenshot step, not by this lane.
- **Optional, `SettingsView.swift` (L5 in wave 2):** the tutorial repeats the literals "Romanize" / "Adds how the original sounds in Latin letters" and "Keep my model when hot" / "Keeps the chosen model through a hot iPhone instead of switching to a smaller one" from `SettingsView.swift` L79-81 and L143-145. If L5 lifts them into `SettingsView.romanizeTitle` / `romanizeHint` / `keepModelWhenHotTitle` / `keepModelWhenHotHint`, `OnboardingLearningDemo` and `OnboardingModelsDemo` should read the statics (a four-line follow-up in `OnboardingView.swift`). Not required by the spec.
