import Foundation
import Observation
import ReVoxCore

enum LiveState: Equatable, Sendable {
    case idle, preparing, running, error
}

enum LiveBanner: Equatable, Sendable {
    case permissionDenied
    case error(String)
    case modelMissing(WhisperModelID)
    /// §9 row 1: the selected model would not load and a smaller installed one is being used instead.
    case usingFallbackModel(requested: WhisperModelID, used: WhisperModelID)
    /// §9 row 1 with nothing smaller installed.
    case modelLoadFailed(WhisperModelID)
    /// §9 VAD row (§6.3).
    case vadLoadFailed
    /// §9 memory and thermal rows.
    case degraded(String)

    static func fallbackText(requested: WhisperModelID, used: WhisperModelID) -> String {
        "Couldn't load \(requested.displayName). Using \(used.displayName) instead."
    }

    static func loadFailedText(_ id: WhisperModelID) -> String {
        "Couldn't load \(id.displayName). Re-download \(id.displayName) in Models."
    }

    static let vadLoadFailedText = "Voice detector failed to load. Re-download it in Models."
}

/// The Live screen state machine (§8.2), the port of the Windows `AppController`.
@MainActor
@Observable
final class LiveViewModel {
    static let lagBadgeDuration: TimeInterval = 5
    static let pausedByIOSText = "Translation paused by iOS"
    static let tapStartText = "Tap Start to resume"
    static let audioRestartedText = "Audio restarted"
    static let systemVoiceText = SpeakerStatus.notDownloadedText
    static let duckingText = "Ducking"
    static let duckingOffText = "Ducking off"

    private(set) var state: LiveState = .idle
    private(set) var stateHistory: [LiveState] = []
    private(set) var rows: [LiveTranscriptRow] = []
    private(set) var isFallingBehind = false
    private(set) var isSpeaking = false
    /// From `SessionEvent.duckingChanged` (§6.8): true while the controller's applied mask carries `.duckOthers`.
    private(set) var isDucked = false
    private(set) var banner: LiveBanner?
    private(set) var preparingMessage: String?
    private(set) var sessionStatus: String?
    private(set) var detectedLanguage: String?
    private(set) var supplierCallCount = 0
    /// How often a cached pipeline was dropped because model files changed (§6.9, M7); read by the tests.
    private(set) var releasedPipelineCount = 0

    /// §9 row 1: the run is using `used` because `requested` would not load. Never written to `Settings`.
    struct ModelFallbackState: Equatable, Sendable {
        let requested: WhisperModelID
        let used: WhisperModelID
    }

    private(set) var fallback: ModelFallbackState?

    /// True while a thermal `.critical` pause stopped the run; only such a run is resumed automatically (§9).
    private(set) var isPausedForHeat = false

    /// Every model this start has already handed to the supplier, successfully or not. `recover(from:)` searches only
    /// among the models it has not tried yet, so each recovery pass consumes one installed model and the walk down
    /// the catalog terminates (§9 row 1). Cleared by `start()`.
    @ObservationIgnored private var attemptedModels: Set<WhisperModelID> = []
    private(set) var modelReadyForStatus: Bool?
    private(set) var lastEventHandledOnMainThread = false
    /// The status line's voice part; M4's `EffectiveSpeaker` status replaces the constant.

    private let settings: SettingsStore
    private let mute: PlaybackMute
    private let permission: MicrophonePermission
    private let modelReady: @MainActor (WhisperModelID) async -> Bool
    private let supplier: PipelineSupplier
    private let speakerStatus: SpeakerStatusRelay
    /// Set by `observe(broadcast:)` — both from the initializer and from `AppEnvironment`/tests that wire the
    /// coordinator after construction; `broadcastStatusText` and `showsBroadcastPicker` read it. `@ObservationIgnored`
    /// because the reference itself never changes meaningfully: the coordinator is `@Observable`, so reading
    /// `broadcast?.statusText` inside a computed property still tracks the coordinator's own changes.
    @ObservationIgnored private var broadcast: BroadcastCoordinator?
    @ObservationIgnored private var broadcastTask: Task<Void, Never>?
    @ObservationIgnored private var pipeline: (any LivePipeline)?
    @ObservationIgnored private let installedModels: @MainActor () -> [WhisperModelID]
    @ObservationIgnored private var signature: PipelineSignature?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lagTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?

