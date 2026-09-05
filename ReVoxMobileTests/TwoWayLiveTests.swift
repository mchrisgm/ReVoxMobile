import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// §8.2 (M8): the language the user leaves alone, the second direction, and the copy the Live screen shows for
/// both. The routing itself is ReVoxCore's; what is checked here is that the screen's settings reach it.
@MainActor
final class TwoWayLiveTests: XCTestCase {
    private func store() -> SettingsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxTwoWay-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SettingsStore(fileURL: directory.appendingPathComponent(SettingsCodec.fileName))
    }

    private func liveModel(_ settings: SettingsStore) -> LiveViewModel {
        LiveViewModel(settings: settings, mute: PlaybackMute(), permission: .fixed(.granted),
                      modelReady: { _ in true }, supplier: { _, _ in FakeLivePipeline() })
    }

    // MARK: The settings reach the pipeline configuration

    func testWithNothingIgnoredTheConfigurationIsUnchanged() {
        let configuration = LiveViewModel.configuration(settings: Settings(), captureMode: .microphone)
        XCTAssertNil(configuration.ignoredLanguage)
        XCTAssertFalse(configuration.twoWay)
        XCTAssertNil(configuration.twoWayLanguage)
    }

    func testTheIgnoredLanguageAndTheSecondDirectionReachTheConfiguration() {
        var settings = Settings()
        settings.ignoredLanguage = "en"
        settings.twoWay = true
        settings.twoWayLanguage = "es"
        let configuration = LiveViewModel.configuration(settings: settings, captureMode: .microphone)
        XCTAssertEqual(configuration.ignoredLanguage, "en")
        XCTAssertTrue(configuration.twoWay)
        XCTAssertEqual(configuration.twoWayLanguage, "es")
    }

    func testAnEmptyIgnoredLanguageIsNoIgnoredLanguage() {
        var settings = Settings()
        settings.ignoredLanguage = ""
        XCTAssertNil(LiveViewModel.configuration(settings: settings, captureMode: .microphone).ignoredLanguage)
    }

    // MARK: The pair handed to Apple's translator

    func testNoPairIsServedUntilBothLanguagesAreChosenAndTwoWayIsOn() {
        let live = liveModel(store())
        live.ignoredLanguage = "en"
        XCTAssertNil(live.twoWayPair, "two-way is off")
        live.isTwoWay = true
        XCTAssertNil(live.twoWayPair, "no reply language yet")
        live.twoWayLanguage = "es"
        XCTAssertEqual(live.twoWayPair?.source, "en")
        XCTAssertEqual(live.twoWayPair?.target, "es")
    }

    func testALanguageIsNeverTranslatedIntoItself() {
        let live = liveModel(store())
        live.ignoredLanguage = "es"
        live.isTwoWay = true
        live.twoWayLanguage = "es"
        XCTAssertNil(live.twoWayPair)
    }

    /// English is the pair Whisper's own translate task already produces, so no second engine is needed for it.
    func testEnglishAsTheReplyLanguageNeedsNoSecondEngine() {
        let live = liveModel(store())
        live.ignoredLanguage = "es"
        live.isTwoWay = true
        live.twoWayLanguage = "en"
        XCTAssertNil(live.twoWayPair, "no Apple session is attached for a direction Whisper covers")
    }

    // MARK: A transcript-only phrase is explained rather than silent

    func testATranscriptOnlyPhraseRaisesADismissibleNote() {
        let live = liveModel(store())
        XCTAssertNil(live.transcriptOnlyNote)
        live.handle(.transcriptOnly(reason: TranslationStage.noEngineReason))
        XCTAssertEqual(live.transcriptOnlyNote, TranslationStage.noEngineReason)
        live.dismissTranscriptOnlyNote()
        XCTAssertNil(live.transcriptOnlyNote)
    }

    // MARK: Copy

    func testTheToggleSubtitleNamesWhatTwoWayWillDo() {
        XCTAssertEqual(LiveView.twoWaySummary(ignored: nil, target: nil), "Choose a language to leave alone")
        XCTAssertEqual(LiveView.twoWaySummary(ignored: "en", target: nil), "English is left alone")
        XCTAssertEqual(LiveView.twoWaySummary(ignored: "en", target: "es"), "English is spoken back in Spanish")
    }

    func testTheStartButtonSaysWhatTheStateIs() {
        XCTAssertEqual(LiveView.buttonTitle(for: .idle), "Start")
        XCTAssertEqual(LiveView.buttonTitle(for: .error), "Start")
        XCTAssertEqual(LiveView.buttonTitle(for: .preparing), "Preparing…")
        XCTAssertEqual(LiveView.buttonTitle(for: .running), "Stop")
        XCTAssertEqual(LiveView.buttonAccessibilityLabel(for: .preparing), "Preparing the model")
    }

    func testEachSourceSaysWhatItListensTo() {
        XCTAssertEqual(LiveView.description(for: .microphone), LiveView.microphoneDescription)
        XCTAssertEqual(LiveView.description(for: .broadcast), LiveView.broadcastDescription)
        XCTAssertNotEqual(LiveView.symbol(for: .microphone), LiveView.symbol(for: .broadcast))
    }

    /// A language iOS has no voice for is called out while it is being chosen, not discovered as silence.
    func testAReplyLanguageWithNoVoiceIsCalledOut() {
        XCTAssertNil(LiveViewModel.voiceNote(for: nil))
        XCTAssertNotNil(LiveViewModel.voiceNote(for: "zz"), "no iPhone ships a voice for a code that is not a language")
        XCTAssertNil(LiveViewModel.voiceNote(for: "en"), "every iPhone speaks English")
        let note = LiveViewModel.voiceNote(for: "zz")
        XCTAssertEqual(note, "This iPhone has no zz voice, so what you say to them stays in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices.")
        let live = liveModel(store())
        XCTAssertNil(live.twoWayVoiceNote)
        live.twoWayLanguage = "zz"
        XCTAssertNotNil(live.twoWayVoiceNote, "choosing the language is when the note appears")
    }
}
