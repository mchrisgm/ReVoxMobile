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

    public init() {}

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
