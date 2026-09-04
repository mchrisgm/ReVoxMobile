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
    @ObservationIgnored private var signature: PipelineSignature?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lagTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?

    init(settings: SettingsStore, mute: PlaybackMute, permission: MicrophonePermission = .live,
         modelReady: @escaping @MainActor (WhisperModelID) async -> Bool, supplier: @escaping PipelineSupplier,
         speakerStatus: SpeakerStatusRelay? = nil, broadcast: BroadcastCoordinator? = nil) {
        self.settings = settings
        self.mute = mute
        self.permission = permission
        self.modelReady = modelReady
        self.supplier = supplier
        // `nil`, not `SpeakerStatusRelay()`: a default argument is evaluated in the caller's context, which
        // may be nonisolated, and the relay is main-actor isolated. Building it here — inside the isolated
        // init — keeps the convenience without the isolation violation.
        self.speakerStatus = speakerStatus ?? SpeakerStatusRelay()
        if let broadcast {
            observe(broadcast: broadcast)      // stores it and starts draining its events
        }
    }

    // MARK: Inputs

    /// The source picker (§8.2); persisted so `settings.capture` matches what the assembler configures.
    var captureMode: CaptureMode {
        get { settings.settings.capture }
        set { settings.update { $0.captureMode = newValue.rawValue } }
    }

    var isMuted: Bool { mute.isMuted }

    var modelStatusText: String {
        let name = settings.settings.whisperModel.displayName
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
        return configuration
    }

    // MARK: Lifecycle (Windows start / stop / toggle)

    func start() async {
        guard state == .idle || state == .error else { return }
        banner = nil
        sessionStatus = nil
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
        let ready = await modelReady(model)
        modelReadyForStatus = ready
        guard ready else {
            banner = .modelMissing(model)
            return
        }
        setState(.preparing)
        let currentSignature = PipelineSignature(settings: settings.settings)
        if pipeline == nil || signature != currentSignature {
            await tearDownPipeline()
            supplierCallCount += 1
            do {
                let built = try await supplier(settings.settings) { [weak self] message in
                    Task { @MainActor in self?.preparingMessage = message }
                }
                pipeline = built
                signature = currentSignature
                observe(built)
            } catch {
                preparingMessage = nil
                setState(.idle)
                banner = .error(String(describing: error))
                return
            }
        }
        preparingMessage = nil
        guard let pipeline else { return }
        await pipeline.setMuted(mute.isMuted)
        await pipeline.start(Self.configuration(settings: settings.settings, captureMode: captureMode))
    }

    func stop() async {
        await pipeline?.stop()
    }

    func toggle() async {
        switch state {
        case .running:
            await stop()
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
