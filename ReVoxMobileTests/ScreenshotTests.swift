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

    /// One PNG per call, and a real one: the first version of this shipped five byte-identical white images,
    /// because `drawHierarchy` renders nothing for a window with no scene and a size assertion cannot tell a
    /// blank page from a busy one. The layer tree is rendered instead, the window is attached to the app's own
    /// scene so SwiftUI lays out in a real trait environment, and the result is checked for actual content.
    @discardableResult
    func capture<V: View>(_ name: String, settle: TimeInterval = 0.25, _ view: V) throws -> URL {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .light
        let window = Self.makeWindow()
        // A window attached to the app's scene is retained by that scene: without this, each capture leaves a
        // live SwiftUI hierarchy sitting over the app for the rest of the run, doing layout on the main actor —
        // which is what started timing out the main-actor polls in the LiveViewModel and keep-alive tests.
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
        RunLoop.current.run(until: Date().addingTimeInterval(settle))   // one turn for async text and image work

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 2                                              // @2x: sharp in the README, half the bytes
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        if Self.distinctColors(in: image) <= Self.blankThreshold {
            // A scene-attached window can draw its hierarchy, which catches anything the layer tree misses.
            image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }

        let colors = Self.distinctColors(in: image)
        XCTAssertGreaterThan(colors, Self.blankThreshold, "\(name) rendered blank (\(colors) distinct colours)")
        let data = try XCTUnwrap(image.pngData(), "\(name) produced no PNG")
        let url = directory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        return url
    }

    /// A screen with a navigation bar, a card and text has hundreds; a blank page has one.
    static let blankThreshold = 8

    static func makeWindow() -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes
        let scene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.frame = CGRect(origin: .zero, size: size)
        return window
    }

    /// Distinct colours across a coarse grid — enough to tell a rendered screen from an empty one without
    /// reading every pixel of a two-megapixel image. The image is composited over white first: CI run 117's
    /// `history-selecting` was a transparent page with a few half-transparent white pixels along its edges, and
    /// their alpha values alone counted as forty "colours", so the layer render passed and the fallback never ran.
    static func distinctColors(in image: UIImage, samples: Int = 48) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return 0 }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var seen = Set<UInt32>()
        let stepX = max(1, width / samples), stepY = max(1, height / samples)
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = (y * width + x) * 4
                seen.insert(UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2]))
            }
        }
        return seen.count
    }

    // MARK: The screens

    func testCapturesEveryScreenInTheReadme() throws {
        let extensionID = "test.revox.broadcast"
        let mute = PlaybackMute()
        let hosting = ScreenHostingSupport(layout: layout, store: store)

        // Live, idle: the M10 control strip with two-way on, so its language row is in the picture (§8.2), and the
        // "Ready to translate" placeholder holding the transcript's height.
        let live = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                 supplier: { _, _ in FakeLivePipeline() })
        live.ignoredLanguage = "en"
        live.isTwoWay = true
        live.twoWayLanguage = "es"
        try capture("live-idle", NavigationStack {
            LiveView(model: live, models: hosting.models(), broadcastExtensionBundleID: extensionID)
        })

        // Live, running, with translated phrases: Learning on for the first (original above the translation) and
        // ages rather than times, so the README shows both M9 surfaces on the screen they live on — and (M10) the
        // strip locked behind its one "Stop to change" pill while the transcript takes the rest of the screen.
        let pipeline = FakeLivePipeline()
        let running = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                    supplier: { _, _ in pipeline })
        running.isTwoWay = false
        running.isLearning = true
        running.handle(.state(.running))
        for (index, (language, english)) in Self.sampleTranscript.enumerated() {
            let original = index == 0 ? "Buenos días, gracias por acompañarnos hoy." : ""
            running.handle(.entry(TranscriptEntry(timestamp: Date().addingTimeInterval(Double(index - 4) * 9), language: language,
                                                  original: original, english: english)))
        }
        // M11 §3: a phrase the gates were unsure about — greyed, marked Unsure, never spoken — under the others.
        running.handle(.entry(TranscriptEntry(timestamp: Date().addingTimeInterval(-2), language: "es", original: "",
                                              english: "Could you repeat the last number?", isGuess: true)))
        try capture("live-running", NavigationStack {
            LiveView(model: running, models: hosting.models(), broadcastExtensionBundleID: extensionID)
        })

        // Models, Voices, Settings.
        let modelsForVoices = hosting.models()
        let voices = try hosting.voices(installed: true)
        try capture("models", NavigationStack { ModelsView(model: hosting.models()) })
        try capture("voices", NavigationStack { VoicesView(model: voices) })
        let settings = SettingsViewModel(store: store, mute: mute, voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        settings.learning = true
        try capture("settings", NavigationStack {
            SettingsView(model: settings, models: modelsForVoices, voices: voices)
        })

        // History in edit mode with two sessions selected: the Merge bar (M9).
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        for (index, day) in [0.0, 1.0].enumerated() {
            let session = Session(startedAt: Date().addingTimeInterval(-86_400 * day), endedAt: Date().addingTimeInterval(-86_400 * day + 600),
                                  captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
            context.insert(session)
            let entry = Entry(timestamp: session.startedAt.addingTimeInterval(5), language: "es", original: "",
                              english: Self.sampleTranscript[index].1, isDropMarker: false)
            entry.session = session
            context.insert(entry)
        }
        try context.save()
        let exporter = TranscriptExporter(directory: root.appendingPathComponent("exports", isDirectory: true))
        // M11 (§4): the bar is a safe-area inset over a bar material; a second turn lets the material settle.
        try capture("history-selecting", settle: 1.0, NavigationStack { HistoryView(exporter: exporter, editing: true) }.modelContainer(container))
    }

    /// M11 §2: the popover's content, hosted on its own — a popover with its arrow cannot be captured without a
    /// presentation. Every service is answered, so the image shows the whole thing: pronunciation with a Say
    /// button, a meaning, the dictionary button and the sentence.
    func testCapturesTheLearningWordPopover() async throws {
        let sentence = SettingExamples.spanishOriginal
        let words = WordSplitter.words(in: sentence, language: "es")
        let word = try XCTUnwrap(words.first { $0.text == "estación" })
        let lookup = WordLookup(speaker: WordSpeaker(isMicrophoneRunning: { false }),
                                hasVoice: { _ in true },
                                hasDefinition: { _ in true },
                                translatorAvailability: { _ in .ready })
        let model = WordPopoverModel(word: word, language: "es", original: sentence, english: SettingExamples.spanishEnglish, lookup: lookup)
        await model.load()
        model.receiveMeaning("station")
        XCTAssertNil(model.translationRequest, "answered: no translation task is attached on the CI simulator")
        try capture("learning-word", VStack(spacing: 0) {
            WordPopoverView(model: model)
                .frame(maxWidth: 360)
                .padding(.top, 24)
            Spacer(minLength: 0)
        })
    }

    static let sampleTranscript: [(String, String)] = [
        ("es", "Good morning, thanks for joining us today."),
        ("es", "The first item is the quarterly report."),
        ("en", "Could you share the numbers again?"),
        ("es", "Of course — I'll send them after the call."),
    ]
}
