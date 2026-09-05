import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// Hosts the tutorial (M10, refreshed in M11 §6) in a `UIHostingController` on every page, with every demo in
/// both of its states — the real Live strip over the demo model included, idle and locked, at the default and
/// an accessibility type size: SwiftUI has no unit-test renderer, so this proves the views build against the
/// model and do not trap on first layout — the same bar `ScreenHostingTests` holds the other screens to.
@MainActor
final class OnboardingHostingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "OnboardingHosting-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    func testEveryPageHostsInTheFullTutorial() {
        let model = OnboardingViewModel(defaults: defaults)
        for page in OnboardingPage.allCases {
            model.show(page)
            host(OnboardingView(model: model))
        }
        XCTAssertTrue(model.isLastPage)
        host(OnboardingView(model: model))            // the Ready page: Skip hidden, "Start translating" primary
        model.stopDemo()
    }

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

    func testTranscriptDemoHostsEmptyPlayingAndStopped() {
        let model = OnboardingViewModel(defaults: defaults)
        model.show(.transcript)
        host(OnboardingView(model: model))                                   // empty, "Tap Start…"
        model.startDemo()
        host(OnboardingView(model: model))                                   // playing, no rows yet
        model.appendNextDemoRow(now: Date().addingTimeInterval(-9))
        model.appendNextDemoRow(now: Date())
        host(OnboardingView(model: model))                                   // playing, two rows with ages
        while model.appendNextDemoRow() {}
        XCTAssertTrue(model.lastDemoRowIsGuess, "the script ends with the greyed Unsure row")
        host(OnboardingPageView(page: .transcript, index: 2, count: model.pages.count, model: model))   // the whole script, guess caption
        model.stopDemo()
        host(OnboardingView(model: model))                                   // stopped, rows kept, caption still the guess
        XCTAssertTrue(model.isDemoComplete)
    }

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

    func testSettingsViewHostsWithTheTutorialRow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxOnboardingSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelLayout(root: root)
        let store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        let support = ScreenHostingSupport(layout: layout, store: store)
        let settingsModel = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        let voices = try support.voices()
        let models = support.models()
        let onboarding = OnboardingViewModel(defaults: defaults)
        onboarding.finish()
        host(NavigationStack {
            SettingsView(model: settingsModel, models: models, voices: voices, onboarding: onboarding)
        })
        onboarding.reset()
        XCTAssertTrue(onboarding.shouldShowNow, "the Settings row resets the model; the root presents the cover")
    }
}
