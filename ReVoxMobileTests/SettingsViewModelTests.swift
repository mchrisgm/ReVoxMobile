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
}
