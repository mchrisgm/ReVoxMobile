import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// Renders the tutorial (M10, refreshed in M11 §6) to PNGs in the same `Documents/screenshots` and
/// `Documents/store-screenshots` folders `ScreenshotTests` fills, so the README's pictures of the first run and the
/// raw captures behind the App Store set are generated from the real views by CI. The capture is `ScreenCapture`,
/// the one `ScreenshotTests` uses — a window attached to the app's scene, the layer tree rendered, the result checked
/// for actual content at each size.
@MainActor
final class OnboardingScreenshotTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "OnboardingShots-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    @discardableResult
    func capture<V: View>(_ name: String, settle: TimeInterval = 0.25, _ view: V) throws -> URL {
        try ScreenCapture.capture(name, settle: settle, view)
    }

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
}
