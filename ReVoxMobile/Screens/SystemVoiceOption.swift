import AVFAudio
import Foundation

/// One English system voice for the Voices screen (§6.6, §8.4): `speechVoices()` filtered to `en*` without novelty
/// voices, sorted premium > enhanced > default, then by name.
struct SystemVoiceOption: Identifiable, Equatable, Sendable {
    let id: String            // AVSpeechSynthesisVoice.identifier, stored in Settings.systemVoiceIdentifier
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    var qualityLabel: String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        case .default: return "Default"
        @unknown default: return "Default"
        }
    }

    static func english(from voices: [AVSpeechSynthesisVoice]) -> [SystemVoiceOption] {
        let options = voices
            .filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .map { SystemVoiceOption(id: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality) }
        return sorted(options)
    }

    static func sorted(_ options: [SystemVoiceOption]) -> [SystemVoiceOption] {
        options.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
            if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
            return lhs.language < rhs.language
        }
    }

    static func installedEnglishVoices() -> [SystemVoiceOption] {
        english(from: AVSpeechSynthesisVoice.speechVoices())
    }
}
