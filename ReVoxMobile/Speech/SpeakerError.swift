import Foundation

/// Speaker failures (§6.6; M4 adds the pocket-tts fallback reasons through `SpeakerStatus`).
enum SpeakerError: Error, Equatable, CustomStringConvertible {
    case noVoice
    case synthesisFailed(String)

    var description: String {
        switch self {
        case .noVoice: return "No English system voice; install one in Settings > Accessibility"
        case .synthesisFailed(let reason): return "Speech synthesis failed: \(reason)"
        }
    }
}

/// pocket-tts failures (§6.6, §6.9). Distinct from `SpeakerError` because the fallback rule reads them
/// differently: a load failure retires pocket-tts for the run, a synthesis failure retires it too but the
/// clip is still spoken by the system voice.
enum PocketTTSError: Error, Equatable, CustomStringConvertible {
    case modelNotFound(String)
    case loadFailed(String)
    case synthesisFailed(String)

    var description: String {
        switch self {
        case .modelNotFound(let reason): return "pocket-tts models are not usable: \(reason)"
        case .loadFailed(let reason): return "pocket-tts failed to load: \(reason)"
        case .synthesisFailed(let reason): return "pocket-tts synthesis failed: \(reason)"
        }
    }
}
