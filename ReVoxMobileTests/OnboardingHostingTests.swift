import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// Hosts the tutorial (M10) in a `UIHostingController` on every page, with every demo in both of its states:
/// SwiftUI has no unit-test renderer, so this proves the views build against the model and do not trap on
/// first layout — the same bar `ScreenHostingTests` holds the other screens to.
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
        // Every demo switched on.
        model.demoSource = .broadcast
        model.demoTwoWay = true
        model.demoLearning = true
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
        host(OnboardingPageView(page: .transcript, index: 2, count: model.pages.count, model: model))   // the whole script
        model.stopDemo()
        host(OnboardingView(model: model))                                   // stopped, rows kept
        XCTAssertTrue(model.isDemoComplete)
    }

    func testProgressBarAndCardHost() {
        host(OnboardingProgressBar(progress: 0.5, step: 4, count: 7).frame(width: 300))
        host(OnboardingProgressBar(progress: 1, step: 7, count: 7).frame(width: 300))
        host(OnboardingDemoCard { Text("card") })
        host(OnboardingPointsList(points: OnboardingDemo.welcomePoints))
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
