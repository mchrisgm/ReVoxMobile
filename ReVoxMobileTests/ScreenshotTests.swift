import XCTest
import SwiftUI
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

/// Renders each screen to PNGs in the host app's Documents — the README's size and App Store Connect's, through
/// `ScreenCapture` — so the README's screenshots and the raw captures behind the App Store set are generated from
/// the real views by CI rather than drawn by hand and left to rot. `scripts/ci/collect-screenshots.sh` copies both
/// folders out of the simulator container after the test run.
///
/// It is a test, not a UI test, for the same reason `ScreenHostingTests` is one: the screens are built from view
/// models the test can put into an exact state, and no simulator automation is needed to reach it.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var store: SettingsStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxShots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// One PNG per size and a real one, checked for content and for its exact pixel size: see `ScreenCapture`.
    @discardableResult
    func capture<V: View>(_ name: String, settle: TimeInterval = 0.25, _ view: V) throws -> URL {
        try ScreenCapture.capture(name, settle: settle, view)
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

        // M11 §5: the Benchmark screen with a measured run, and the Models screen showing what that run recommends.
        // The measured note counts only models that are installed now, so the sample run's two measured models are
        // put on disk first — small then wins on word error rate and carries the note.
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let benchmarkStore = BenchmarkStore(directory: root.appendingPathComponent("Benchmarks", isDirectory: true),
                                            host: BenchmarkHost(device: "iPhone17,1", iOSVersion: "26.0.1", memoryTierGB: 8))
        try benchmarkStore.save(.sample())
        let benchmark = BenchmarkViewModel(store: benchmarkStore, manager: hosting.manager(),
                                           isPipelineRunning: { false }, releasePipeline: {},
                                           runner: BenchmarkRunner(seams: FakeBenchmarkSeams().seams), host: FakeInstallHost())
        let models = hosting.models(benchmarks: benchmarkStore)
        models.benchmark = benchmark                                  // the "Benchmark this iPhone" row and its footer
        try capture("models", NavigationStack { ModelsView(model: models) })
        try capture("benchmark", NavigationStack { BenchmarkView(model: benchmark) })
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
        // M11 (§4): the bar is a safe-area inset over a bar material; a second turn lets the material settle. The
        // capture sits inside a TabView because the whole point of the bar is where it sits relative to the tab bar.
        try capture("history-selecting", settle: 1.0, TabView {
            NavigationStack { HistoryView(exporter: exporter, editing: true) }
                .tabItem { Label("History", systemImage: "clock") }
        }.modelContainer(container))
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

    /// Every capture is written twice: the README's 786 × 1704 to `screenshots`, and App Store Connect's
    /// 1290 × 2796 — the 6.9-inch slot's exact size — to the sibling `store-screenshots` folder. Written before the
    /// second render existed, when it failed at the `store-screenshots` unwrap: no such file. The view is twelve
    /// flat bands, so the blank check cannot be what fails, and both files are removed afterwards so the folders CI
    /// collects hold only the screens.
    func testEveryCaptureIsAlsoWrittenAtTheAppStoreSize() throws {
        let name = "size-check"
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let readme = documents.appendingPathComponent("screenshots/\(name).png")
        let store = documents.appendingPathComponent("store-screenshots/\(name).png")
        defer {
            try? FileManager.default.removeItem(at: readme)
            try? FileManager.default.removeItem(at: store)
        }
        try capture(name, VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { band in
                Color(hue: Double(band) / 12, saturation: 0.7, brightness: 0.9)
            }
        })
        let readmeImage = try XCTUnwrap(UIImage(contentsOfFile: readme.path)?.cgImage, "no README capture at \(readme.path)")
        XCTAssertEqual([readmeImage.width, readmeImage.height], [786, 1704], "the README render stays 393 × 852 points at @2x")
        let storeImage = try XCTUnwrap(UIImage(contentsOfFile: store.path)?.cgImage, "no store capture at \(store.path)")
        XCTAssertEqual([storeImage.width, storeImage.height], [1290, 2796], "App Store Connect's 6.9-inch slot: 430 × 932 points at @3x")
    }

    static let sampleTranscript: [(String, String)] = [
        ("es", "Good morning, thanks for joining us today."),
        ("es", "The first item is the quarterly report."),
        ("en", "Could you share the numbers again?"),
        ("es", "Of course — I'll send them after the call."),
    ]
}
