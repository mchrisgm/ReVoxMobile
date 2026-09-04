import Foundation
import ReVoxCore

/// What ReVox gives up when the device pushes back (§9 rows "Memory warning" and "Thermal state `.serious`", §6.11).
enum DegradationEffect: Equatable, Sendable {
    /// Memory pressure: drop the pocket-tts models; the system voice speaks until the next `prepare` (§6.5).
    case unloadPocketTTS
    /// Use this Whisper model from now on — a smaller installed one under pressure, the user's on recovery.
    /// `restartRunning` says what a session that is already going does: the memory rows switch it at once (the
    /// loaded model is the memory the device wants back), the thermal row does not — §9 asks for the smaller model
    /// "for new sessions", and a teardown plus a full WhisperKit load is the worst thing to do on a hot device.
    case useModel(WhisperModelID, restartRunning: Bool)
    /// Thermal `.critical`: stop translating until the state recovers.
    case pauseTranslation
    /// The thermal state recovered: resume a run that `pauseTranslation` stopped.
    case resumeTranslation
    /// The banner text for the effects above (§9 "User-visible").
    case banner(String)
}

/// What has already been given up. One value per app launch; the coordinator owns it.
struct DegradationState: Equatable, Sendable {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var pocketTTSDropped = false
    /// The reduced model in use, or nil while the user's own model is in use.
    var reducedModel: WhisperModelID?
    var isPausedForHeat = false
    var memoryWarnings = 0

    init() {}
}

/// Pure: one signal in, the effects to apply out. Every threshold here is ASSUMED and gated on the M7 device
/// measurements of §13 Q15 (`docs/measurements/m7-hardening.md`, rows 6–7).
enum DegradationPolicy {
    static let systemVoiceText = "Memory low: switched to the system voice"
    static let heatPausedText = "iPhone is hot: translation paused"
    static let heatReducedText = "iPhone is hot: translation reduced"
    static let heatRecoveredText = "iPhone cooled down: translation resumed"

    static func memoryModelText(_ id: WhisperModelID) -> String { "Memory low: switched to \(id.displayName)" }

    /// `selectedModel` is what the **user** chose (`Settings.model`), never the reduced one, so a recovery can
    /// restore it; `installedModels` is what is on disk right now. `keepModelWhenHot` (M9) is the owner's
    /// "force my model" toggle: a `.serious` thermal state then changes nothing about the model. It does not
    /// touch the `.critical` pause — iOS ends an app that keeps working at critical, and the ask was the model,
    /// not the pause — and it does not touch the memory rows, where the model *is* the memory the device wants.
    static func react(to signal: DeviceSignal, state: inout DegradationState, selectedModel: WhisperModelID,
                      installedModels: [WhisperModelID], usesPocketTTS: Bool, keepModelWhenHot: Bool = false) -> [DegradationEffect] {
        switch signal {
        case .lowPowerMode:
            // §9 has no row for Low Power Mode: it is logged by `DeviceSignals` and changes nothing.
            return []

        case .memoryWarning:
            state.memoryWarnings += 1
            if usesPocketTTS, !state.pocketTTSDropped {
                state.pocketTTSDropped = true
                return [.unloadPocketTTS, .banner(systemVoiceText)]
            }
            return stepDownModel(state: &state, selectedModel: selectedModel, installedModels: installedModels)

        case .thermalState(let thermal):
            state.thermalState = thermal
            switch thermal {
            case .critical:
                guard !state.isPausedForHeat else { return [] }
                state.isPausedForHeat = true
                return [.pauseTranslation, .banner(heatPausedText)]

            case .serious:
                var effects: [DegradationEffect] = []
                if state.isPausedForHeat {
                    state.isPausedForHeat = false
                    effects.append(.resumeTranslation)
                }
                if !keepModelWhenHot, state.reducedModel == nil,
                   let smaller = ModelFallback.smallerInstalledModel(than: selectedModel, installed: installedModels) {
                    state.reducedModel = smaller
                    effects.append(.useModel(smaller, restartRunning: false))
                }
                if effects.contains(where: { if case .useModel = $0 { return true } else { return false } }) {
                    effects.append(.banner(heatReducedText))
                } else if !effects.isEmpty {
                    effects.append(.banner(heatRecoveredText))   // resumed from a pause and kept the model
                }
                return effects

            case .nominal, .fair:
                var effects: [DegradationEffect] = []
                if state.isPausedForHeat {
                    state.isPausedForHeat = false
                    effects.append(.resumeTranslation)
                }
                if state.reducedModel != nil {
                    state.reducedModel = nil
                    effects.append(.useModel(selectedModel, restartRunning: false))
                }
                if !effects.isEmpty { effects.append(.banner(heatRecoveredText)) }
                return effects

            @unknown default:
                return []
            }
        }
    }

    /// §9 memory row, second half: "if Whisper **was evicted or fails next call**, drop to a smaller installed
    /// model". The recovering translator has already spent its one unload/reload retry by the time this is called,
    /// so a failure that follows a memory warning is the eviction the row names. A failure with no memory warning
    /// behind it is a broken model, not device pressure: the load-failure fallback and the retry own that case, and
    /// nothing degrades here.
    static func reactToWhisperFailure(state: inout DegradationState, selectedModel: WhisperModelID,
                                      installedModels: [WhisperModelID]) -> [DegradationEffect] {
        guard state.memoryWarnings > 0 else { return [] }
        return stepDownModel(state: &state, selectedModel: selectedModel, installedModels: installedModels)
    }

    /// One step down the catalog from whatever is in use, shared by a further memory warning and a Whisper failure
    /// after one. Empty when nothing smaller is installed — there is nothing left to give up.
    private static func stepDownModel(state: inout DegradationState, selectedModel: WhisperModelID,
                                      installedModels: [WhisperModelID]) -> [DegradationEffect] {
        guard let smaller = ModelFallback.smallerInstalledModel(than: state.reducedModel ?? selectedModel,
                                                                installed: installedModels) else { return [] }
        state.reducedModel = smaller
        return [.useModel(smaller, restartRunning: true), .banner(memoryModelText(smaller))]
    }
}
