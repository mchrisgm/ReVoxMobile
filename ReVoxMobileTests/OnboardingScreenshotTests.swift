import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// Renders the tutorial (M10, refreshed in M11 §6) to PNGs in the same `Documents/screenshots` folder
/// `ScreenshotTests` fills, so the README's pictures of the first run are generated from the real views by CI.
/// The capture is the one `ScreenshotTests.capture` uses — a window attached to the app's scene, the layer tree
/// rendered, the result checked for actual content — and it shares that class's window, colour-count and
/// output-folder helpers.
@MainActor
final class OnboardingScreenshotTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = try ScreenshotTests.outputDirectory()
        suite = "OnboardingShots-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    @discardableResult
    func capture<V: View>(_ name: String, settle: TimeInterval = 0.25, _ view: V) throws -> URL {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .light
        let window = ScreenshotTests.makeWindow()
        // Detached in a `defer`: a window attached to the app's scene is retained by that scene, and a live
        // SwiftUI hierarchy left over the app keeps doing layout on the main actor for the rest of the run.
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))   // one turn for async text and symbol work

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        if ScreenshotTests.distinctColors(in: image) <= ScreenshotTests.blankThreshold {
            image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }

        let colors = ScreenshotTests.distinctColors(in: image)
        XCTAssertGreaterThan(colors, ScreenshotTests.blankThreshold, "\(name) rendered blank (\(colors) distinct colours)")
        let data = try XCTUnwrap(image.pngData(), "\(name) produced no PNG")
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        return url
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
