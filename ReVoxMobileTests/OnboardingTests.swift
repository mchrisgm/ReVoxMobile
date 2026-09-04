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
        XCTAssertEqual(model.pages, [.welcome, .source, .transcript, .twoWay, .learning, .models, .ready])
        XCTAssertEqual(OnboardingPage.ordered, OnboardingPage.allCases)
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
        model.demoSource = .broadcast
        model.demoTwoWay = true
        model.demoLearning = true
        model.demoRomanize = true
        model.demoModel = .largeV3
        model.demoKeepModelWhenHot = true
        model.finish()
        XCTAssertFalse(model.shouldShowNow)
        model.reset()
        XCTAssertTrue(model.shouldShowNow)
        XCTAssertEqual(model.currentIndex, 0)
        XCTAssertNil(defaults.object(forKey: OnboardingViewModel.storageKey))
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults))
        XCTAssertEqual(model.demoSource, .microphone)
        XCTAssertFalse(model.demoTwoWay)
        XCTAssertFalse(model.demoLearning)
        XCTAssertFalse(model.demoRomanize)
        XCTAssertEqual(model.demoModel, .small)
        XCTAssertFalse(model.demoKeepModelWhenHot)
    }

    func testANewerVersionShowsAgainAnOlderOneDoesNot() {
        defaults.set(OnboardingViewModel.version - 1, forKey: OnboardingViewModel.storageKey)
        XCTAssertTrue(OnboardingViewModel.shouldShow(defaults: defaults), "an older completed version means the tutorial changed")
        defaults.set(OnboardingViewModel.version, forKey: OnboardingViewModel.storageKey)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults))
        defaults.set(OnboardingViewModel.version + 1, forKey: OnboardingViewModel.storageKey)
        XCTAssertFalse(OnboardingViewModel.shouldShow(defaults: defaults), "a newer record (a downgrade) does not nag")
    }

    // MARK: The transcript demo

    func testDemoRowsFollowTheScriptAndStopAtItsEnd() {
        let model = OnboardingViewModel(defaults: defaults)
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertTrue(model.demoRows.isEmpty)
        model.startDemo()
        XCTAssertTrue(model.isDemoPlaying)
        let script = OnboardingDemo.transcriptScript
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for (index, line) in script.enumerated() {
            XCTAssertTrue(model.appendNextDemoRow(now: base.addingTimeInterval(Double(index))))
            XCTAssertEqual(model.demoRows.count, index + 1)
            XCTAssertEqual(model.demoRows[index].kind, .entry(language: line.language, original: line.original, english: line.english))
            XCTAssertEqual(model.demoRows[index].time, base.addingTimeInterval(Double(index)))
        }
        XCTAssertTrue(model.isDemoComplete)
        XCTAssertFalse(model.appendNextDemoRow(), "the script is spent")
        XCTAssertEqual(model.demoRows.count, script.count)
        XCTAssertTrue(model.isDemoPlaying, "the demo keeps running so the ages count up, until Stop")
        model.stopDemo()
        XCTAssertFalse(model.isDemoPlaying)
        XCTAssertEqual(model.demoRows.count, script.count, "Stop keeps the transcript, like the Live screen")
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
        model.finish()
        XCTAssertFalse(model.isDemoPlaying)
    }

    // MARK: Copy

    func testCopyBehindTheDemos() {
        XCTAssertEqual(OnboardingView.primaryTitle(isLastPage: false), "Next")
        XCTAssertEqual(OnboardingView.primaryTitle(isLastPage: true), "Start translating")
        XCTAssertEqual(OnboardingView.skipTitle, "Skip")
        XCTAssertEqual(OnboardingTranscriptDemo.buttonTitle(playing: false), "Start")
        XCTAssertEqual(OnboardingTranscriptDemo.buttonTitle(playing: true), "Stop")
        XCTAssertEqual(SettingsView.showTutorialTitle, "Show the tutorial")
        XCTAssertEqual(OnboardingDemo.welcomePoints.count, 4)
        XCTAssertEqual(OnboardingDemo.transcriptScript.count, 4)
        XCTAssertEqual(OnboardingDemo.learningText(learning: false, romanize: true), SettingExamples.learning(false))
        XCTAssertEqual(OnboardingDemo.learningText(learning: true, romanize: false), SettingExamples.learning(true))
        XCTAssertEqual(OnboardingDemo.learningText(learning: true, romanize: true), SettingExamples.romanize(true))
        for id in WhisperModelID.allCases {
            XCTAssertFalse(OnboardingDemo.modelNote(id).isEmpty)
        }
        XCTAssertEqual(OnboardingDemo.recommendedModel, .small)
        if case .entry(let language, _, let english) = OnboardingDemo.yourReply.kind {
            XCTAssertEqual(language, "en")
            XCTAssertEqual(english, "Sí, a las nueve.", "the reply row carries the Spanish, as the Live screen shows it")
        } else {
            XCTFail("the reply is an entry")
        }
    }

    func testAppEnvironmentOwnsTheTutorial() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxOnboardingEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertEqual(environment.onboarding.pages.count, 7)
        XCTAssertEqual(environment.onboarding.shouldShowNow, OnboardingViewModel.shouldShow(defaults: .standard))
    }
}