    init(settings: SettingsStore, mute: PlaybackMute, permission: MicrophonePermission = .live,
         modelReady: @escaping @MainActor (WhisperModelID) async -> Bool, supplier: @escaping PipelineSupplier,
         speakerStatus: SpeakerStatusRelay? = nil, broadcast: BroadcastCoordinator? = nil,
         installedModels: @escaping @MainActor () -> [WhisperModelID] = { [] }) {
        self.settings = settings
        self.mute = mute
        self.permission = permission
        self.modelReady = modelReady
        self.supplier = supplier
        self.installedModels = installedModels
        // `nil`, not `SpeakerStatusRelay()`: a default argument is evaluated in the caller's context, which
        // may be nonisolated, and the relay is main-actor isolated. Building it here — inside the isolated
        // init — keeps the convenience without the isolation violation.
        self.speakerStatus = speakerStatus ?? SpeakerStatusRelay()
        if let broadcast {
            observe(broadcast: broadcast)      // stores it and starts draining its events
        }
        refreshVoiceNote()
    }

    // MARK: Inputs

    /// The source picker (§8.2); persisted so `settings.capture` matches what the assembler configures.
    var captureMode: CaptureMode {
        get { settings.settings.capture }
        set { settings.update { $0.captureMode = newValue.rawValue } }
    }

    var isMuted: Bool { mute.isMuted }

    /// The settings the pipeline is built from: the user's, with the model replaced while a fallback is active.
    /// A fallback whose `requested` model is no longer the user's choice is ignored here on the spot — so the status
    /// line names the newly chosen model at once — and `start()` clears it outright before the next build, so a run
    /// never inherits a fallback for a model the user has left (§9 row 1).
    var effectiveSettings: Settings {
        var value = settings.settings
        if let fallback, fallback.requested == value.whisperModel {
            value.model = fallback.used.rawValue
        }
        return value
    }

    /// The model this run actually uses.
    var activeModel: WhisperModelID { effectiveSettings.whisperModel }

    var modelStatusText: String {
        let name = activeModel.displayName
        switch state {
        case .preparing: return preparingMessage ?? "Preparing…"
        default: return modelReadyForStatus == false ? "No model" : "\(name) · ready"
        }
    }

    /// The voice part of the status line (§8.2): "alba (pocket-tts)", "System voice — pocket-tts not downloaded", …
    var voiceStatusText: String { speakerStatus.text }

    /// "Ducking" pill while ducked, "Ducking off" when the toggle is off, nothing otherwise (§8.2).
    var duckingStatusText: String? {
        if isDucked { return Self.duckingText }
        return settings.settings.ducking ? nil : Self.duckingOffText
    }

    /// The broadcast attach state for the status line, only while the source is Other apps (§6.2, §8.2).
    var broadcastStatusText: String? {
        guard captureMode == .broadcast else { return nil }
        return broadcast?.statusText
    }

    /// The `RPSystemBroadcastPickerView` is shown while no broadcast is attached or known to be live (§8.2).
    var showsBroadcastPicker: Bool {
        guard captureMode == .broadcast else { return false }
        return broadcast?.needsBroadcast ?? true
    }

    static func configuration(settings: Settings, captureMode: CaptureMode) -> PipelineConfiguration {
        var configuration = PipelineConfiguration(captureMode: captureMode, preset: settings.preset, pinnedLanguage: settings.language)
        configuration.duckingEnabled = settings.ducking   // R11; the controller applies the cycles of §6.8
        configuration.captureLatencyFrames = captureMode == .broadcast ? BroadcastTuning.captureLatencyFrames : 0   // §5.2
        configuration.ignoredLanguage = settings.ignored          // §8.2 (M8)
        configuration.twoWay = settings.twoWay
        configuration.twoWayLanguage = settings.twoWayLanguage
        return configuration
    }

    // MARK: Two-way conversation (§8.2, M8)

    /// The language ReVox leaves alone. nil = every language is translated, the pre-M8 behaviour.
    var ignoredLanguage: String? {
        get { settings.settings.ignored }
        set { settings.update { $0.ignoredLanguage = newValue } }
    }

