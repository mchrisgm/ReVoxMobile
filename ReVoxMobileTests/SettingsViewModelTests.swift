import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxSettingsVM-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SettingsStore(fileURL: directory.appendingPathComponent(SettingsCodec.fileName))
    }

    func testRoundTripsSettings() {
        let store = makeStore()
        let model = SettingsViewModel(store: store, mute: PlaybackMute())
        XCTAssertEqual(model.latencyMode, .balanced)
        XCTAssertNil(model.language)

        model.latencyMode = .fast
        model.language = "fr"
        let reread = SettingsStore(fileURL: store.fileURL)
        XCTAssertEqual(reread.settings.latencyMode, "fast")
        XCTAssertEqual(reread.settings.language, "fr")

        model.language = nil
        XCTAssertNil(SettingsStore(fileURL: store.fileURL).settings.language, "Auto-detect stores nil")
    }

    func testVoiceAndModelLists() {
        XCTAssertTrue(SettingsViewModel.voiceNames.contains("alba"))
        XCTAssertTrue(SettingsViewModel.voiceNames.contains("system"))
        XCTAssertTrue(SettingsViewModel.modelNames.contains("large-v3"))
        XCTAssertEqual(SettingsViewModel.modelNames, ["tiny", "base", "small", "medium", "large-v3"])
        XCTAssertFalse(SettingsViewModel.modelNames.contains { $0.contains("turbo") || $0.contains("distil") })
    }

    func testLanguageOptionsSortedWithAutoDetectFirstAndCodeFallback() {
        let options = SettingsViewModel.languageOptions(codes: ["es", "de", "haw", "zz"], locale: Locale(identifier: "en_US"))
        XCTAssertEqual(options.first?.code, nil)
        XCTAssertEqual(options.first?.displayName, SettingsViewModel.autoDetectTitle)
        let names = options.dropFirst().map(\.displayName)
        XCTAssertEqual(names, names.sorted())
        XCTAssertTrue(names.contains("German"))
        XCTAssertTrue(names.contains("Spanish"))
        XCTAssertTrue(names.contains("zz"), "unknown code falls back to the code itself")
        XCTAssertEqual(options.map(\.id).count, Set(options.map(\.id)).count)
    }

    func testLiveLanguageListComesFromWhisperKit() {
        let model = SettingsViewModel(store: makeStore(), mute: PlaybackMute(), locale: Locale(identifier: "en_US"))
        XCTAssertGreaterThan(model.languageOptions.count, 90)
        XCTAssertTrue(model.languageOptions.contains { $0.code == "es" })
        XCTAssertTrue(model.languageOptions.contains { $0.code == "ja" })
    }

    func testMuteMirrorsTheSharedState() {
        let mute = PlaybackMute()
        let model = SettingsViewModel(store: makeStore(), mute: mute)
        model.isMuted = true
        XCTAssertTrue(mute.isMuted)
        mute.isMuted = false
        XCTAssertFalse(model.isMuted)
    }

    func testPresetDescriptionsAreTheWindowsValues() {
        XCTAssertEqual(SettingsViewModel.presetDescription(.balanced), "Silence 500 ms, max 10 s")
        XCTAssertEqual(SettingsViewModel.presetDescription(.fast), "Silence 300 ms, max 4 s")
    }

    // MARK: ducking toggle, voice volume, help text (§8.5, C1)

    func testDuckingAndVoiceVolumeRoundTripAndReachThePlayersBox() {
        let store = makeStore()
        let box = VoiceVolume(1)
        let model = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: box)
        XCTAssertTrue(model.ducking, "R11 default")
        XCTAssertEqual(model.voiceVolume, 1.0)

        model.ducking = false
        model.voiceVolume = 0.4
        XCTAssertEqual(box.current, 0.4, accuracy: 0.0001, "the players read the box at enqueue time")
        let reread = SettingsStore(fileURL: store.fileURL)
        XCTAssertFalse(reread.settings.ducking)
        XCTAssertEqual(reread.settings.voiceVolume, 0.4, accuracy: 0.0001)

        model.voiceVolume = 1.7
        XCTAssertEqual(model.voiceVolume, 1.0, "clamped")
        XCTAssertEqual(box.current, 1)
        model.voiceVolume = -0.2
        XCTAssertEqual(model.voiceVolume, 0)
    }

    func testSavedVoiceVolumeSeedsTheBoxAtLaunch() {
        let store = makeStore()
        store.update { $0.voiceVolume = 0.25 }
        let box = VoiceVolume(1)
        _ = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: box)
        XCTAssertEqual(box.current, 0.25, accuracy: 0.0001)
    }

    func testDuckingHelpTextNamesTheWindowsSlider() {
        XCTAssertEqual(SettingsViewModel.duckingHelpText,
                       "While ReVox speaks, iOS lowers other audio by an amount iOS decides. The Windows ducked-level slider has no iOS equivalent; use Voice volume to balance ReVox's own voice.")
        XCTAssertEqual(SettingsViewModel.duckingAppliesOnStartText, "A change to the ducking toggle takes effect the next time you tap Start.")
    }


    // MARK: M9

    func testTheM9BindingsWriteTheStore() {
        let store = makeStore()
        let model = SettingsViewModel(store: store, mute: PlaybackMute())
        model.keepModelWhenHot = true
        model.learning = true
        model.romanize = true
        model.timeDisplay = .both
        XCTAssertTrue(store.settings.keepModelWhenHot)
        XCTAssertTrue(store.settings.learning)
        XCTAssertTrue(store.settings.romanize)
        XCTAssertEqual(store.settings.timeDisplayMode, .both)
        XCTAssertEqual(SettingsViewModel.timeDisplayTitle(.age), "How long ago")
    }

    /// Every setting has an example that changes with its value: the reader sees what it does, not only what it is.
    func testEveryExampleChangesWithItsValue() {
        XCTAssertNotEqual(SettingExamples.latency(.balanced), SettingExamples.latency(.veryFast))
        XCTAssertTrue(SettingExamples.latency(.veryFast).contains("0.2 s"))
        XCTAssertNotEqual(SettingExamples.ducking(true), SettingExamples.ducking(false))
        XCTAssertEqual(SettingExamples.voiceVolume(0.35), "ReVox's own voice plays at 35 %. Other apps are not affected.")
        XCTAssertNotEqual(SettingExamples.keepModelWhenHot(true, model: .small), SettingExamples.keepModelWhenHot(false, model: .small))
        XCTAssertTrue(SettingExamples.keepModelWhenHot(true, model: .small).contains("small"))
        XCTAssertNotEqual(SettingExamples.learning(true), SettingExamples.learning(false))
        XCTAssertNotEqual(SettingExamples.romanize(true), SettingExamples.romanize(false))
        XCTAssertNotEqual(SettingExamples.timeDisplay(.time), SettingExamples.timeDisplay(.age))
        XCTAssertTrue(SettingExamples.skipLanguage("English").contains("English"))
        XCTAssertTrue(SettingExamples.sourceLanguagePinned("French").contains("French"))
        XCTAssertEqual(SettingExamples.sampleRow().kind, .entry(language: "es", original: "", english: SettingExamples.spanishEnglish))
        XCTAssertEqual(Romanizer.romanize(SettingExamples.japaneseOriginal), "ohayou",
                       "the example is kana on purpose: ICU reads kanji by their Chinese readings")
    }
}
