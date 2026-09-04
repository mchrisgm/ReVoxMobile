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
}
