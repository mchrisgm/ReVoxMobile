import Foundation
import Observation
import ReVoxCore
import WhisperKit

@MainActor
@Observable
final class SettingsViewModel {
    static let autoDetectTitle = LanguageCatalog.autoDetectTitle
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
        self.languageOptions = LanguageCatalog.languageOptions(codes: Set(Constants.languages.values), locale: locale)
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

    /// The preset values (§5.1): balanced 500 ms / 10 s, fast 300 ms / 4 s, very fast 200 ms / 3 s (M9).
    static func presetDescription(_ preset: SegmenterPreset) -> String {
        "Silence \(preset.silenceMs) ms, max \(Int(preset.maxSegmentSeconds)) s"
    }

    // MARK: M9

    /// §9 thermal row, overridden: the chosen model stays through a `.serious` thermal state.
    var keepModelWhenHot: Bool {
        get { store.settings.keepModelWhenHot }
        set { store.update { $0.keepModelWhenHot = newValue } }
    }

    var learning: Bool {
        get { store.settings.learning }
        set { store.update { $0.learning = newValue } }
    }

    var romanize: Bool {
        get { store.settings.romanize }
        set { store.update { $0.romanize = newValue } }
    }

    /// The model the heat example names.
    var selectedModel: WhisperModelID { store.settings.whisperModel }

    var timeDisplay: Settings.TimeDisplay {
        get { store.settings.timeDisplayMode }
        set { store.update { $0.timeDisplay = newValue.rawValue } }
    }

    static let keepModelWhenHotHelpText = "When the iPhone gets hot, ReVox normally switches the next session to a smaller model and says so. With this on, your chosen model is kept. Translation still pauses if the iPhone reaches its critical temperature; iOS would close the app otherwise."
    static let learningHelpText = "Shows the words as they were spoken above the translation. Each phrase is decoded a second time, so it takes a little longer to appear."
    static let romanizeHelpText = "Adds how the original sounds in Latin letters, for scripts you cannot read yet. Only shown when it differs from the original. Japanese kanji come out with their Chinese readings; kana are right."
    static let timeDisplayHelpText = "How long ago a phrase was said is easier to follow in a running conversation than the time it was said. History always shows the time."

    static func timeDisplayTitle(_ mode: Settings.TimeDisplay) -> String {
        switch mode {
        case .time: return "Time"
        case .age: return "How long ago"
        case .both: return "Both"
        }
    }

    /// Kept as the screen's own entry point; `LanguageCatalog` is where the list is built (§8.5).
    static func languageOptions(codes: Set<String>, locale: Locale) -> [LanguageOption] {
        LanguageCatalog.languageOptions(codes: codes, locale: locale)
    }

    /// §8.2 (M8): the language ReVox leaves alone. "None" is the pre-M8 behaviour — everything is translated.
    var ignoredLanguage: String? {
        get { store.settings.ignored }
        set { store.update { $0.ignoredLanguage = newValue } }
    }

    /// The concrete languages the ignore picker offers, with "None" as the first row.
    var ignoredLanguageOptions: [LanguageOption] {
        [LanguageOption(code: nil, displayName: Self.noIgnoredLanguageTitle)] + LanguageCatalog.concrete
    }

    static let noIgnoredLanguageTitle = "None"
    static let ignoredLanguageHelpText = "ReVox neither translates nor transcribes this language. Turn on Two-way on the Live screen to have it spoken back in another language instead."
    static let ignoredLanguageNeedsAutoDetectText = "Ignoring a language needs Source language set to Auto-detect, because a pinned language is never detected."
}
