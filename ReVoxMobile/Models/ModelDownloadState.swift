import Foundation

/// The single UI state of a model row (§6.9): phase, determinate fraction and the catalog size.
struct ModelDownloadState: Equatable, Sendable {
    var phase: ModelDownloadPhase
    var fraction: Double?
    var bytesExpected: Int64
}

extension ModelDownloadState {
    /// The tokenizer snapshot contributes the last 2 % of a Whisper install bar.
    static let tokenizerShare = 0.02

    static func idle(bytesExpected: Int64) -> ModelDownloadState {
        ModelDownloadState(phase: .idle, fraction: nil, bytesExpected: bytesExpected)
    }

    /// WhisperKit reports file-count weighted `Progress`; it fills the first 98 % of the bar.
    static func whisperVariant(_ progress: Progress, bytesExpected: Int64) -> ModelDownloadState {
        let fraction = min(max(progress.fractionCompleted, 0), 1) * (1 - tokenizerShare)
        return ModelDownloadState(phase: .downloading(completedFiles: nil, totalFiles: nil), fraction: fraction, bytesExpected: bytesExpected)
    }

    static func whisperTokenizer(_ progress: Progress, bytesExpected: Int64) -> ModelDownloadState {
        let fraction = (1 - tokenizerShare) + min(max(progress.fractionCompleted, 0), 1) * tokenizerShare
        return ModelDownloadState(phase: .downloading(completedFiles: nil, totalFiles: nil), fraction: fraction, bytesExpected: bytesExpected)
    }

    /// FluidAudio's `DownloadProgress` is byte-weighted over 0–1; the phase is mapped by `ModelInstaller`.
    static func fluidAudio(fractionCompleted: Double, phase: ModelDownloadPhase, bytesExpected: Int64) -> ModelDownloadState {
        ModelDownloadState(phase: phase, fraction: min(max(fractionCompleted, 0), 1), bytesExpected: bytesExpected)
    }
}
