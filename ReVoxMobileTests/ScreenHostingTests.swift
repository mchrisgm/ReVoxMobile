import XCTest
import SwiftUI
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

/// Hosts each screen in a `UIHostingController` and lays it out once: SwiftUI has no unit-test renderer, so this
/// proves the views build against their view models and do not trap on first layout.
@MainActor
final class ScreenHostingTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var store: SettingsStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxScreens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var support: ScreenHostingSupport { ScreenHostingSupport(layout: layout, store: store) }

    func makeModelsViewModel(pipelineRunning: Bool = false) -> ModelsViewModel {
        support.models(pipelineRunning: pipelineRunning)
    }

    func makeVoicesViewModel(installed: Bool = false, pipelineRunning: Bool = false) throws -> VoicesViewModel {
        try support.voices(installed: installed, pipelineRunning: pipelineRunning)
    }

    func testVoicesViewHostsBothEngines() throws {
        let notInstalled = try makeVoicesViewModel()
        host(NavigationStack { VoicesView(model: notInstalled) })
        let installed = try makeVoicesViewModel(installed: true)
        host(NavigationStack { VoicesView(model: installed) })
        let running = try makeVoicesViewModel(installed: true, pipelineRunning: true)
        host(NavigationStack { VoicesView(model: running) })
        XCTAssertEqual(running.footerText, VoicesViewModel.stopToDeleteText)
        XCTAssertFalse(running.canPlaySample)
    }

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    func testModelsViewHostsWithEveryRowState() {
        host(NavigationStack { ModelsView(model: makeModelsViewModel()) })
        host(NavigationStack { ModelsView(model: makeModelsViewModel(pipelineRunning: true)) })
        for phase in [ModelDownloadPhase.idle, .listing, .downloading(completedFiles: 1, totalFiles: 6), .compiling("x"), .verifying, .installed, .paused, .failed("boom")] {
            let row = ModelRow(id: .small, name: "small", sizeText: "≈ 487 MB", isRecommended: true, isSuitable: true, warning: nil, note: nil,
                               state: ModelDownloadState(phase: phase, fraction: 0.4, bytesExpected: 1), isSelected: false)
            host(List { ModelRowView(row: row, onDownload: {}, onCancel: {}, onSelect: {}) })
        }
    }

    func testSettingsViewHosts() throws {
        let settingsModel = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        let voices = try makeVoicesViewModel()
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel(), voices: voices) })
        settingsModel.latencyMode = .fast
        settingsModel.language = "es"
        settingsModel.ducking = false
        settingsModel.voiceVolume = 0.3
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel(), voices: voices) })
        // M9: every section's example in its "on" state, and the third preset.
        settingsModel.latencyMode = .veryFast
        settingsModel.learning = true
        settingsModel.romanize = true
        settingsModel.timeDisplay = .both
        settingsModel.keepModelWhenHot = true
        settingsModel.isMuted = true
        settingsModel.ignoredLanguage = "en"
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel(), voices: voices) })
    }

    func testLiveViewHostsInEveryState() async {
        let mute = PlaybackMute()
        let pipeline = FakeLivePipeline()
        let extensionID = "test.revox.broadcast"
        let live = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                 supplier: { _, _ in pipeline })
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // empty state
        await live.start()
        await waitUntil { live.state == .running }
        pipeline.emit(.entry(TranscriptEntry(timestamp: Date(), language: "es", original: "", english: "hola")))
        pipeline.emit(.lag)
        await waitUntil { live.rows.count == 2 }
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // running with rows and the badge
        pipeline.emit(.error("boom"))
        await waitUntil { live.state == .error }
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // error banner

        let denied = LiveViewModel(settings: store, mute: mute, permission: .fixed(.denied), modelReady: { _ in true }, supplier: { _, _ in pipeline })
        await denied.start()
        host(NavigationStack { LiveView(model: denied, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })  // permission banner

        let noModel = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in false }, supplier: { _, _ in pipeline })
        await noModel.start()
        host(NavigationStack { LiveView(model: noModel, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })  // download prompt

        let suite = "group.test.revox-\(UUID().uuidString)"
        let coordinator = BroadcastCoordinator(capture: BroadcastCapture(appGroup: suite, containerURL: nil, records: nil), records: nil,
                                               containerURL: nil, names: BroadcastNotificationNames(appGroup: suite))
        let broadcast = LiveViewModel(settings: store, mute: mute, permission: .fixed(.denied), modelReady: { _ in true },
                                      supplier: { _, _ in FakeLivePipeline() }, broadcast: coordinator)
        broadcast.captureMode = .broadcast
        XCTAssertTrue(broadcast.showsBroadcastPicker)
        host(NavigationStack { LiveView(model: broadcast, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // picker + captions, idle
        await broadcast.start()
        await waitUntil { broadcast.state == .running }
        XCTAssertNil(broadcast.banner, "a denied microphone does not block broadcast mode")
        host(NavigationStack { LiveView(model: broadcast, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // running, picker still shown
        coordinator.handle(.attached(generation: 1, joinedInProgress: true))
        await waitUntil { broadcast.rows.count == 1 }
        XCTAssertFalse(broadcast.showsBroadcastPicker)
        host(NavigationStack { LiveView(model: broadcast, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })   // attached, joined row
        // M8, §8.2: the two-way card expanded, and the button's preparing state with its spinner and progress line.
        let twoWay = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                   supplier: { _, _ in FakeLivePipeline() })
        twoWay.ignoredLanguage = "en"
        twoWay.isTwoWay = true
        twoWay.twoWayLanguage = "es"
        host(NavigationStack { LiveView(model: twoWay, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })
        XCTAssertEqual(twoWay.twoWayPair?.source, "en")
        twoWay.handle(.transcriptOnly(reason: TranslationStage.noEngineReason))
        host(NavigationStack { LiveView(model: twoWay, models: makeModelsViewModel(), broadcastExtensionBundleID: extensionID) })
        XCTAssertEqual(twoWay.transcriptOnlyNote, TranslationStage.noEngineReason)

        XCTAssertEqual(LiveView.availableSources, [.microphone, .broadcast])
        XCTAssertEqual(BroadcastPickerButton.size, 50)
        XCTAssertEqual(BroadcastPickerButton.captionText, "Tap to choose ReVox and start the broadcast. You can also start it from Control Center's Screen Recording control.")
        XCTAssertEqual(BroadcastPickerButton.footnoteText, "Locking the iPhone with the side button ends the broadcast.")
    }

    func testRootViewHostsAllThreeTabs() throws {
        let environment = try AppEnvironment.testing(root: root.appendingPathComponent("env", isDirectory: true))
        host(RootView(environment: environment).modelContainer(environment.transcriptContainer))
    }

    func testBroadcastDiagnosticsViewHostsWithAndWithoutARing() async throws {
        let model = BroadcastDiagnosticsModel(containerURL: root, records: nil, keepAlive: KeepAliveMonitor(),
                                              sessionController: AudioSessionController(session: RecordingAudioSessionSeam()))
        await model.refresh()
        host(NavigationStack { BroadcastDiagnosticsView(model: model) })
        let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: root))
        let writer = try RingWriter(storage: MappedRingStorage(mapping: mapping))
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        await model.refresh()
        host(NavigationStack { BroadcastDiagnosticsView(model: model) })
        let settingsModel = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        let voices = try makeVoicesViewModel()
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel(), voices: voices, diagnostics: model) })
    }

    func testSessionRowViewHosts() throws {
        let context = ModelContext(try TranscriptContainer.make(inMemory: true))
        let session = Session(startedAt: Date(), endedAt: Date().addingTimeInterval(90), captureMode: "broadcast", pinnedLanguage: "es", modelID: "small", voice: "alba", joinedInProgress: true)
        context.insert(session)
        let entry = Entry(timestamp: Date(), language: "es", original: "", english: "hola", isDropMarker: false)
        entry.session = session
        context.insert(entry)
        try context.save()
        host(List { SessionRowView(summary: SessionSummary(session: session)) })
        let empty = Session(startedAt: Date(), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        context.insert(empty)
        try context.save()
        host(List { SessionRowView(summary: SessionSummary(session: empty)) })
    }

    func testSessionDetailViewHostsWithEntriesAndEmpty() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        let session = Session(startedAt: Date(), endedAt: Date().addingTimeInterval(30), captureMode: "microphone", pinnedLanguage: "es", modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        for (offset, english) in [(1.0, "hola"), (2.0, "adi\u{00F3}s")] {
            let entry = Entry(timestamp: Date().addingTimeInterval(offset), language: "es", original: "", english: english, isDropMarker: false)
            entry.session = session
            context.insert(entry)
        }
        let marker = Entry(timestamp: Date().addingTimeInterval(1.5), language: "", original: "", english: "", isDropMarker: true)
        marker.session = session
        context.insert(marker)
        try context.save()
        let exporter = TranscriptExporter(directory: root.appendingPathComponent("exports", isDirectory: true))
        host(NavigationStack { SessionDetailView(session: session, exporter: exporter) }.modelContainer(container))
        let empty = Session(startedAt: Date(), captureMode: "broadcast", pinnedLanguage: nil, modelID: "base", voice: "system", joinedInProgress: true)
        context.insert(empty)
        try context.save()
        host(NavigationStack { SessionDetailView(session: empty, exporter: exporter) }.modelContainer(container))
    }


    func testHistoryViewHostsEmptyPopulatedAndSearching() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        // The per-test export directory: nothing this test pushes may write into the shared temporary folder.
        let exporter = TranscriptExporter(directory: root.appendingPathComponent("exports", isDirectory: true))
        host(NavigationStack { HistoryView(exporter: exporter) }.modelContainer(container))     // "No Transcripts"
        let context = ModelContext(container)
        let session = Session(startedAt: Date(), endedAt: Date().addingTimeInterval(10), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        context.insert(session)
        let entry = Entry(timestamp: Date(), language: "es", original: "", english: "hola", isDropMarker: false)
        entry.session = session
        context.insert(entry)
        try context.save()
        host(NavigationStack { HistoryView(exporter: exporter) }.modelContainer(container))                       // one row
        host(NavigationStack { HistoryView(initialQuery: "hola", exporter: exporter) }.modelContainer(container)) // one hit
        host(NavigationStack { HistoryView(initialQuery: "zzz", exporter: exporter) }.modelContainer(container))  // ContentUnavailableView.search
        // M9: edit mode with the Merge / Delete bar; a second session so Merge has something to count.
        let second = Session(startedAt: Date().addingTimeInterval(120), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        context.insert(second)
        try context.save()
        host(NavigationStack { HistoryView(exporter: exporter, editing: true) }.modelContainer(container))        // selecting
        XCTAssertEqual(HistoryView.emptyTitle, "No Transcripts")
        XCTAssertEqual(HistoryView.emptyDescription, "Sessions you translate appear here.")
        XCTAssertEqual(HistoryView(exporter: exporter).exporter.directory.standardizedFileURL,
                       root.appendingPathComponent("exports", isDirectory: true).standardizedFileURL,
                       "the screen carries the injected exporter, not the defaulted temporary-folder one")
    }

    func testAboutViewHosts() {
        host(NavigationStack { AboutView(info: AboutInfo(marketingVersion: "0.1.0", buildNumber: "42")) })
    }

    func testBroadcastPickerButtonHosts() {
        host(BroadcastPickerButton(preferredExtension: "com.example.revox.Broadcast")
            .frame(width: BroadcastPickerButton.size, height: BroadcastPickerButton.size))
    }
}
