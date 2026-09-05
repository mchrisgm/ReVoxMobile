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

    func testThePanelLineNamesBothDirectionsByThePeople() {
        XCTAssertEqual(LiveView.twoWaySummary(you: nil, they: nil), "Choose the language you speak.")
        let same = "You and they both speak English, so there is nothing to translate. Choose the language they speak."
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: nil), same, "nil is English, which is what runs")
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: ""), same)
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: "en"), same)
        XCTAssertEqual(LiveView.twoWaySummary(you: "en", they: "es"),
                       "What you say in English is spoken to them in Spanish; what they say is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWaySummary(you: "es", they: nil),
                       "What you say in Spanish is spoken to them in English; what they say is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWayOffSummary(you: nil),
                       "Two-way is off: everything ReVox hears is spoken to you in English, including what you say.")
        XCTAssertEqual(LiveView.twoWayOffSummary(you: "en"),
                       "Two-way is off: English is not translated and not spoken back at you; everything else is spoken to you in English.")
        XCTAssertEqual(LiveView.twoWayHintText, "Speaks what you say to the other person in their language")
        XCTAssertEqual(LiveView.noLanguageTitle, "Not set")
        for text in [LiveView.twoWaySummary(you: nil, they: nil), same, LiveView.twoWaySummary(you: "en", they: "es"),
                     LiveView.twoWayOffSummary(you: nil), LiveView.twoWayOffSummary(you: "en"), LiveView.twoWayHintText] {
            XCTAssertFalse(text.contains("left alone"), text)
            XCTAssertFalse(text.contains("Reply in"), text)
        }
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
