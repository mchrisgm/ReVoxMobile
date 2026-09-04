import Foundation
import Observation
import os
import ReVoxCore

/// What the coordinator is allowed to do, injected so the tests never need the audio stack.
struct DegradationActions: Sendable {
    var unloadPocketTTS: @MainActor () async -> Void
    /// The model to use and whether a session that is already running is rebuilt on it now (§9: yes for the memory
    /// rows, no for the thermal row, which asks for the smaller model "for new sessions").
    var useModel: @MainActor (WhisperModelID, Bool) async -> Void
    var pause: @MainActor () async -> Void
    var resume: @MainActor () async -> Void
    var showBanner: @MainActor (String) -> Void
}

/// Drains `DeviceSignals` and applies `DegradationPolicy` (§9 memory and thermal rows, §6.11). One per app launch.
@MainActor
@Observable
final class DegradationCoordinator {
    private static let logger = Logger(subsystem: "revox", category: "degradation")

    private(set) var state = DegradationState()
    /// Every effect that was applied, in order; the M7 measurement record reads it from a debug build.
    private(set) var appliedEffects: [DegradationEffect] = []

    @ObservationIgnored private let signals: AsyncStream<DeviceSignal>
    @ObservationIgnored private let selectedModel: @MainActor () -> WhisperModelID
    @ObservationIgnored private let installedModels: @MainActor () -> [WhisperModelID]
    @ObservationIgnored private let usesPocketTTS: @MainActor () -> Bool
    @ObservationIgnored private let actions: DegradationActions
    @ObservationIgnored private var task: Task<Void, Never>?

    init(signals: AsyncStream<DeviceSignal>,
         selectedModel: @escaping @MainActor () -> WhisperModelID,
         installedModels: @escaping @MainActor () -> [WhisperModelID],
         usesPocketTTS: @escaping @MainActor () -> Bool,
         actions: DegradationActions) {
        self.signals = signals
        self.selectedModel = selectedModel
        self.installedModels = installedModels
        self.usesPocketTTS = usesPocketTTS
        self.actions = actions
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let stream = self?.signals else { return }
            for await signal in stream {
                await self?.handle(signal)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One signal: decide, then apply the effects in order.
    func handle(_ signal: DeviceSignal) async {
        let effects = DegradationPolicy.react(to: signal, state: &state, selectedModel: selectedModel(),
                                              installedModels: installedModels(), usesPocketTTS: usesPocketTTS())
        guard !effects.isEmpty else {
            Self.logger.info("signal with no effect thermal=\(String(describing: self.state.thermalState), privacy: .public)")
            return
        }
        appliedEffects.append(contentsOf: effects)
        for effect in effects {
            await apply(effect)
        }
    }

    /// §9 memory row, "if Whisper was evicted **or fails next call**": the recovering translator spent its one
    /// unload/reload retry, or the reload itself failed. After a memory warning that is the eviction signal and the
    /// model steps down; with no memory warning behind it nothing happens here (the load-failure fallback and the
    /// retry own that failure).
    func whisperFailed() async {
        let effects = DegradationPolicy.reactToWhisperFailure(state: &state, selectedModel: selectedModel(),
                                                              installedModels: installedModels())
        guard !effects.isEmpty else { return }
        Self.logger.notice("whisper failed after \(self.state.memoryWarnings, privacy: .public) memory warning(s)")
        appliedEffects.append(contentsOf: effects)
        for effect in effects {
            await apply(effect)
        }
    }

    /// The `@Sendable` handle `PipelineAssembler.whisperRecovery` carries into every built pipeline.
    /// A successful `.reloaded` is not an eviction — only a spent retry or a failed reload is.
    nonisolated func recoveryEventHandler() -> @Sendable (RecoveringTranslator.RecoveryEvent) -> Void {
        { [weak self] event in
            switch event {
            case .reloaded:
                return
            case .reloadFailed, .gaveUp:
                Task { @MainActor in await self?.whisperFailed() }
            }
        }
    }

    private func apply(_ effect: DegradationEffect) async {
        switch effect {
        case .unloadPocketTTS:
            Self.logger.notice("memory pressure: dropping pocket-tts")
            await actions.unloadPocketTTS()
        case .useModel(let model, let restartRunning):
            Self.logger.notice("switching to model=\(model.rawValue, privacy: .public) restartRunning=\(restartRunning, privacy: .public)")
            await actions.useModel(model, restartRunning)
        case .pauseTranslation:
            Self.logger.notice("thermal critical: pausing translation")
            await actions.pause()
        case .resumeTranslation:
            Self.logger.notice("thermal recovered: resuming translation")
            await actions.resume()
        case .banner(let text):
            actions.showBanner(text)
        }
    }
}
