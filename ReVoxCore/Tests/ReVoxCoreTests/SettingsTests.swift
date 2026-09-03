import XCTest
@testable import ReVoxCore

/// Mirrors `tests/test_config.py` (R11 fields).
final class SettingsTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("revox-settings-\(UUID().uuidString)")
            .appendingPathComponent(SettingsCodec.fileName)
    }

    func testDefaults() {
        let settings = Settings()
        XCTAssertEqual(settings.model, "small")
        XCTAssertNil(settings.language)
        XCTAssertEqual(settings.voice, "alba")
        XCTAssertNil(settings.systemVoiceIdentifier)
        XCTAssertTrue(settings.ducking)
        XCTAssertEqual(settings.voiceVolume, 1.0)
        XCTAssertEqual(settings.latencyMode, "balanced")
        XCTAssertEqual(settings.captureMode, "microphone")
        XCTAssertEqual(settings.whisperModel, .small)
        XCTAssertEqual(settings.preset, .balanced)
        XCTAssertEqual(settings.capture, .microphone)
        XCTAssertTrue(settings.usesPocketTTSVoice)
        XCTAssertEqual(SettingsCodec.fileName, "settings.json")
    }

    func testRoundTrip() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = Settings()
        settings.model = "medium"
        settings.language = "es"
        settings.voice = "system"
        settings.systemVoiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        settings.ducking = false
        settings.voiceVolume = 0.5
        settings.latencyMode = "fast"
        settings.captureMode = "broadcast"
        try SettingsCodec.save(settings, to: url)
        XCTAssertEqual(SettingsCodec.load(from: url), settings)
        XCTAssertEqual(SettingsCodec.decode(try SettingsCodec.encode(settings)), settings)
    }

    func testEncodedKeysAreWindowsSnakeCase() throws {
        let json = String(decoding: try SettingsCodec.encode(Settings()), as: UTF8.self)
        for key in ["\"model\"", "\"language\"", "\"voice\"", "\"system_voice_identifier\"", "\"ducking\"",
                    "\"voice_volume\"", "\"latency_mode\"", "\"capture_mode\""] {
            XCTAssertTrue(json.contains(key), key)
        }
        XCTAssertTrue(json.contains("\"language\" : null") || json.contains("\"language\":null"))
    }

    func testMissingFileReturnsDefaults() {
        XCTAssertEqual(SettingsCodec.load(from: temporaryFile()), Settings())
    }

    func testCorruptJSONReturnsDefaults() {
        XCTAssertEqual(SettingsCodec.decode(Data("{not json".utf8)), Settings())
        XCTAssertEqual(SettingsCodec.decode(Data("[1, 2]".utf8)), Settings())    // non-object root
        XCTAssertEqual(SettingsCodec.decode(Data()), Settings())
    }

    func testIgnoresUnknownAndFillsMissing() {
        let settings = SettingsCodec.decode(Data(#"{"model": "medium", "bogus_key": 1}"#.utf8))
        XCTAssertEqual(settings.model, "medium")
        XCTAssertEqual(settings.voice, "alba")
        XCTAssertEqual(settings.whisperModel, .medium)
    }

    func testWrongTypesReturnDefaults() {
        XCTAssertEqual(SettingsCodec.decode(Data(#"{"model": "medium", "ducking": "yes"}"#.utf8)), Settings())
        XCTAssertEqual(SettingsCodec.decode(Data(#"{"voice_volume": "loud"}"#.utf8)), Settings())
    }

    func testWindowsFileDecodes() {
        let windows = #"""
        {
          "model": "auto",
          "device": "auto",
          "language": null,
          "voice": "alba",
          "output_device": null,
          "ducking_level": 0.2,
          "latency_mode": "fast",
          "hotkey_toggle": "ctrl+alt+t",
          "hotkey_mute": "ctrl+alt+m",
          "hotkey_hold": "ctrl+alt+space",
          "transcript_dir": null,
          "start_minimized": false,
          "capture_mode": "system"
        }
        """#
        let settings = SettingsCodec.decode(Data(windows.utf8))
        XCTAssertEqual(settings.model, "auto")
        XCTAssertEqual(settings.whisperModel, .small)          // "auto" is not an iOS model id
        XCTAssertEqual(settings.preset, .fast)
        XCTAssertNil(settings.language)
        XCTAssertTrue(settings.ducking)                        // ducking_level is dropped, the toggle defaults on
        XCTAssertEqual(settings.captureMode, "system")
    }

    func testInvalidLatencyModeMapsToBalanced() {
        var settings = Settings()
        settings.latencyMode = "turbo"
        XCTAssertEqual(settings.preset, .balanced)
    }

    func testInvalidCaptureModeDefaults() {
        var settings = Settings()
        settings.captureMode = "system"                        // the Windows value
        XCTAssertEqual(settings.capture, .microphone)
        settings.captureMode = "app"
        XCTAssertEqual(settings.capture, .microphone)
        settings.captureMode = "broadcast"
        XCTAssertEqual(settings.capture, .broadcast)
    }

    func testUsesPocketTTSVoice() {
        var settings = Settings()
        for voice in ["alba", "azelma", "cosette", "javert"] {
            settings.voice = voice
            XCTAssertTrue(settings.usesPocketTTSVoice, voice)
        }
        settings.voice = "system"
        XCTAssertFalse(settings.usesPocketTTSVoice)
        settings.voice = "jane"                                // a pocket-tts voice that is not offered
        XCTAssertFalse(settings.usesPocketTTSVoice)
    }
}