    /// Whether that language is spoken back in `twoWayLanguage` instead of being dropped.
    var isTwoWay: Bool {
        get { settings.settings.twoWay }
        set { settings.update { $0.twoWay = newValue } }
    }

    var twoWayLanguage: String? {
        get { settings.settings.twoWayLanguage }
        set {
            settings.update { $0.twoWayLanguage = newValue }
            refreshVoiceNote()
        }
    }

    /// iOS speaks the second direction with its own voice, so a language it has no voice for is silence. Said
    /// while the language is being chosen rather than discovered mid-conversation — and held here rather than
    /// computed in the view body, because reading the installed voices walks them and the body runs on every row.
    private(set) var twoWayVoiceNote: String?

    func refreshVoiceNote() {
        twoWayVoiceNote = Self.voiceNote(for: settings.settings.twoWayLanguage)
    }

    static func voiceNote(for target: String?) -> String? {
        guard let target, !target.isEmpty, !SystemSpeaker.hasVoice(for: target) else { return nil }
        let name = LanguageCatalog.displayName(target, whenNil: "None")
        return "This iPhone has no \(name) voice, so replies stay in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices."
    }

    /// The pair the second direction needs, for the screen to hand to Apple's translator. nil whenever two-way is
    /// off, incomplete, or would translate a language into itself.
    var twoWayPair: (source: String, target: String)? {
        guard isTwoWay, let source = ignoredLanguage, let target = settings.settings.twoWayTarget, source != target else { return nil }
        return (source, target)
    }

    /// A phrase kept in the transcript that nothing could say — surfaced once, dismissibly, rather than as silence.
    private(set) var transcriptOnlyNote: String?

    func dismissTranscriptOnlyNote() {
        transcriptOnlyNote = nil
    }

    // MARK: Lifecycle (Windows start / stop / toggle)

    func start() async {
        guard state == .idle || state == .error else { return }
        banner = nil
        sessionStatus = nil
        transcriptOnlyNote = nil
        // The answer must be known before anything activates the audio session: a `.playAndRecord` session
        // activated while permission is undetermined comes up with a dead input, and granting permission after
        // the fact does not revive it (observed on device, build 8). Building the pipeline is what configures
        // and activates the session, so the prompt happens strictly before that.
        if captureMode == .microphone {
            switch permission.status() {
            case .denied:
                banner = .permissionDenied
                return
            case .undetermined:
                guard await permission.request() else {
                    banner = .permissionDenied
                    return
                }
            case .granted:
                break
            }
        }
        let model = settings.settings.whisperModel
        // §9 row 1: a fallback belongs to the model it was installed for. The moment the user picks another one
        // (Models screen, or `onActiveModelDeleted` after a delete) the fallback is stale: `effectiveSettings`
        // already ignores it, and dropping it here keeps the published `fallback` honest — for the status line and
        // for the next failure's search.
        if let fallback, fallback.requested != model { self.fallback = nil }
        // Each start searches the installed models from scratch (§9 row 1).
        attemptedModels = []
        let ready = await modelReady(model)
        modelReadyForStatus = ready
        guard ready else {
            banner = .modelMissing(model)
            return
        }
        setState(.preparing)
        guard await buildIfNeeded() else { return }
        preparingMessage = nil
        guard let pipeline else { return }
        await pipeline.setMuted(mute.isMuted)
        await pipeline.start(Self.configuration(settings: effectiveSettings, captureMode: captureMode))
    }

    /// Reuses the cached pipeline when its signature still matches, otherwise builds one; a load failure goes to
    /// `recover(from:)` (§9 rows 1 and 4). Returns false when the run must not start.
    private func buildIfNeeded() async -> Bool {
        if pipeline != nil, signature == PipelineSignature(settings: effectiveSettings) { return true }
        await tearDownPipeline()
        do {
            try await build(with: effectiveSettings)
            return true
        } catch {
            return await recover(from: error)
        }
    }

    private func build(with builtSettings: Settings) async throws {
        attemptedModels.insert(builtSettings.whisperModel)
        supplierCallCount += 1
        let built = try await supplier(builtSettings) { [weak self] message in
            Task { @MainActor in self?.preparingMessage = message }
        }
        pipeline = built
        signature = PipelineSignature(settings: builtSettings)
        observe(built)
    }

