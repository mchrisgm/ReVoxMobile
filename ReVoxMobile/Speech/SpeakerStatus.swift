import Foundation
import ReVoxCore

enum SpeakerFallbackReason: Equatable, Sendable {
    case loadFailed(String)
    case synthesisFailed(String)
    case memoryPressure
}

/// Which engine speaks and why, for the Live status line (§8.2, R11) and the player gain (§6.7).
enum SpeakerStatus: Equatable, Sendable {
    case pocketTTS(voice: String)
    case systemSelected
    case systemNotDownloaded
    case fallback(SpeakerFallbackReason)

    static let systemText = "System voice"
    static let notDownloadedText = "System voice — pocket-tts not downloaded"
    static let failedToLoadText = "System voice — pocket-tts failed to load"
    static let failedToSpeakText = "System voice — pocket-tts failed to speak"
    static let memoryLowText = "System voice — memory low"

    var text: String {
        switch self {
        case .pocketTTS(let voice): return "\(voice) (pocket-tts)"
        case .systemSelected: return Self.systemText
        case .systemNotDownloaded: return Self.notDownloadedText
        case .fallback(.loadFailed): return Self.failedToLoadText
        case .fallback(.synthesisFailed): return Self.failedToSpeakText
        case .fallback(.memoryPressure): return Self.memoryLowText
        }
    }

    var usesPocketTTS: Bool {
        if case .pocketTTS = self { return true }
        return false
    }

    var isFallback: Bool {
        if case .fallback = self { return true }
        return false
    }

    /// The fixed gain of §6.7: 0.7 for pocket-tts's un-normalised samples, 1.0 for system-voice clips.
    var engineGain: Float {
        usesPocketTTS ? PlayerNodeSink.pocketTTSEngineGain : 1
    }

    /// The `Session.voice` value of the transcript metadata (§6.10).
    var recordedVoiceName: String {
        if case .pocketTTS(let voice) = self { return voice }
        return "system"
    }
}

/// The per-session choice of R11, evaluated by the assembly before every `start`.
enum SpeakerSelection: Equatable, Sendable {
    case pocketTTS(voice: String, fallbackIdentifier: String?)
    case system(identifier: String?)
    case systemNotDownloaded(identifier: String?)

    /// pocket-tts when installed, verified (`ModelInstaller.isPocketTTSReady`) and `settings.usesPocketTTSVoice`.
    static func choose(settings: Settings, pocketTTSReady: Bool) -> SpeakerSelection {
        guard settings.usesPocketTTSVoice else {
            return .system(identifier: settings.systemVoiceIdentifier)
        }
        return pocketTTSReady
            ? .pocketTTS(voice: settings.voice, fallbackIdentifier: settings.systemVoiceIdentifier)
            : .systemNotDownloaded(identifier: settings.systemVoiceIdentifier)
    }
}
