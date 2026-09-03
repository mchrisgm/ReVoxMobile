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

    private let store: SettingsStore
    private let mute: PlaybackMute
    let languageOptions: [LanguageOption]

    init(store: SettingsStore, mute: PlaybackMute, locale: Locale = .current) {
        self.store = store
        self.mute = mute
        self.languageOptions = Self.languageOptions(codes: Set(Constants.languages.values), locale: locale)
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
