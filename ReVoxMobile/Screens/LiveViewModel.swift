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
    static let systemVoiceText = "System voice — pocket-tts not downloaded"

    private(set) var state: LiveState = .idle
    private(set) var stateHistory: [LiveState] = []
    private(set) var rows: [LiveTranscriptRow] = []
    private(set) var isFallingBehind = false
    private(set) var isSpeaking = false
    private(set) var banner: LiveBanner?
    private(set) var preparingMessage: String?
    private(set) var sessionStatus: String?
    private(set) var detectedLanguage: String?
    private(set) var supplierCallCount = 0
    private(set) var modelReadyForStatus: Bool?
    private(set) var lastEventHandledOnMainThread = false
    /// The status line's voice part; M4's `EffectiveSpeaker` status replaces the constant.
    var voiceStatusText = LiveViewModel.systemVoiceText

    private let settings: SettingsStore
    private let mute: PlaybackMute
    private let permission: MicrophonePermission
    private let modelReady: @MainActor (WhisperModelID) async -> Bool
    private let supplier: PipelineSupplier
    @ObservationIgnored private var pipeline: (any LivePipeline)?
    @ObservationIgnored private var signature: PipelineSignature?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var lagTask: Task<Void, Never>?
    @ObservationIgnored private var sessionTask: Task<Void, Never>?

    init(settings: SettingsStore, mute: PlaybackMute, permission: MicrophonePermission = .live,
         modelReady: @escaping @MainActor (WhisperModelID) async -> Bool, supplier: @escaping PipelineSupplier) {
        self.settings = settings
        self.mute = mute
        self.permission = permission
        self.modelReady = modelReady
        self.supplier = supplier
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

    static func configuration(settings: Settings, captureMode: CaptureMode) -> PipelineConfiguration {
        var configuration = PipelineConfiguration(captureMode: captureMode, preset: settings.preset, pinnedLanguage: settings.language)
        configuration.duckingEnabled = false   // M4 wires `settings.ducking`; the M3 controller only records requests
        return configuration
    }

    // MARK: Lifecycle (Windows start / stop / toggle)

    func start() async {
        guard state == .idle || state == .error else { return }
        banner = nil
        sessionStatus = nil
        if captureMode == .microphone, permission.status() == .denied {
            banner = .permissionDenied
            return
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

    private func setState(_ newState: LiveState) {
        guard newState != state else { return }
        state = newState
        stateHistory.append(newState)
    }
}
