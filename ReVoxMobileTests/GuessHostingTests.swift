import XCTest
import SwiftUI
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

/// M11 (§3, §4): the unsure-phrase surfaces and the History edit bar host and lay out, and the setting's binding
/// and copy are exact. Hosting in a `UIHostingController` is the only proof there is for SwiftUI here.
@MainActor
final class GuessHostingTests: XCTestCase {
    private var root: URL!
    private var store: SettingsStore!
    private let said = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxGuesses-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    private var exporter: TranscriptExporter { TranscriptExporter(directory: root.appendingPathComponent("exports", isDirectory: true)) }

    /// A guess row beside a confident one, with and without an original, at the default and the largest size.
    func testAGuessRowHostsAtEverySize() {
        let rows = [
            LiveTranscriptRow(time: said, kind: .entry(language: "es", english: "Where is the station?")),
            LiveTranscriptRow(time: said.addingTimeInterval(4), kind: .entry(language: "fr", english: "Maybe tomorrow."), isGuess: true),
            LiveTranscriptRow(time: said.addingTimeInterval(5), kind: .entry(language: "ja", original: "おはよう", english: "Good morning."), isGuess: true),
        ]
        for size in [DynamicTypeSize.large, .accessibility5] {
            host(List {
                ForEach(rows) { row in
                    LiveTranscriptRowView(row: row, now: self.said.addingTimeInterval(12), timeDisplay: .both, showsOriginal: true, romanizes: true)
                }
            }
            .environment(\.dynamicTypeSize, size))
        }
        host(List { ForEach(rows) { LiveTranscriptRowView(row: $0) } })
    }

    func testSessionDetailAndTheHistoryRowHostAGuess() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        let session = Session(startedAt: said, endedAt: said.addingTimeInterval(30), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        let guess = Entry(timestamp: said.addingTimeInterval(1), language: "es", original: "", english: "Where is the exit?", isDropMarker: false, isGuess: true)
        guess.session = session
        context.insert(guess)
        try context.save()
        let summary = SessionSummary(session: session)
        XCTAssertEqual(summary.guessCountText, "1 unsure phrase", "the header's Unsure row is present")
        XCTAssertTrue(summary.previewIsGuess)
        host(NavigationStack { SessionDetailView(session: session, exporter: exporter) }.modelContainer(container))
        host(List { SessionRowView(summary: summary) })
        host(List { SessionRowView(summary: summary) }.environment(\.dynamicTypeSize, .accessibility5))
    }

    func testTheSettingsSectionHostsAndTheBindingWritesTheStore() {
        let model = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(model.keepGuesses, "default on")
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } })
        model.keepGuesses = false
        XCTAssertFalse(store.settings.keepGuesses)
        XCTAssertFalse(SettingsStore(fileURL: store.fileURL).settings.keepGuesses, "written to disk")
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } })
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } }.environment(\.dynamicTypeSize, .accessibility5))
    }

    func testTheCopyIsExact() {
        XCTAssertEqual(SettingsViewModel.guessesSectionTitle, "Unsure phrases")
        XCTAssertEqual(SettingsViewModel.keepGuessesTitle, "Keep unsure phrases in History")
        XCTAssertEqual(SettingsViewModel.keepGuessesHint, "Keeps phrases ReVox was unsure about in History as well as on the Live screen")
        XCTAssertEqual(SettingsViewModel.keepGuessesHelpText,
                       "When ReVox is not sure of the language or the words, the phrase is shown greyed and marked Unsure on the Live screen and is never spoken aloud. With this on, those phrases are also kept in History and in the exported file, marked (unsure). A change takes effect the next time you tap Start.")
        XCTAssertEqual(SettingExamples.keepGuesses(true),
                       "An unsure phrase stays in the session, greyed and marked Unsure, so you can read what ReVox thought it heard.")
        XCTAssertEqual(SettingExamples.keepGuesses(false),
                       "An unsure phrase is shown on the Live screen only. History keeps the phrases ReVox was sure of.")
        XCTAssertTrue(SettingExamples.guessRow.isGuess)
        XCTAssertFalse(SettingExamples.sampleRow().isGuess)
        XCTAssertEqual(SettingExamples.guessRow.kind, .entry(language: "es", original: "", english: SettingExamples.spanishEnglish))
        XCTAssertNotEqual(SettingExamples.guessRow.id, SettingExamples.sampleRow().id, "its own identity in a Form")
    }

    /// §4: the edit bar is laid out in the real shape — a NavigationStack inside a TabView — and on its own.
    func testHistoryInEditModeHostsInsideATabView() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        for offset in [0.0, 120.0] {
            let session = Session(startedAt: said.addingTimeInterval(offset), endedAt: said.addingTimeInterval(offset + 10), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
            context.insert(session)
            let entry = Entry(timestamp: said.addingTimeInterval(offset + 1), language: "es", original: "", english: "hola", isDropMarker: false)
            entry.session = session
            context.insert(entry)
        }
        try context.save()
        host(TabView {
            NavigationStack { HistoryView(exporter: exporter, editing: true) }
                .tabItem { Label("History", systemImage: "clock") }
        }.modelContainer(container))
        host(NavigationStack { HistoryView(exporter: exporter, editing: true) }.modelContainer(container))
        host(NavigationStack { HistoryView(initialQuery: "hola", exporter: exporter, editing: true) }.modelContainer(container))   // bar hidden while searching
        XCTAssertEqual(HistoryView.mergeButtonTitle(count: 2), "Merge (2)")
        XCTAssertEqual(HistoryView.deleteButtonTitle(count: 2), "Delete (2)")
    }
}
