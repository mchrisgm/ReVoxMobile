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