    /// A Whisper load failure falls back to the largest smaller installed model the run has not tried yet and
    /// rebuilds, repeating until one loads or nothing smaller is left; everything else is reported (§9 rows 1 and 4).
    /// The pipeline itself never enters `.error` from here.
    private func recover(from error: Error) async -> Bool {
        preparingMessage = nil
        setState(.idle)
        switch error as? PipelineBuildError {
        case .vadLoadFailed:
            banner = .vadLoadFailed
            return false
        case .whisperLoadFailed(let failed, _):
            let untried = installedModels().filter { !attemptedModels.contains($0) }
            guard let smaller = ModelFallback.smallerInstalledModel(than: failed, installed: untried) else {
                fallback = nil
                banner = .modelLoadFailed(failed)
                return false
            }
            fallback = ModelFallbackState(requested: settings.settings.whisperModel, used: smaller)
            setState(.preparing)
            do {
                try await build(with: effectiveSettings)
                banner = .usingFallbackModel(requested: failed, used: smaller)
                return true
            } catch {
                return await recover(from: error)
            }
        case nil:
            banner = .error(String(describing: error))
            return false
        }
    }

    /// The banner's Dismiss button (§8.8: a banner is never a modal loop).
    func dismissBanner() {
        banner = nil
    }

    /// §9 memory and thermal rows: use `model` from now on. The user's `Settings.model` is untouched and the cached
    /// pipeline is dropped, so the next build uses `model` whatever happens. `restartRunning` decides what a session
    /// that is already going does: the memory rows pass true — the loaded model is the memory the device wants back,
    /// so it is torn down and rebuilt smaller at once — while the thermal row passes false, because §9 asks for the
    /// smaller model "for new sessions" and a teardown plus a full WhisperKit load is the most expensive thing to do
    /// on a hot device, and it would drop the audio in flight.
    func degrade(to model: WhisperModelID, restartRunning: Bool) async {
        let requested = settings.settings.whisperModel
        let target: ModelFallbackState? = model == requested ? nil : ModelFallbackState(requested: requested, used: model)
        guard target != fallback else { return }
        fallback = target
        signature = nil                                  // the cached pipeline was built for the previous model
        guard restartRunning, state == .running else { return }
        await stop()
        setState(.idle)
        await start()
    }

    /// Thermal `.critical`: stop the run and remember that heat, not the user, stopped it.
    func pauseForHeat() async {
        guard state == .running || state == .preparing else { return }
        isPausedForHeat = true
        await stop()
        setState(.idle)
    }

    /// The thermal state recovered: resume only a run that `pauseForHeat()` stopped.
    func resumeAfterHeat() async {
        guard isPausedForHeat else { return }
        isPausedForHeat = false
        await start()
    }

    /// §9: the memory/thermal banner, dismissible like every other Live banner (§8.8).
    func showDegradationBanner(_ text: String) {
        banner = .degraded(text)
    }

    func stop() async {
        await pipeline?.stop()
    }

    /// The Live screen's Stop button and the toolbar: a user stop also cancels a pending heat resume.
    func stopByUser() async {
        isPausedForHeat = false
        await stop()
    }

    /// Returning from Settings after granting microphone access clears the permission banner (§8.8: inline banner
    /// plus the Settings link, never a modal loop). Nothing is started here; the user taps Start.
    func applicationDidBecomeActive() {
        if banner == .permissionDenied, permission.status() != .denied {
            banner = nil
        }
        refreshVoiceNote()   // a voice may have just been installed in iOS Settings (§8.2)
    }

    func toggle() async {
        switch state {
        case .running:
            await stopByUser()
        case .idle, .error:
            setState(.idle)
            await start()
        case .preparing:
            break
        }
    }

    func setMuted(_ muted: Bool) async {
        mute.isMuted = muted
        await pipeline?.setMuted(muted)
    }

    /// Windows `set_latency_mode`: a change invalidates the cached pipeline.
    func setLatencyMode(_ preset: SegmenterPreset) {
        guard preset != settings.settings.preset else { return }
        settings.update { $0.latencyMode = preset.rawValue }
        signature = nil
    }

