import XCTest
import SwiftUI
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

/// Renders each screen to a PNG in the host app's Documents, so the README's screenshots are generated from the
/// real views by CI rather than drawn by hand and left to rot. `scripts/ci/collect-screenshots.sh` copies them
/// out of the simulator container after the test run.
///
/// It is a test, not a UI test, for the same reason `ScreenHostingTests` is one: the screens are built from view
/// models the test can put into an exact state, and no simulator automation is needed to reach it.
@MainActor
final class ScreenshotTests: XCTestCase {
    static let size = CGSize(width: 393, height: 852)      // iPhone 15/16 portrait points

    private var root: URL!
    private var layout: ModelLayout!
    private var store: SettingsStore!
    private var directory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxShots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        directory = try Self.outputDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    static func outputDirectory() throws -> URL {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let directory = documents.appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// One PNG per call. The view is put in a real key window so materials, the navigation bar and the
    /// segmented control render as they do on device; `layer.render(in:)` would flatten them.
    @discardableResult
    func capture<V: View>(_ name: String, _ view: V) throws -> URL {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))   // one turn for async image/text work

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData(), "\(name) produced no PNG")
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        window.isHidden = true
        XCTAssertGreaterThan(data.count, 5_000, "\(name) rendered blank")
        return url
    }

    // MARK: The screens

    func testCapturesEveryScreenInTheReadme() throws {
        let extensionID = "test.revox.broadcast"
        let mute = PlaybackMute()
        let hosting = ScreenHostingSupport(layout: layout, store: store)

        // Live, idle, with the two-way card expanded (§8.2).
        let live = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                 supplier: { _, _ in FakeLivePipeline() })
        live.ignoredLanguage = "en"
        live.isTwoWay = true
        live.twoWayLanguage = "es"
        try capture("live-idle", NavigationStack {
            LiveView(model: live, models: hosting.models(), broadcastExtensionBundleID: extensionID)
        })

        // Live, running, with a translated phrase and a drop marker.
        let pipeline = FakeLivePipeline()
        let running = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                    supplier: { _, _ in pipeline })
        running.isTwoWay = false
        running.handle(.state(.running))
        for (language, english) in Self.sampleTranscript {
            running.handle(.entry(TranscriptEntry(timestamp: Date(), language: language, original: "", english: english)))
        }
        try capture("live-running", NavigationStack {
            LiveView(model: running, models: hosting.models(), broadcastExtensionBundleID: extensionID)
        })

        // Models, Voices, Settings.
        let modelsForVoices = hosting.models()
        let voices = try hosting.voices(installed: true)
        try capture("models", NavigationStack { ModelsView(model: hosting.models()) })
        try capture("voices", NavigationStack { VoicesView(model: voices) })
        let settings = SettingsViewModel(store: store, mute: mute, voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        try capture("settings", NavigationStack {
            SettingsView(model: settings, models: modelsForVoices, voices: voices)
        })
    }

    static let sampleTranscript: [(String, String)] = [
        ("es", "Good morning, thanks for joining us today."),
        ("es", "The first item is the quarterly report."),
        ("en", "Could you share the numbers again?"),
        ("es", "Of course — I'll send them after the call."),
    ]
}
