import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class LiveViewModelTests: XCTestCase {
    private var store: SettingsStore!
    private var pipelines: LockedBox<[FakeLivePipeline]>!

    override func setUp() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxLiveVM-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = SettingsStore(fileURL: directory.appendingPathComponent(SettingsCodec.fileName))
        pipelines = LockedBox<[FakeLivePipeline]>([])
    }

    private func makeModel(permission: MicrophonePermission = .fixed(.granted), modelReady: Bool = true,
                           supplierFails: Bool = false) -> LiveViewModel {
        let pipelines = self.pipelines!
        return LiveViewModel(
            settings: store, mute: PlaybackMute(), permission: permission,
            modelReady: { _ in modelReady },
            supplier: { _, progress in
                if supplierFails { throw ModelInstallError.filesMissingAfterDownload("no models") }
                progress("Preparing model…")
                let pipeline = FakeLivePipeline()
                pipelines.mutate { $0.append(pipeline) }
                return pipeline
            }
        )
    }

    private var first: FakeLivePipeline { pipelines.value[0] }

    func testStartGoesPreparingThenRunning() async {
        let model = makeModel()
        await model.start()
        await waitUntil("running") { model.state == .running }
        XCTAssertEqual(model.stateHistory, [.preparing, .running])
        XCTAssertEqual(first.startedWith.first?.captureMode, .microphone)
        XCTAssertEqual(first.startedWith.first?.preset, .balanced)
        XCTAssertNil(first.startedWith.first?.pinnedLanguage)
        XCTAssertNil(model.preparingMessage)
    }

    func testToggleStopsWhenRunning() async {
        let model = makeModel()
        await model.toggle()
        await waitUntil { model.state == .running }
        await model.toggle()
        await waitUntil { model.state == .idle }
        XCTAssertEqual(first.stopCount, 1)
    }

    func testSourcePickerUsedOnStart() async {
        let model = makeModel()
        model.captureMode = .broadcast
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(first.startedWith.first?.captureMode, .broadcast)
        XCTAssertEqual(store.settings.captureMode, "broadcast", "the picker value is persisted")
    }

    func testEntryEventAppendsOnMainActor() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        first.emit(.entry(TranscriptEntry(timestamp: Date(), language: "de", original: "", english: "hi")))
        await waitUntil("entry row") { model.rows.count == 1 }
        XCTAssertEqual(model.rows[0].kind, .entry(language: "de", english: "hi"))
        XCTAssertEqual(model.detectedLanguage, "de")
        XCTAssertTrue(model.lastEventHandledOnMainThread)
    }

    func testErrorEventSetsErrorState() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        first.emit(.error("boom"))
        await waitUntil { model.state == .error }
        XCTAssertEqual(model.banner, .error("boom"))
        // An idle event after an error keeps the error state (Windows `_on_pipeline_event`).
        first.emit(.state(.idle))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.state, .error)
    }

    func testLoadedModelsReusedAcrossRestarts() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        await model.stop()
        await waitUntil { model.state == .idle }
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(pipelines.value.count, 1)
        XCTAssertEqual(model.supplierCallCount, 1)
        XCTAssertEqual(first.startedWith.count, 2)
    }

    func testLatencyModeChangeRebuildsPipeline() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        await model.stop()
        await waitUntil { model.state == .idle }
        model.setLatencyMode(.fast)
        XCTAssertEqual(store.settings.latencyMode, "fast")
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(pipelines.value.count, 2)
        XCTAssertEqual(pipelines.value[1].startedWith.first?.preset, .fast)
    }

    /// §10.1: the Swift counterpart of `test_app.py::test_supplier_failure_reports_error` (§9 row 1).
    func testLoadFailureShowsBannerWithoutStarting() async {
        let model = makeModel(supplierFails: true)
        await model.start()
        XCTAssertEqual(model.state, .idle)
        if case .error(let message)? = model.banner {
            XCTAssertTrue(message.contains("no models"))
        } else {
            XCTFail("expected an error banner, got \(String(describing: model.banner))")
        }
        XCTAssertEqual(model.stateHistory, [.preparing, .idle])
    }

    func testDeniedPermissionShowsBannerWithoutStarting() async {
        let model = makeModel(permission: .fixed(.denied))
        await model.start()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.banner, .permissionDenied)
        XCTAssertEqual(pipelines.value.count, 0)
    }

    func testMissingModelShowsTheDownloadBanner() async {
        let model = makeModel(modelReady: false)
        await model.start()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.banner, .modelMissing(.small))
        XCTAssertEqual(model.modelStatusText, "No model")
    }

    func testMuteForwardsToThePipelineAndIsAppliedOnStart() async {
        let model = makeModel()
        await model.setMuted(true)
        XCTAssertTrue(model.isMuted)
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(first.muted, [true])
        await model.setMuted(false)
        XCTAssertEqual(first.muted, [true, false])
    }

    func testLagSetsTheBadgeAddsOneMarkerRowAndClears() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        first.emit(.lag)
        first.emit(.lag)
        await waitUntil { model.isFallingBehind }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.rows.filter { $0.kind == .dropMarker }.count, 1, "consecutive markers collapse")
        first.emit(.entry(TranscriptEntry(timestamp: Date(), language: "es", original: "", english: "ok")))
        await waitUntil { model.rows.count == 2 }
        XCTAssertFalse(model.isFallingBehind, "an entry clears the badge (Windows laggedChanged(False))")
    }

    func testSessionEventsDriveTheStatusLine() {
        let model = makeModel()
        model.handle(SessionEvent.pausedByIOS)
        XCTAssertEqual(model.sessionStatus, "Translation paused by iOS")
        model.handle(SessionEvent.resumed)
        XCTAssertNil(model.sessionStatus)
        model.handle(SessionEvent.resumeFailed)
        XCTAssertEqual(model.sessionStatus, "Tap Start to resume")
        model.handle(SessionEvent.audioRestarted)
        XCTAssertEqual(model.sessionStatus, "Audio restarted")
        // §6.1: the capture source's own line, published by MicrophoneCapture through the controller (Tasks 28, 30, 40).
        model.handle(SessionEvent.captureStatus("No microphone input"))
        XCTAssertEqual(model.sessionStatus, "No microphone input")
        model.handle(SessionEvent.captureStatus(nil))
        XCTAssertNil(model.sessionStatus)
        model.handle(SessionEvent.routeChanged(.oldDeviceUnavailable))
        XCTAssertNil(model.sessionStatus, "a route change on its own says nothing")
    }

    func testM3ConfigurationHasDuckingOffAndMirrorsSettings() {
        var settings = Settings()
        settings.latencyMode = "fast"
        settings.language = "it"
        let configuration = LiveViewModel.configuration(settings: settings, captureMode: .microphone)
        XCTAssertEqual(configuration.captureMode, .microphone)
        XCTAssertEqual(configuration.preset, .fast)
        XCTAssertEqual(configuration.pinnedLanguage, "it")
        XCTAssertFalse(configuration.duckingEnabled, "ducking is delivered in M4")
        XCTAssertEqual(configuration.maxPending, 3)
    }
}
