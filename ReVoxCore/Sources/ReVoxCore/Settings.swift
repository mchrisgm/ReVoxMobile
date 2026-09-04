import Foundation

/// Port of `revox/config.py:Settings` (R11): the fields that survive the port, with the Windows JSON key names.
/// Dropped: `device`, `output_device`, `ducking_level`, `hotkey_*`, `transcript_dir`, `start_minimized`.
public struct Settings: Codable, Equatable, Sendable {
    public var model: String = "small"                       // WhisperModelID.rawValue
    public var language: String? = nil                       // nil = auto-detect
    public var voice: String = "alba"                        // pocket-tts voice name or "system"
    public var systemVoiceIdentifier: String? = nil          // AVSpeechSynthesisVoice.identifier
    public var ducking: Bool = true
    public var voiceVolume: Double = 1.0                     // 0.0 … 1.0
    public var latencyMode: String = "balanced"              // SegmenterPreset.rawValue
    public var captureMode: String = "microphone"            // CaptureMode.rawValue
    /// M8: a language ReVox leaves alone — not translated, not transcribed — so a two-person conversation is not
    /// echoed back at the person already speaking it. nil = translate every language.
    public var ignoredLanguage: String? = nil
    /// M8: with two-way on, the ignored language is translated into `twoWayLanguage` instead of being dropped,
    /// and both directions are transcribed.
    public var twoWay: Bool = false
    /// M8: what the ignored language is translated into while two-way is on. nil = English, which needs no
    /// second engine because Whisper's translate task already produces English.
    public var twoWayLanguage: String? = nil
    /// M9: keep the chosen Whisper model through a `.serious` thermal state instead of stepping down to a
    /// smaller installed one for the next session. The `.critical` pause is not affected.
    public var keepModelWhenHot: Bool = false
    /// M9 Learning mode: the words as spoken are transcribed too and shown above the translation.
    public var learning: Bool = false
    /// M9: with Learning on, a Latin transliteration of the original is shown as well.
    public var romanize: Bool = false
    /// M9: what a Live row shows next to its text — `TimeDisplay.rawValue`. History always shows the time.
    public var timeDisplay: String = TimeDisplay.age.rawValue

    public enum TimeDisplay: String, CaseIterable, Sendable {
        case time, age, both
    }

    public init() {}

    public var timeDisplayMode: TimeDisplay { TimeDisplay(rawValue: timeDisplay) ?? .age }

    /// The language ReVox is asked to leave alone, once, so no caller has to remember the empty-string case.
    public var ignored: String? {
        guard let ignoredLanguage, !ignoredLanguage.isEmpty else { return nil }
        return ignoredLanguage
    }

    /// The target of the second direction while two-way is on; nil when two-way is off or the target is English.
    public var twoWayTarget: String? {
        guard twoWay, let twoWayLanguage, !twoWayLanguage.isEmpty, twoWayLanguage != "en" else { return nil }
        return twoWayLanguage
    }

    public var whisperModel: WhisperModelID { WhisperModelID(rawValue: model) ?? .small }
    public var preset: SegmenterPreset { SegmenterPreset(rawValue: latencyMode) ?? .balanced }
    public var capture: CaptureMode { CaptureMode(rawValue: captureMode) ?? .microphone }
    public var usesPocketTTSVoice: Bool { ModelCatalog.pocketTTS.offeredVoices.contains(voice) }

    enum CodingKeys: String, CodingKey {
        case model, language, voice
        case systemVoiceIdentifier = "system_voice_identifier"
        case ducking
        case voiceVolume = "voice_volume"
        case latencyMode = "latency_mode"
        case captureMode = "capture_mode"
        case ignoredLanguage = "ignored_language"
        case twoWay = "two_way"
        case twoWayLanguage = "two_way_language"
        case keepModelWhenHot = "keep_model_when_hot"
        case learning
        case romanize
        case timeDisplay = "time_display"
    }

    /// Missing keys keep their defaults; a wrong type throws, and `SettingsCodec.decode` turns that into `Settings()`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? model
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? language
        voice = try container.decodeIfPresent(String.self, forKey: .voice) ?? voice
        systemVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .systemVoiceIdentifier) ?? systemVoiceIdentifier
        ducking = try container.decodeIfPresent(Bool.self, forKey: .ducking) ?? ducking
        voiceVolume = try container.decodeIfPresent(Double.self, forKey: .voiceVolume) ?? voiceVolume
        latencyMode = try container.decodeIfPresent(String.self, forKey: .latencyMode) ?? latencyMode
        captureMode = try container.decodeIfPresent(String.self, forKey: .captureMode) ?? captureMode
        ignoredLanguage = try container.decodeIfPresent(String.self, forKey: .ignoredLanguage) ?? ignoredLanguage
        twoWay = try container.decodeIfPresent(Bool.self, forKey: .twoWay) ?? twoWay
        twoWayLanguage = try container.decodeIfPresent(String.self, forKey: .twoWayLanguage) ?? twoWayLanguage
        keepModelWhenHot = try container.decodeIfPresent(Bool.self, forKey: .keepModelWhenHot) ?? keepModelWhenHot
        learning = try container.decodeIfPresent(Bool.self, forKey: .learning) ?? learning
        romanize = try container.decodeIfPresent(Bool.self, forKey: .romanize) ?? romanize
        timeDisplay = try container.decodeIfPresent(String.self, forKey: .timeDisplay) ?? timeDisplay
    }

    /// Writes every key (optionals as `null`, like Windows `json.dumps(dataclasses.asdict(settings))`).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(language, forKey: .language)
        try container.encode(voice, forKey: .voice)
        try container.encode(systemVoiceIdentifier, forKey: .systemVoiceIdentifier)
        try container.encode(ducking, forKey: .ducking)
        try container.encode(voiceVolume, forKey: .voiceVolume)
        try container.encode(latencyMode, forKey: .latencyMode)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(ignoredLanguage, forKey: .ignoredLanguage)
        try container.encode(twoWay, forKey: .twoWay)
        try container.encode(twoWayLanguage, forKey: .twoWayLanguage)
        try container.encode(keepModelWhenHot, forKey: .keepModelWhenHot)
        try container.encode(learning, forKey: .learning)
        try container.encode(romanize, forKey: .romanize)
        try container.encode(timeDisplay, forKey: .timeDisplay)
    }
}

public enum SettingsCodec {
    public static let fileName = "settings.json"

    /// Never throws: corrupt JSON, a non-object root or a wrong type → `Settings()` (Windows: `TypeError`/`ValueError` → defaults).
    public static func decode(_ data: Data) -> Settings {
        (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }

    public static func encode(_ settings: Settings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// Missing or unreadable file → `Settings()`.
    public static func load(from url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url) else { return Settings() }
        return decode(data)
    }

    public static func save(_ settings: Settings, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encode(settings).write(to: url, options: .atomic)
    }
}
