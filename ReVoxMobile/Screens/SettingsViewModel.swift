import Foundation
import Observation
import ReVoxCore
import WhisperKit

@MainActor
@Observable
final class SettingsViewModel {
    static let autoDetectTitle = "Auto-detect"
    static let modelNames: [String] = WhisperModelID.allCases.map(\.displayName)
    static let voiceNames: [String] = ModelCatalog.pocketTTS.offeredVoices + ["system"]
    /// C1: the README and this footer say the Windows ducked-level slider has no iOS equivalent.
    static let duckingHelpText = "While ReVox speaks, iOS lowers other audio by an amount iOS decides. The Windows ducked-level slider has no iOS equivalent; use Voice volume to balance ReVox's own voice."
    static let duckingAppliesOnStartText = "A change to the ducking toggle takes effect the next time you tap Start."

    private let store: SettingsStore
    private let mute: PlaybackMute
    private let volume: VoiceVolume
    let languageOptions: [LanguageOption]

    init(store: SettingsStore, mute: PlaybackMute, voiceVolume: VoiceVolume = VoiceVolume(), locale: Locale = .current) {
        self.store = store
        self.mute = mute
        self.volume = voiceVolume
        self.languageOptions = Self.languageOptions(codes: Set(Constants.languages.values), locale: locale)
        voiceVolume.current = Float(store.settings.voiceVolume)   // seed the players' box from the saved value
    }

    var latencyMode: SegmenterPreset {
        get { store.settings.preset }
        set { store.update { $0.latencyMode = newValue.rawValue } }
    }

    var language: String? {
        get { store.settings.language }
        set { store.update { $0.language = newValue } }
    }

    var isMuted: Bool {
        get { mute.isMuted }
        set { mute.isMuted = newValue }
    }

    /// R11 `ducking`; read by `LiveViewModel.configuration` at every start.
    var ducking: Bool {
        get { store.settings.ducking }
        set { store.update { $0.ducking = newValue } }
    }

    /// R11 `voiceVolume`, 0…1; written to the shared box so the next clip uses it (§6.7, §8.5).
    var voiceVolume: Double {
        get { store.settings.voiceVolume }
        set {
            let clamped = min(max(newValue, 0), 1)
            store.update { $0.voiceVolume = clamped }
            volume.current = Float(clamped)
        }
    }

    /// The Windows preset values (§5.1): balanced 500 ms / 10 s, fast 300 ms / 4 s.
    static func presetDescription(_ preset: SegmenterPreset) -> String {
        "Silence \(preset.silenceMs) ms, max \(Int(preset.maxSegmentSeconds)) s"
    }

    /// "Auto-detect" first, then the codes by localized display name (the code when the locale has no name).
    static func languageOptions(codes: Set<String>, locale: Locale) -> [LanguageOption] {
        let named = codes.map { code -> LanguageOption in
            let name = locale.localizedString(forLanguageCode: code) ?? code
            return LanguageOption(code: code, displayName: name)
        }
        .sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName { return (lhs.code ?? "") < (rhs.code ?? "") }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return [LanguageOption(code: nil, displayName: autoDetectTitle)] + named
    }
}
