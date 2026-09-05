import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// M9: the Live screen's quick controls, the Learning mode plumbing and the leading column of a row.
@MainActor
final class LiveControlsTests: XCTestCase {
    private func store() -> SettingsStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxControls-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SettingsStore(fileURL: directory.appendingPathComponent(SettingsCodec.fileName))
    }

    private func liveModel(_ settings: SettingsStore) -> LiveViewModel {
        LiveViewModel(settings: settings, mute: PlaybackMute(), permission: .fixed(.granted),
                      modelReady: { _ in true }, supplier: { _, _ in FakeLivePipeline() })
    }

    func testLatencyFromTheLiveScreenInvalidatesTheCachedPipelineLikeSettingsDoes() async {
        let settings = store()
        let live = liveModel(settings)
        await live.start()
        await waitUntil("running") { live.state == .running }
        await live.stopByUser()
        await waitUntil("idle") { live.state == .idle }
        XCTAssertEqual(live.supplierCallCount, 1)
        live.latencyMode = .veryFast
        XCTAssertEqual(settings.settings.preset, .veryFast)
        await live.start()
        await waitUntil("running again") { live.state == .running }
        XCTAssertEqual(live.supplierCallCount, 2, "a new preset means a new pipeline")
        await live.stopByUser()
    }

    func testDuckingAndLearningReachTheNextConfiguration() {
        let settings = store()
        let live = liveModel(settings)
        live.ducking = false
        live.isLearning = true
        let configuration = LiveViewModel.configuration(settings: settings.settings, captureMode: .microphone)
        XCTAssertFalse(configuration.duckingEnabled)
        XCTAssertTrue(configuration.wantsOriginal, "Learning mode asks the stage for the words as spoken")
    }

    func testVoiceVolumeIsLiveThroughThePlayersBox() {
        let settings = store()
        let live = liveModel(settings)
        let box = VoiceVolume(1)
        live.volume = box
        live.voiceVolume = 0.35
        XCTAssertEqual(settings.settings.voiceVolume, 0.35)
        XCTAssertEqual(box.current, 0.35, accuracy: 0.001, "the next clip plays at the new level without a restart")
        live.voiceVolume = 4
        XCTAssertEqual(settings.settings.voiceVolume, 1, "clamped")
    }

    func testTheLeadingColumnFollowsTheTimeDisplaySetting() {
        let said = Date(timeIntervalSince1970: 1_700_000_000)
        let now = said.addingTimeInterval(12)
        let clock = said.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        XCTAssertEqual(LiveTranscriptRowView.leadingText(time: said, now: now, display: .age), "12 s")
        XCTAssertEqual(LiveTranscriptRowView.leadingText(time: said, now: now, display: .time), clock)
        XCTAssertEqual(LiveTranscriptRowView.leadingText(time: said, now: now, display: .both), "12 s · \(clock)")
        XCTAssertEqual(LiveTranscriptRowView.leadingText(time: said, now: nil, display: .age), clock,
                       "History passes no clock and always gets the time: an age means nothing a day later")
    }

    func testTheOriginalReachesTheLiveRowAndTheSessionRow() {
        let live = liveModel(store())
        live.handle(.entry(TranscriptEntry(timestamp: Date(), language: "es", original: "Buenos días.", english: "Good morning.")))
        XCTAssertEqual(live.rows.first?.kind, .entry(language: "es", original: "Buenos días.", english: "Good morning."))
        let entry = Entry(timestamp: Date(), language: "ja", original: "おはよう", english: "Good morning.", isDropMarker: false)
        XCTAssertEqual(SessionDetailRows.row(for: entry).kind, .entry(language: "ja", original: "おはよう", english: "Good morning."))
        XCTAssertEqual(LiveTranscriptRow.Kind.entry(language: "es", english: "x"),
                       .entry(language: "es", original: "", english: "x"), "the pre-M9 shape still works")
    }

    func testTheHistoryButtonsCountTheSelection() {
        XCTAssertEqual(HistoryView.mergeButtonTitle(count: 0), "Merge")
        XCTAssertEqual(HistoryView.mergeButtonTitle(count: 3), "Merge (3)")
        XCTAssertEqual(HistoryView.deleteButtonTitle(count: 2), "Delete (2)")
    }

    // MARK: M10 — the control strip

    /// The pipeline reads source, latency, ducking, Learning and two-way once at Start, so the strip locks them
    /// from the moment the model starts loading, not only once audio flows.
    func testTheStripLocksTheStartTimeControlsWhilePreparingAndRunning() {
        XCTAssertFalse(LiveControlStrip.locksControls(in: .idle))
        XCTAssertFalse(LiveControlStrip.locksControls(in: .error))
        XCTAssertTrue(LiveControlStrip.locksControls(in: .preparing))
        XCTAssertTrue(LiveControlStrip.locksControls(in: .running))
        XCTAssertEqual(LiveControlStrip.lockedText, "Stop to change", "one shared hint, not a caption per control")
        XCTAssertNotEqual(LiveControlStrip.lockedText, LiveView.lockedWhileRunningText, "the M8 copy is still what VoiceOver hears")
    }

    func testEachPillSaysItsValueInAFewCharacters() {
        XCTAssertEqual(LiveControlStrip.sourcePillTitle(for: .microphone), "Mic")
        XCTAssertEqual(LiveControlStrip.sourcePillTitle(for: .broadcast), LiveView.title(for: .broadcast))
        XCTAssertEqual(LiveControlStrip.togglePillTitle(LiveControlStrip.duckingPillName, isOn: true), "Duck on")
        XCTAssertEqual(LiveControlStrip.togglePillTitle(LiveControlStrip.learningPillName, isOn: false), "Learn off")
        XCTAssertEqual(LiveControlStrip.togglePillTitle(LiveControlStrip.twoWayPillName, isOn: true), "Two-way on")
        XCTAssertEqual(LiveControlStrip.moreTitle(expanded: false), "More")
        XCTAssertEqual(LiveControlStrip.moreTitle(expanded: true), "Less")
        for preset in SegmenterPreset.allCases {
            XCTAssertFalse(LiveControlStrip.latencySymbol(for: preset).isEmpty)
            XCTAssertTrue(LiveControlStrip.latencyDetailText(for: preset).hasPrefix(SettingsView.title(for: preset)))
            XCTAssertTrue(LiveControlStrip.latencyDetailText(for: preset).hasSuffix(SettingsViewModel.presetDescription(preset)))
        }
        XCTAssertEqual(Set(SegmenterPreset.allCases.map(LiveControlStrip.latencySymbol(for:))).count, 3, "each preset has its own gauge")
    }

    func testTheVolumePillRoundsToWholePercentAndSpeaksTheWord() {
        XCTAssertEqual(LiveControlStrip.volumePillText(0.8), "80%")
        XCTAssertEqual(LiveControlStrip.volumePillText(0.804), "80%")
        XCTAssertEqual(LiveControlStrip.volumePercentText(0.35), "35 percent")
        XCTAssertEqual(LiveControlStrip.volumePercent(4), 100, "clamped like the setter")
        XCTAssertEqual(LiveControlStrip.volumePercent(-1), 0)
        XCTAssertEqual(LiveControlStrip.volumeSymbol(for: 0), "speaker.slash")
        XCTAssertEqual(LiveControlStrip.volumeSymbol(for: 0.2), "speaker.wave.1")
        XCTAssertEqual(LiveControlStrip.volumeSymbol(for: 0.5), "speaker.wave.2")
        XCTAssertEqual(LiveControlStrip.volumeSymbol(for: 1), "speaker.wave.3")
    }

    /// "Ducking off" is the strip's pill now; the status line's badge is for the moment other audio is lowered.
    func testTheStatusLineShowsDuckingOnlyWhileDucked() {
        XCTAssertNil(LiveView.duckingBadge(isDucked: false, status: LiveViewModel.duckingOffText))
        XCTAssertNil(LiveView.duckingBadge(isDucked: false, status: nil))
        XCTAssertEqual(LiveView.duckingBadge(isDucked: true, status: LiveViewModel.duckingText), LiveViewModel.duckingText)
    }

    // MARK: M11 — You speak / They speak

    func testTheySpeakShowsEnglishUntilOneIsStored() {
        let settings = store()
        let live = liveModel(settings)
        XCTAssertEqual(live.theySpeak, "en")
        XCTAssertNil(settings.settings.twoWayLanguage, "English is the stored nil, as on Windows")
        live.ignoredLanguage = "en"
        live.isTwoWay = true
        live.theySpeak = "es"
        XCTAssertEqual(settings.settings.twoWayLanguage, "es")
        XCTAssertEqual(live.twoWayPair?.source, "en")
        XCTAssertEqual(live.twoWayPair?.target, "es")
        live.theySpeak = "en"
        XCTAssertNil(settings.settings.twoWayLanguage, "choosing English stores nil")
        XCTAssertNil(live.twoWayPair)
        live.theySpeak = "zz"
        XCTAssertNotNil(live.twoWayVoiceNote, "the setter went through twoWayLanguage, so the voice note refreshed")
        live.theySpeak = "en"
        XCTAssertNil(live.twoWayVoiceNote)
    }

    func testYourLanguageCanBeChosenOnLiveOnlyWithAutoDetect() {
        let settings = store()
        let live = liveModel(settings)
        XCTAssertTrue(live.canChooseYourLanguage)
        XCTAssertNil(live.pinnedSourceNote)
        settings.update { $0.language = "fr" }
        XCTAssertFalse(live.canChooseYourLanguage)
        XCTAssertEqual(live.pinnedSourceNote,
                       "Source language is pinned to French in Settings, so the language you speak cannot be chosen here. Set it to Auto-detect for Two-way to work.")
        live.ignoredLanguage = "en"
        XCTAssertEqual(live.pinnedSourceNote,
                       "Source language is pinned to French in Settings, so nothing is heard as English. Set it to Auto-detect for Two-way to work.")
        XCTAssertEqual(live.pinnedSourceNote, LiveViewModel.pinnedSourceNote(pinned: "French", you: "English"))
        settings.update { $0.language = nil }
        XCTAssertTrue(live.canChooseYourLanguage)
        XCTAssertNil(live.pinnedSourceNote)
    }

    func testTheLiveViewModelIsTheStripsModel() {
        let live = liveModel(store())
        let controls: any LiveControlsModel = live
        controls.isTwoWay = true
        controls.theySpeak = "es"
        XCTAssertEqual(live.twoWayLanguage, "es", "the strip writes through the protocol into the same setting")
        XCTAssertEqual(controls.state, .idle)
        XCTAssertTrue(controls.canChooseYourLanguage)
        XCTAssertNil(controls.pinnedSourceNote)
        XCTAssertNil(controls.twoWayVoiceNote)
    }

    func testTheGroupsAndThePairPillsSayWhoSpeaksWhat() {
        XCTAssertEqual(LiveControlStrip.listenCaption, "Listen")
        XCTAssertEqual(LiveControlStrip.voiceCaption, "Voice")
        XCTAssertEqual(LiveControlStrip.languagesCaption, "Languages")
        XCTAssertEqual(Set([LiveControlStrip.listenCaption, LiveControlStrip.voiceCaption, LiveControlStrip.languagesCaption]).count, 3)
        XCTAssertEqual(LiveControlStrip.captionColumnWidth, 72)
        XCTAssertEqual(LiveControlStrip.youSpeakTitle, "You speak")
        XCTAssertEqual(LiveControlStrip.theySpeakTitle, "They speak")
        XCTAssertEqual(LiveControlStrip.chooseLanguageTitle, "Choose…")
        XCTAssertEqual(LiveControlStrip.youSpeakHintText, "The language you speak; what you say is spoken to them in their language")
        XCTAssertEqual(LiveControlStrip.theySpeakHintText, "The other person's language; what you say is spoken to them in it")
        XCTAssertEqual(LiveControlStrip.theySpeakAccessibilityValue(name: "Spanish", hasVoice: true), "Spanish")
        XCTAssertEqual(LiveControlStrip.theySpeakAccessibilityValue(name: "Spanish", hasVoice: false), "Spanish, no voice on this iPhone")
        XCTAssertEqual(LiveControlStrip.lockedDetailText, "Stop to change the dimmed controls — ReVox reads them once, at Start.")
        XCTAssertTrue(LiveControlStrip.lockedDetailText.hasPrefix(LiveControlStrip.lockedText))
        XCTAssertEqual(LiveControlStrip.volumeHelpText, "How loud ReVox's own voice is; other apps are not affected")
        XCTAssertNotEqual(LiveControlStrip.volumeHelpText, LiveControlStrip.duckingHelpText)
    }
}
