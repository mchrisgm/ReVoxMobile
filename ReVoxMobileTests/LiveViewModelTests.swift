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

    /// Microphone permission is requested before the pipeline is built.
    ///
    /// Building the pipeline configures and activates the audio session. Activating a `.playAndRecord` session
    /// while permission is still undetermined gives a live session with a dead input, and granting permission
    /// afterwards does not revive it — the microphone stays silent for the whole run (observed on device,
    /// build 8). So the prompt has to come first, and the session is only activated once the answer is known.
    func testPermissionIsRequestedBeforeThePipelineIsBuilt() async {
        let events = LockedBox<[String]>([])
        let permission = MicrophonePermission(
            status: { .undetermined },
            request: { events.mutate { $0.append("request") }; return true }
        )
        let pipelines = self.pipelines!
        let model = LiveViewModel(
            settings: store, mute: PlaybackMute(), permission: permission,
            modelReady: { _ in true },
            supplier: { _, _ in
                events.mutate { $0.append("build") }
                let pipeline = FakeLivePipeline()
                pipelines.mutate { $0.append(pipeline) }
                return pipeline
            }
        )

        await model.start()
        await waitUntil("running") { model.state == .running }

        XCTAssertEqual(events.value, ["request", "build"],
                       "the session must not be activated before the microphone answer is known")
    }

    /// A refusal at the prompt is the same outcome as a standing denial: a banner, and nothing started.
    func testDenyingThePromptShowsTheBannerAndBuildsNothing() async {
        let built = LockedBox<Int>(0)
        let model = LiveViewModel(
            settings: store, mute: PlaybackMute(),
            permission: MicrophonePermission(status: { .undetermined }, request: { false }),
            modelReady: { _ in true },
            supplier: { _, _ in built.mutate { $0 += 1 }; return FakeLivePipeline() }
        )

        await model.start()

        XCTAssertEqual(model.banner, .permissionDenied)
        XCTAssertEqual(built.value, 0)
        XCTAssertEqual(model.state, .idle)
    }

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

    func testConfigurationMirrorsSettingsIncludingDucking() {
        var settings = Settings()
        settings.latencyMode = "fast"
        settings.language = "it"
        let configuration = LiveViewModel.configuration(settings: settings, captureMode: .microphone)
        XCTAssertEqual(configuration.captureMode, .microphone)
        XCTAssertEqual(configuration.preset, .fast)
        XCTAssertEqual(configuration.pinnedLanguage, "it")
        XCTAssertTrue(configuration.duckingEnabled, "R11 default ducking = true")
        XCTAssertEqual(configuration.maxPending, 3)
        settings.ducking = false
        XCTAssertFalse(LiveViewModel.configuration(settings: settings, captureMode: .microphone).duckingEnabled)
    }

    func testDuckingEventsDriveThePillAndTheOffText() {
        let model = makeModel()
        XCTAssertNil(model.duckingStatusText)
        model.handle(SessionEvent.duckingChanged(true))
        XCTAssertTrue(model.isDucked)
        XCTAssertEqual(model.duckingStatusText, "Ducking")
        model.handle(SessionEvent.duckingChanged(false))
        XCTAssertFalse(model.isDucked)
        XCTAssertNil(model.duckingStatusText)
        store.update { $0.ducking = false }
        XCTAssertEqual(model.duckingStatusText, "Ducking off")
    }

    func testVoiceStatusComesFromTheRelay() {
        let relay = SpeakerStatusRelay()
        let model = LiveViewModel(settings: store, mute: PlaybackMute(), permission: .fixed(.granted), modelReady: { _ in true },
                                  supplier: { _, _ in FakeLivePipeline() }, speakerStatus: relay)
        XCTAssertEqual(model.voiceStatusText, "System voice — pocket-tts not downloaded")
        relay.status = .pocketTTS(voice: "alba")
        XCTAssertEqual(model.voiceStatusText, "alba (pocket-tts)")
        relay.status = .fallback(.loadFailed("x"))
        XCTAssertEqual(model.voiceStatusText, "System voice — pocket-tts failed to load")
    }
    func testKeepAliveGapShowsPausedByIOSUntilTheNextEntry() async {
        let model = makeModel()
        let (stream, continuation) = AsyncStream<KeepAliveMonitor.Event>.makeStream()
        model.observe(keepAlive: stream)
        await model.start()
        await waitUntil { model.state == .running }
        continuation.yield(.gap(seconds: 7, before: .init(position: 0, at: 0), after: .init(position: 0, at: 7)))
        await waitUntil("paused status") { model.sessionStatus == LiveViewModel.pausedByIOSText }
        first.emit(.entry(TranscriptEntry(timestamp: Date(), language: "es", original: "", english: "back")))
        await waitUntil { model.rows.count == 1 }
        XCTAssertNil(model.sessionStatus, "cleared by the next entry (§9)")
        continuation.finish()
    }

    private func makeBroadcastCoordinator() -> BroadcastCoordinator {
        let suite = "group.test.revox-\(UUID().uuidString)"
        let capture = BroadcastCapture(appGroup: suite, containerURL: nil, records: nil)
        return BroadcastCoordinator(capture: capture, records: nil, containerURL: nil, names: BroadcastNotificationNames(appGroup: suite))
    }

    /// What `CaptureSources.setBroadcastGapHandler` last installed on the app-lifetime capture: nil after a run's
    /// `MonitoredPipeline.stop()`, non-nil again after the next `start()`.
    private let installedGapHandler = LockedBox<(@Sendable (Int) async -> Void)?>(nil)

    /// A model whose supplier is the tail of `PipelineAssembler.supplier()` — the same `MonitoredPipeline` wrapper with
    /// the same two hooks — over a `FakeLivePipeline`, so a stop-then-start exercises the real install/release path
    /// without loading a Whisper or VAD model. `build` itself cannot run in the simulator (it throws `vadLoadFailed`).
    private func makeMonitoredModel() -> LiveViewModel {
        let pipelines = self.pipelines!
        let installed = self.installedGapHandler
        let monitor = KeepAliveMonitor()
        return LiveViewModel(
            settings: store, mute: PlaybackMute(), permission: .fixed(.granted),
            modelReady: { _ in true },
            supplier: { settings, _ in
                let pipeline = FakeLivePipeline()
                pipelines.mutate { $0.append(pipeline) }
                let isBroadcast = settings.capture == .broadcast
                return MonitoredPipeline(
                    pipeline: pipeline, monitor: monitor, position: { 0 },
                    onStart: { [weak pipeline] in
                        guard isBroadcast else {
                            installed.mutate { $0 = nil }
                            return
                        }
                        let handler: @Sendable (Int) async -> Void = { _ in await pipeline?.noteCaptureGap() }
                        installed.mutate { $0 = handler }
                    },
                    onStop: { installed.mutate { $0 = nil } })
            }
        )
    }

    func testSwitchingTheSourceRebuildsThePipeline() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        await model.stop()
        await waitUntil { model.state == .idle }
        model.captureMode = .broadcast
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(pipelines.value.count, 2, "the signature includes the capture mode")
        XCTAssertEqual(pipelines.value[1].startedWith.first?.captureMode, .broadcast)
        XCTAssertEqual(model.supplierCallCount, 2)
    }

    func testBroadcastEventsDriveRowsStatusAndStop() async {
        let coordinator = makeBroadcastCoordinator()
        let model = makeModel()
        model.observe(broadcast: coordinator)
        model.captureMode = .broadcast
        XCTAssertEqual(model.broadcastStatusText, BroadcastCoordinator.startPromptText)
        XCTAssertTrue(model.showsBroadcastPicker)
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(pipelines.value.count, 1, "broadcast mode starts without a microphone permission check")

        coordinator.handle(.attached(generation: 1, joinedInProgress: true))
        await waitUntil("joined row") { model.rows.count == 1 }
        XCTAssertEqual(model.rows[0].kind, .joinedInProgress)
        XCTAssertFalse(model.showsBroadcastPicker)
        XCTAssertEqual(model.broadcastStatusText, BroadcastCoordinator.joinedText)

        coordinator.handle(.silence(seconds: 10))
        await waitUntil { model.broadcastStatusText == BroadcastCoordinator.silentText }

        coordinator.handle(.idle)
        await waitUntil("stopped by ended") { self.first.stopCount == 1 }
        await waitUntil { model.state == .idle }
        XCTAssertEqual(model.sessionStatus, BroadcastCoordinator.endedText)
        XCTAssertTrue(model.showsBroadcastPicker)

        model.captureMode = .microphone
        XCTAssertNil(model.broadcastStatusText, "microphone mode shows no broadcast status")
        XCTAssertFalse(model.showsBroadcastPicker)
    }

    func testStaleBroadcastStopsAndReportsIt() async {
        let coordinator = makeBroadcastCoordinator()
        let model = makeModel()
        model.observe(broadcast: coordinator)
        model.captureMode = .broadcast
        await model.start()
        await waitUntil { model.state == .running }
        coordinator.handle(.attached(generation: 1, joinedInProgress: false))
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.rows.count, 0, "not joined: no header row")
        coordinator.handle(.stale(lastWriteAt: 1))
        await waitUntil("stopped by stale") { self.first.stopCount == 1 }
        XCTAssertEqual(model.sessionStatus, BroadcastCoordinator.staleText)
    }

    /// The regression this task's per-run hooks exist for: `LiveViewModel` caches the pipeline across restarts
    /// (`start()` calls the supplier only when the signature changed), so an install done once in `build` would be
    /// cleared by the first `stop()` and never re-armed — from the second run on, a ring overrun would produce no
    /// drop marker and no "Falling behind" badge (§6.2, §5.4, §9). Every Control-Center broadcast end hits this path:
    /// `observe(broadcast:)` calls `stop()` on `.ended`/`.stale`, and the user then starts again with the same settings.
    func testTheRingGapHandlerIsReinstalledOnEveryBroadcastRun() async {
        let model = makeMonitoredModel()
        model.captureMode = .broadcast
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertNotNil(installedGapHandler.value, "the first run installs the handler")
        await model.stop()
        await waitUntil { model.state == .idle }
        XCTAssertNil(installedGapHandler.value, "the run's handler dies with the run: no late overrun into a dead pipeline")
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(model.supplierCallCount, 1, "the pipeline is reused: build() does not run again")
        XCTAssertNotNil(installedGapHandler.value, "the second run still reports ring overruns")
        await installedGapHandler.value?(512)
        XCTAssertEqual(first.gapCount, 1)
        await model.stop()
    }

    func testAMicrophoneRunClearsTheRingGapHandler() async {
        let model = makeMonitoredModel()
        model.captureMode = .broadcast
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertNotNil(installedGapHandler.value)
        await model.stop()
        await waitUntil { model.state == .idle }
        model.captureMode = .microphone
        await model.start()
        await waitUntil { model.state == .running }
        XCTAssertEqual(model.supplierCallCount, 2, "the capture mode is part of the signature: a rebuild")
        XCTAssertNil(installedGapHandler.value, "a microphone run leaves no ring handler on the app-lifetime capture")
        await model.stop()
    }

    func testBroadcastConfigurationCarriesTheMeasuredCaptureLatency() {
        let broadcast = LiveViewModel.configuration(settings: Settings(), captureMode: .broadcast)
        XCTAssertEqual(broadcast.captureLatencyFrames, BroadcastTuning.captureLatencyFrames)
        XCTAssertEqual(broadcast.captureGateHoldFrames, CaptureGate.defaultHoldFrames)
        let microphone = LiveViewModel.configuration(settings: Settings(), captureMode: .microphone)
        XCTAssertEqual(microphone.captureLatencyFrames, 0, "mic mode: both gate positions coincide (§5.2)")
    }

    func testPermissionBannerClearsWhenAccessIsGrantedOnReturnAndNeverBecomesModal() async {
        let status = LockedBox<MicrophonePermissionStatus>(.denied)
        let permission = MicrophonePermission(status: { status.value }, request: { false })
        let model = makeModel(permission: permission)
        await model.start()
        XCTAssertEqual(model.banner, .permissionDenied)
        XCTAssertEqual(model.state, .idle)
        model.applicationDidBecomeActive()
        XCTAssertEqual(model.banner, .permissionDenied, "still denied: the banner stays; there is no alert to loop on")
        status.mutate { $0 = .granted }
        model.applicationDidBecomeActive()
        XCTAssertNil(model.banner, "returning from Settings with access granted clears the banner")
        XCTAssertEqual(model.state, .idle, "nothing starts by itself; the user taps Start")
    }

    // MARK: The cached pipeline is released when model files change (M7 Task 89)

    func testReleaseCachedPipelineForcesTheNextStartToRebuild() async {
        let model = makeModel()
        await model.start()
        await waitUntil("running") { model.state == .running }
        await model.stop()
        await waitUntil("idle") { model.state == .idle }
        XCTAssertEqual(model.supplierCallCount, 1)

        await model.releaseCachedPipeline()
        XCTAssertEqual(model.releasedPipelineCount, 1)
        XCTAssertEqual(first.stopCount, 2, "releasing stops the cached pipeline as well")

        await model.start()
        await waitUntil("running again") { model.state == .running }
        XCTAssertEqual(model.supplierCallCount, 2, "a released pipeline is rebuilt, never reused")
        XCTAssertEqual(pipelines.value.count, 2)
    }

    func testReleaseCachedPipelineIsIgnoredWhileRunning() async {
        let model = makeModel()
        await model.start()
        await waitUntil("running") { model.state == .running }
        await model.releaseCachedPipeline()
        XCTAssertEqual(model.releasedPipelineCount, 0)
        XCTAssertEqual(first.stopCount, 0)
        XCTAssertEqual(model.state, .running)
    }

    // MARK: Load-failure recovery (M7 Task 91)

    /// A supplier that throws the given errors in order and records the settings every build attempt received.
    /// One element per build attempt, consumed front to back: an error fails that build, `nil` lets it succeed, and
    /// once the list is empty every further build succeeds.
    private func makeRecoveringModel(failures: [Error?],
                                     installed: [WhisperModelID] = [.tiny, .base, .small]) -> (LiveViewModel, LockedBox<[Settings]>) {
        let pipelines = self.pipelines!
        let received = LockedBox<[Settings]>([])
        let remaining = LockedBox<[Error?]>(failures)
        let model = LiveViewModel(
            settings: store, mute: PlaybackMute(), permission: .fixed(.granted),
            modelReady: { _ in true },
            supplier: { settings, _ in
                received.mutate { $0.append(settings) }
                var next: Error?
                remaining.mutate { if !$0.isEmpty { next = $0.removeFirst() } }
                if let next { throw next }
                let pipeline = FakeLivePipeline()
                pipelines.mutate { $0.append(pipeline) }
                return pipeline
            },
            installedModels: { installed }
        )
        return (model, received)
    }

    func testWhisperLoadFailureFallsBackToTheLargestSmallerInstalledModel() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [PipelineBuildError.whisperLoadFailed(model: .small, reason: "compile failed")])
        await model.start()
        await waitUntil("running on the fallback") { model.state == .running }
        XCTAssertEqual(received.value.map(\.model), ["small", "base"])
        XCTAssertEqual(model.banner, .usingFallbackModel(requested: .small, used: .base))
        XCTAssertEqual(LiveBanner.fallbackText(requested: .small, used: .base), "Couldn't load small. Using base instead.")
        XCTAssertEqual(model.activeModel, .base)
        XCTAssertTrue(model.modelStatusText.hasPrefix("base"), "the status line names the model that actually loaded")
        XCTAssertEqual(store.settings.model, "small", "a fallback never overwrites the user's choice")
        XCTAssertEqual(model.supplierCallCount, 2)
        model.dismissBanner()
        XCTAssertNil(model.banner)
    }

    func testWhisperLoadFailureWithoutASmallerInstalledModelAsksForARedownload() async {
        store.update { $0.model = "tiny" }
        let (model, received) = makeRecoveringModel(failures: [PipelineBuildError.whisperLoadFailed(model: .tiny, reason: "missing files")],
                                                    installed: [.tiny])
        await model.start()
        await waitUntil("idle again") { model.state == .idle }
        XCTAssertEqual(received.value.count, 1, "no second build is attempted")
        XCTAssertEqual(model.banner, .modelLoadFailed(.tiny))
        XCTAssertEqual(LiveBanner.loadFailedText(.tiny), "Couldn't load tiny. Re-download tiny in Models.")
        XCTAssertNil(model.preparingMessage)
    }

    func testTheSearchWalksDownTheInstalledModelsAndGivesUpNamingTheLastFailure() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [
            PipelineBuildError.whisperLoadFailed(model: .small, reason: "compile failed"),
            PipelineBuildError.whisperLoadFailed(model: .base, reason: "compile failed"),
            PipelineBuildError.whisperLoadFailed(model: .tiny, reason: "compile failed"),
        ])
        await model.start()
        await waitUntil("idle again") { model.state == .idle }
        XCTAssertEqual(received.value.map(\.model), ["small", "base", "tiny"],
                       "each pass consumes one installed model, so the walk down §9 row 1 terminates")
        XCTAssertEqual(model.banner, .modelLoadFailed(.tiny),
                       "the give-up banner names the model whose load actually threw last")
        XCTAssertNil(model.fallback, "the failed fallback is dropped")
        XCTAssertEqual(model.activeModel, .small, "with no fallback the run is back on the user's own model")
        XCTAssertEqual(store.settings.model, "small")
    }

    func testASecondStartWithTheFallbackStillActiveFallsBackAgain() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [
            PipelineBuildError.whisperLoadFailed(model: .small, reason: "compile failed"),
            nil,
            PipelineBuildError.whisperLoadFailed(model: .base, reason: "compile failed"),
            nil,
        ])
        await model.start()
        await waitUntil("running on the fallback") { model.state == .running }
        XCTAssertEqual(model.activeModel, .base)

        await model.stop()
        await waitUntil("idle") { model.state == .idle }
        await model.releaseCachedPipeline()          // a delete dropped the cached pipeline (Task 89)
        await model.start()
        await waitUntil("running on the second fallback") { model.state == .running }

        XCTAssertEqual(received.value.map(\.model), ["small", "base", "base", "tiny"],
                       "an active fallback does not suppress the search: base failed, so tiny is tried")
        XCTAssertEqual(model.banner, .usingFallbackModel(requested: .base, used: .tiny),
                       "the banner names the model that failed this start, not the one the user selected")
        XCTAssertEqual(model.activeModel, .tiny)
        XCTAssertEqual(model.fallback, LiveViewModel.ModelFallbackState(requested: .small, used: .tiny),
                       "the fallback is still keyed on the user's model, so a later model change drops it")
        XCTAssertEqual(store.settings.model, "small", "a fallback never overwrites the user's choice")
    }

    func testChangingTheModelDropsAStaleFallbackAndTheSpecFallbackRunsAgain() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [
            PipelineBuildError.whisperLoadFailed(model: .small, reason: "x"),
            nil,
            PipelineBuildError.whisperLoadFailed(model: .medium, reason: "x"),
        ], installed: [.tiny, .base, .small, .medium])
        await model.start()
        await waitUntil("running on the fallback") { model.state == .running }
        XCTAssertEqual(model.fallback, LiveViewModel.ModelFallbackState(requested: .small, used: .base))

        store.update { $0.model = "medium" }        // the Models screen, or onActiveModelDeleted after a delete
        XCTAssertEqual(model.activeModel, .medium, "a fallback for a model the user has left is ignored at once")

        await model.stop()
        await waitUntil("idle") { model.state == .idle }
        await model.releaseCachedPipeline()          // both are guarded on idle (Tasks 89 and 91)
        await model.start()
        await waitUntil("running on the new model's own fallback") { model.state == .running }

        XCTAssertEqual(received.value.map(\.model), ["small", "base", "medium", "small"],
                       "the stale fallback is gone, so §9 row 1 searches again from the model the user now wants")
        XCTAssertEqual(model.banner, .usingFallbackModel(requested: .medium, used: .small),
                       "not .modelLoadFailed(.small): the banner names the model that actually failed")
        XCTAssertEqual(model.activeModel, .small)
        XCTAssertEqual(store.settings.model, "medium", "a fallback still never overwrites the user's choice")
    }

    func testVADLoadFailureShowsItsOwnBannerAndNeverRetries() async {
        let (model, received) = makeRecoveringModel(failures: [PipelineBuildError.vadLoadFailed("MLModel compile failed")])
        await model.start()
        await waitUntil("idle again") { model.state == .idle }
        XCTAssertEqual(received.value.count, 1)
        XCTAssertEqual(model.banner, .vadLoadFailed)
        XCTAssertEqual(LiveBanner.vadLoadFailedText, "Voice detector failed to load. Re-download it in Models.")
    }

    func testANonBuildErrorKeepsTheGenericBanner() async {
        let (model, _) = makeRecoveringModel(failures: [ModelInstallError.filesMissingAfterDownload("no models")])
        await model.start()
        await waitUntil("idle again") { model.state == .idle }
        guard case .error = model.banner else {
            return XCTFail("expected the generic error banner, got \(String(describing: model.banner))")
        }
    }

    // MARK: Degradation (M7 Task 94)

    func testMemoryDegradeRestartsARunningPipelineOnTheSmallerModelAndRestoresLater() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [])
        await model.start()
        await waitUntil("running") { model.state == .running }

        await model.degrade(to: .base, restartRunning: true)
        await waitUntil("running on base") { model.state == .running && model.supplierCallCount == 2 }
        XCTAssertEqual(received.value.map(\.model), ["small", "base"])
        XCTAssertEqual(model.activeModel, .base)
        XCTAssertEqual(store.settings.model, "small", "degradation never overwrites the user's choice")
        XCTAssertEqual(pipelines.value[0].stopCount, 2,
                       "degrade stopped it, then buildIfNeeded tore it down before the rebuild (tearDownPipeline stops too)")

        await model.degrade(to: .small, restartRunning: true)
        await waitUntil("back on small") { model.activeModel == .small && model.supplierCallCount == 3 }
        XCTAssertNil(model.fallback)
        XCTAssertEqual(pipelines.value[1].stopCount, 2)
    }

    func testThermalDegradeLeavesARunningSessionAloneAndAppliesAtTheNextStart() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [])
        await model.start()
        await waitUntil("running") { model.state == .running }

        await model.degrade(to: .base, restartRunning: false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.state, .running, "§9 asks for the smaller model for new sessions, not a rebuild on a hot device")
        XCTAssertEqual(model.supplierCallCount, 1)
        XCTAssertEqual(pipelines.value[0].stopCount, 0)
        XCTAssertEqual(model.activeModel, .base, "the next build already uses the smaller model")

        await model.stopByUser()
        await waitUntil("idle") { model.state == .idle }
        await model.start()
        await waitUntil("running on base") { model.state == .running && model.supplierCallCount == 2 }
        XCTAssertEqual(received.value.map(\.model), ["small", "base"])
    }

    func testAStartThatFailsUnderADegradationFallbackFallsBackAgain() async {
        store.update { $0.model = "small" }
        let (model, received) = makeRecoveringModel(failures: [
            nil,
            PipelineBuildError.whisperLoadFailed(model: .base, reason: "compile failed"),
            nil,
        ])
        await model.start()
        await waitUntil("running") { model.state == .running }

        await model.degrade(to: .base, restartRunning: false)
        await model.stopByUser()
        await waitUntil("idle") { model.state == .idle }
        await model.start()
        await waitUntil("running on the smaller model") { model.state == .running }

        XCTAssertEqual(received.value.map(\.model), ["small", "base", "tiny"],
                       "the degraded model failed to load, so §9 row 1 steps down once more instead of giving up")
        XCTAssertEqual(model.banner, .usingFallbackModel(requested: .base, used: .tiny),
                       "the banner names the model that failed, which under degradation is the reduced one")
        XCTAssertEqual(model.activeModel, .tiny)
        XCTAssertEqual(model.fallback, LiveViewModel.ModelFallbackState(requested: .small, used: .tiny))
        XCTAssertEqual(store.settings.model, "small", "degradation and recovery both leave the user's choice alone")
    }

    func testPauseForHeatStopsAndOnlyTheHeatPauseIsResumed() async {
        let (model, _) = makeRecoveringModel(failures: [])
        await model.start()
        await waitUntil("running") { model.state == .running }

        await model.pauseForHeat()
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.isPausedForHeat)
        XCTAssertEqual(pipelines.value[0].stopCount, 1)

        await model.resumeAfterHeat()
        await waitUntil("running again") { model.state == .running }
        XCTAssertFalse(model.isPausedForHeat)
        XCTAssertEqual(model.supplierCallCount, 1, "the cached pipeline is reused: only heat paused it")

        await model.pauseForHeat()
        XCTAssertTrue(model.isPausedForHeat)
        await model.stopByUser()
        await waitUntil("idle") { model.state == .idle }
        XCTAssertFalse(model.isPausedForHeat, "a user stop cancels the pending heat resume")
        await model.resumeAfterHeat()
        XCTAssertEqual(model.state, .idle, "a run the user stopped is not resumed by a thermal recovery")
    }

    func testDegradationBannerIsShownAndDismissed() async {
        let (model, _) = makeRecoveringModel(failures: [])
        model.showDegradationBanner(DegradationPolicy.heatReducedText)
        XCTAssertEqual(model.banner, .degraded("iPhone is hot: translation reduced"))
        model.dismissBanner()
        XCTAssertNil(model.banner)
    }
}
