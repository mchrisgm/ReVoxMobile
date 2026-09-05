import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// The first-run tutorial's model (M10): the pages and their order, the bounds of Back and Next, what Skip and
/// Finish persist, and when the tutorial shows again.
@MainActor
final class OnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "OnboardingTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

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

    func testAdvanceAndBackStayInBounds() {
        let model = OnboardingViewModel(defaults: defaults)
        model.back()
        XCTAssertEqual(model.currentIndex, 0, "Back on the first page is a no-op")
        for expected in 1..<model.pages.count {
            model.advance()
            XCTAssertEqual(model.currentIndex, expected)
        }
        XCTAssertTrue(model.isLastPage)
        XCTAssertEqual(model.page, .ready)
        model.advance()
        XCTAssertEqual(model.currentIndex, model.pages.count - 1, "Next on the last page is a no-op")
        model.back()
        XCTAssertEqual(model.page, .models)
        model.show(.transcript)
        XCTAssertEqual(model.currentIndex, 2)
    }

    func testProgressRunsFromOneSeventhToOne() {
        let model = OnboardingViewModel(defaults: defaults)
        XCTAssertEqual(model.progress, 1.0 / 7.0, accuracy: 0.0001)
        model.advance()
        XCTAssertEqual(model.progress, 2.0 / 7.0, accuracy: 0.0001)
        model.show(.ready)
        XCTAssertEqual(model.progress, 1, accuracy: 0.0001)
    }

    func testShowsUntilFinishedAndFinishPersistsTheVersion() {
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults))
        let model = OnboardingViewModel(defaults: defaults)
        XCTAssertTrue(model.shouldShowNow)
        model.show(.ready)
        model.finish()
        XCTAssertFalse(model.shouldShowNow)
        XCTAssertEqual(defaults.integer(forKey: OnboardingViewModel.storageKey), OnboardingViewModel.version)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults))
        XCTAssertFalse(OnboardingViewModel(defaults: defaults).shouldShowNow, "a fresh model at the next launch stays hidden")
    }

    func testSkipPersistsLikeFinish() {
        let model = OnboardingViewModel(defaults: defaults)
        model.advance()
        model.skip()
        XCTAssertFalse(model.shouldShowNow)
        XCTAssertEqual(defaults.integer(forKey: OnboardingViewModel.storageKey), OnboardingViewModel.version)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults))
    }

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

    // MARK: The transcript demo

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

    func testDemoRowsArriveOnTheirOwnWhilePlaying() async {
        let model = OnboardingViewModel(defaults: defaults)
        model.startDemo()
        await waitFor("the first scripted row", timeout: OnboardingDemo.rowInterval * 3) { !model.demoRows.isEmpty }
        XCTAssertEqual(model.demoRows.first?.kind, .entry(language: "es", original: OnboardingDemo.transcriptScript[0].original,
                                                          english: OnboardingDemo.transcriptScript[0].english))
        model.stopDemo()
        let count = model.demoRows.count
        try? await Task.sleep(for: .seconds(OnboardingDemo.rowInterval * 1.5))
        XCTAssertEqual(model.demoRows.count, count, "nothing arrives after Stop")
    }

    func testFinishStopsTheDemo() {
        let model = OnboardingViewModel(defaults: defaults)
        model.show(.transcript)
        model.startDemo()
        model.controls.start()
        model.finish()
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertEqual(model.controls.state, .idle, "the demo session is stopped too")
    }

    func testTheTranscriptCaptionExplainsTheGuessWhileItIsOnScreen() {
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: false, lastIsGuess: false), LiveView.microphoneDescription)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: true, lastIsGuess: false), OnboardingDemo.speakingText)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: true, lastIsGuess: true), OnboardingDemo.guessText)
        XCTAssertEqual(OnboardingTranscriptDemo.captionText(playing: false, lastIsGuess: true), OnboardingDemo.guessText, "after Stop the grey row is still there")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: true, lastIsGuess: true), "questionmark.circle")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: true, lastIsGuess: false), "speaker.wave.2")
        XCTAssertEqual(OnboardingTranscriptDemo.captionSymbol(playing: false, lastIsGuess: false), "speaker.wave.2")
    }

    // MARK: Copy

    func testCopyBehindTheDemos() {
        XCTAssertEqual(OnboardingView.primaryTitle(isLastPage: false), "Next")
        XCTAssertEqual(OnboardingView.primaryTitle(isLastPage: true), "Start translating")
        XCTAssertEqual(OnboardingView.skipTitle, "Skip")
        XCTAssertEqual(OnboardingStartStopButton.title(running: false), "Start")
        XCTAssertEqual(OnboardingStartStopButton.title(running: true), "Stop")
        XCTAssertEqual(OnboardingStartStopButton.title(running: false), LiveView.buttonTitle(for: .idle))
        XCTAssertEqual(OnboardingStartStopButton.title(running: true), LiveView.buttonTitle(for: .running))
        XCTAssertEqual(SettingsView.showTutorialTitle, "Show the tutorial")
        XCTAssertEqual(OnboardingDemo.welcomePoints.count, 4)
        XCTAssertEqual(OnboardingDemo.transcriptScript.count, 5)
        XCTAssertEqual(OnboardingDemo.transcriptScript.filter(\.isGuess).count, 1)
        XCTAssertEqual(OnboardingDemo.transcriptScript.last?.isGuess, true)
        XCTAssertEqual(OnboardingDemo.transcriptScript.last?.language, "pt")
        XCTAssertEqual(OnboardingDemo.guessText, "The greyed phrase is marked Unsure: ReVox was not sure of it, so it is kept but not spoken.")
        XCTAssertEqual(OnboardingDemo.learningText(learning: false, romanize: true), SettingExamples.learning(false))
        XCTAssertEqual(OnboardingDemo.learningText(learning: true, romanize: false), SettingExamples.learning(true))
        XCTAssertEqual(OnboardingDemo.learningText(learning: true, romanize: true), SettingExamples.romanize(true))
        for id in WhisperModelID.allCases {
            XCTAssertFalse(OnboardingDemo.modelNote(id).isEmpty)
        }
        XCTAssertEqual(OnboardingDemo.recommendedModel, ModelCatalog.defaultWhisperModel)
        XCTAssertEqual(OnboardingDemo.benchmarkText, "Settings › Models › Benchmark this iPhone measures them on your iPhone.")
        XCTAssertEqual(OnboardingDemo.wordTapText, "Tap any word for its pronunciation and meaning.")
        XCTAssertEqual(OnboardingControlsDemo.tipText,
                       "The volume applies at once; everything else is read when a session starts. This Start is a demo — nothing is recorded.")
        XCTAssertEqual(OnboardingControlsDemo.startAccessibilityLabel, "Start a demo session")
        XCTAssertEqual(OnboardingControlsDemo.stopAccessibilityLabel, "Stop the demo session")
        if case .entry(let language, _, let english) = OnboardingDemo.yourReply.kind {
            XCTAssertEqual(language, "en")
            XCTAssertEqual(english, "Sí, a las nueve.", "the reply row carries the Spanish, as the Live screen shows it")
        } else {
            XCTFail("the reply is an entry")
        }
    }

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

    func testAppEnvironmentOwnsTheTutorial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxOnboardingEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertEqual(environment.onboarding.pages.count, 7)
        // `testing(root:)` marks the tutorial as seen in a suite of its own, so a screen hosted in a test never
        // presents the first-run cover and the app's own defaults are never read (build 23 failed on a fresh
        // simulator when this asserted equality with `.standard`).
        XCTAssertFalse(environment.onboarding.shouldShowNow, "a test environment never presents the tutorial")
        environment.onboarding.reset()
        XCTAssertTrue(environment.onboarding.shouldShowNow, "reset still brings it back for the Settings button")
    }
}
