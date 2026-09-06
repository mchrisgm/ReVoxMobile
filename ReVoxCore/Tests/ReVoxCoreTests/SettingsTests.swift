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
                    "\"voice_volume\"", "\"latency_mode\"", "\"capture_mode\"", "\"keep_guesses\""] {
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
        for voice in ["alba", "azelma", "javert"] {
            settings.voice = voice
            XCTAssertTrue(settings.usesPocketTTSVoice, voice)
        }
        settings.voice = "system"
        XCTAssertFalse(settings.usesPocketTTSVoice)
        settings.voice = "jane"                                // a pocket-tts voice that is not offered
        XCTAssertFalse(settings.usesPocketTTSVoice)
        settings.voice = "cosette"                             // offered before 1.0.0; a saved choice now means the system voice
        XCTAssertFalse(settings.usesPocketTTSVoice)
    }

    // MARK: Ignored language and two-way (M8)

    func testTheNewFieldsDefaultToTheOneWayBehaviour() {
        let settings = Settings()
        XCTAssertNil(settings.ignoredLanguage)
        XCTAssertFalse(settings.twoWay)
        XCTAssertNil(settings.twoWayLanguage)
        XCTAssertNil(settings.ignored)
        XCTAssertNil(settings.twoWayTarget)
    }

    func testIgnoredAndTargetIgnoreEmptyStringsAndEnglish() {
        var settings = Settings()
        settings.ignoredLanguage = ""
        XCTAssertNil(settings.ignored, "an empty code is not a language")
        settings.ignoredLanguage = "en"
        XCTAssertEqual(settings.ignored, "en")

        settings.twoWayLanguage = "es"
        XCTAssertNil(settings.twoWayTarget, "two-way is off, so there is no target")
        settings.twoWay = true
        XCTAssertEqual(settings.twoWayTarget, "es")
        settings.twoWayLanguage = "en"
        XCTAssertNil(settings.twoWayTarget, "English needs no second engine; Whisper already produces it")
        settings.twoWayLanguage = ""
        XCTAssertNil(settings.twoWayTarget)
    }

    func testTheNewFieldsRoundTripThroughTheWindowsSnakeCaseKeys() throws {
        var settings = Settings()
        settings.ignoredLanguage = "en"
        settings.twoWay = true
        settings.twoWayLanguage = "es"
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["ignored_language"] as? String, "en")
        XCTAssertEqual(object["two_way"] as? Bool, true)
        XCTAssertEqual(object["two_way_language"] as? String, "es")
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
    }

    /// A settings file written before M8 has none of these keys and must keep working unchanged.
    func testASettingsFileFromBeforeM8Decodes() throws {
        let json = Data(#"{"model":"small","language":null,"voice":"alba","ducking":true}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertNil(settings.ignoredLanguage)
        XCTAssertFalse(settings.twoWay)
        XCTAssertNil(settings.twoWayLanguage)
        XCTAssertEqual(settings.voice, "alba")
    }

    // MARK: M9

    func testTheM9FieldsDefaultToOff() {
        let settings = Settings()
        XCTAssertFalse(settings.keepModelWhenHot)
        XCTAssertFalse(settings.learning)
        XCTAssertFalse(settings.romanize)
        XCTAssertEqual(settings.timeDisplayMode, .age, "a running conversation is followed by how long ago, not when")
    }

    func testTheM9FieldsRoundTripThroughSnakeCaseKeys() throws {
        var settings = Settings()
        settings.keepModelWhenHot = true
        settings.learning = true
        settings.romanize = true
        settings.timeDisplay = "both"
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["keep_model_when_hot"] as? Bool, true)
        XCTAssertEqual(object["learning"] as? Bool, true)
        XCTAssertEqual(object["romanize"] as? Bool, true)
        XCTAssertEqual(object["time_display"] as? String, "both")
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
        XCTAssertEqual(settings.timeDisplayMode, .both)
    }

    func testAnUnknownTimeDisplayFallsBackToAge() {
        var settings = Settings()
        settings.timeDisplay = "sundial"
        XCTAssertEqual(settings.timeDisplayMode, .age)
    }

    /// A settings file written before M9 has none of these keys and must keep working unchanged.
    func testASettingsFileFromBeforeM9Decodes() throws {
        let json = Data(#"{"model":"small","language":null,"voice":"alba","ducking":true,"two_way":true}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertFalse(settings.keepModelWhenHot)
        XCTAssertFalse(settings.learning)
        XCTAssertEqual(settings.timeDisplayMode, .age)
        XCTAssertTrue(settings.twoWay)
    }

    func testAnIntegerVoiceVolumeDecodesAsADouble() {
        let settings = SettingsCodec.decode(Data(#"{"voice_volume": 1}"#.utf8))
        XCTAssertEqual(settings.voiceVolume, 1.0)
        XCTAssertEqual(SettingsCodec.decode(Data(#"{"voice_volume": 0}"#.utf8)).voiceVolume, 0)
    }

    func testExplicitNullsKeepTheOptionalsEmptyAndTheDefaultsForTheRest() {
        let json = #"{"language": null, "system_voice_identifier": null, "ignored_language": null, "two_way_language": null, "keep_guesses": null}"#
        let settings = SettingsCodec.decode(Data(json.utf8))
        XCTAssertEqual(settings, Settings())
    }

    // MARK: Unsure phrases (M11)

    func testTheM11FieldDefaultsToKeepingGuesses() {
        XCTAssertTrue(Settings().keepGuesses, "History matches what Live showed unless the user turns it off")
    }

    func testTheM11FieldRoundTripsThroughSnakeCase() throws {
        var settings = Settings()
        settings.keepGuesses = false
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["keep_guesses"] as? Bool, false)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
        XCTAssertNotEqual(settings, Settings(), "the field is part of equality")
    }

    /// A settings file written before M11 has no `keep_guesses` and keeps the default.
    func testASettingsFileFromBeforeM11Decodes() throws {
        let json = Data(#"{"model":"small","language":null,"voice":"alba","ducking":true,"learning":true}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertTrue(settings.keepGuesses)
        XCTAssertTrue(settings.learning)
        XCTAssertEqual(SettingsCodec.decode(Data(#"{"keep_guesses": false}"#.utf8)).keepGuesses, false)
    }

    func testSaveCreatesTheDirectoryAndOverwritesAtomically() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        try SettingsCodec.save(Settings(), to: url)
        var changed = Settings()
        changed.voice = "javert"
        try SettingsCodec.save(changed, to: url)
        XCTAssertEqual(SettingsCodec.load(from: url).voice, "javert")
    }
}