    /// A model or voice was deleted: the cached pipeline still holds the removed files open, so drop it while idle.
    /// Running or preparing runs are left alone — `ModelManager` refuses a delete then (§6.9).
    func releaseCachedPipeline() async {
        guard state == .idle || state == .error else { return }
        await tearDownPipeline()
        releasedPipelineCount += 1
    }

    private func tearDownPipeline() async {
        eventTask?.cancel()
        eventTask = nil
        if let pipeline {
            await pipeline.stop()
        }
        pipeline = nil
        signature = nil
    }

    private func observe(_ pipeline: any LivePipeline) {
        eventTask = Task { [weak self] in
            for await event in pipeline.events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    // MARK: Events (Windows `_on_pipeline_event`)

    func handle(_ event: PipelineEvent) {
        lastEventHandledOnMainThread = Thread.isMainThread
        switch event {
        case .state(let pipelineState):
            switch pipelineState {
            case .running:
                setState(.running)
            case .idle:
                if state != .error { setState(.idle) }
            case .error:
                setState(.error)
            }
        case .entry(let entry):
            if sessionStatus == Self.pausedByIOSText { sessionStatus = nil }
            isFallingBehind = false
            lagTask?.cancel()
            detectedLanguage = entry.language
            rows.append(LiveTranscriptRow(time: entry.timestamp, kind: .entry(language: entry.language, english: entry.english)))
        case .lag:
            isFallingBehind = true
            if rows.last?.kind != .dropMarker {
                rows.append(LiveTranscriptRow(time: Date(), kind: .dropMarker))
            }
            lagTask?.cancel()
            lagTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.lagBadgeDuration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.isFallingBehind = false
            }
        case .speaking(let speaking):
            isSpeaking = speaking
        case .error(let message):
            setState(.error)
            banner = .error(message)
        case .transcriptOnly(let reason):
            transcriptOnlyNote = reason
        }
    }

    func handle(_ event: SessionEvent) {
        switch event {
        case .pausedByIOS: sessionStatus = Self.pausedByIOSText
        case .resumed: sessionStatus = nil
        case .resumeFailed: sessionStatus = Self.tapStartText
        case .audioRestarted: sessionStatus = Self.audioRestartedText
        case .duckingChanged(let ducked): isDucked = ducked
        case .routeChanged: break   // §9: no user-visible surface; the tap rebuild happens in MicrophoneCapture (Task 30)
        case .captureStatus(let text): sessionStatus = text   // §6.1 "No microphone input"; nil clears the line
        }
    }

    func observe(sessionEvents: AsyncStream<SessionEvent>) {
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            for await event in sessionEvents {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// §9 "App was suspended while translating": a heartbeat gap shows the paused status until the next entry.
    func observe(keepAlive: AsyncStream<KeepAliveMonitor.Event>) {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            for await event in keepAlive {
                guard let self else { return }
                if case .gap = event {
                    self.sessionStatus = Self.pausedByIOSText
                }
            }
        }
    }

    /// §6.2 / §9 broadcast rows: joined header, ended/failed/stale stop the pipeline cleanly, silence is a hint.
    /// Storing the coordinator is what makes `broadcastStatusText` and `showsBroadcastPicker` report anything, so a
    /// model built without one and wired afterwards (`model.observe(broadcast:)`) behaves exactly like an injected one.
    func observe(broadcast coordinator: BroadcastCoordinator) {
        self.broadcast = coordinator
        broadcastTask?.cancel()
        broadcastTask = Task { [weak self] in
            for await event in coordinator.events {
                guard let self else { return }
                switch event {
                case .attached(let joinedInProgress):
                    if joinedInProgress, self.rows.last?.kind != .joinedInProgress {
                        self.rows.append(LiveTranscriptRow(time: Date(), kind: .joinedInProgress))
                    }
                case .ended(let reason):
                    self.sessionStatus = reason.map(BroadcastCoordinator.failedText) ?? BroadcastCoordinator.endedText
                    await self.stop()
                case .stale:
                    self.sessionStatus = BroadcastCoordinator.staleText
                    await self.stop()
                case .silent:
                    break                                       // shown through `broadcastStatusText`
                }
            }
        }
    }

    private func setState(_ newState: LiveState) {
        guard newState != state else { return }
        state = newState
        stateHistory.append(newState)
    }
}
