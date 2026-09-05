import XCTest
import SwiftData
@testable import ReVoxMobile

/// The schema as it was before M11 (§6.10): the same two entities, `Entry` without `isGuess`. Nested in a
/// `VersionedSchema` so the entity names ("Session", "Entry") match the app's and the store's.
enum PreM11Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Session.self, Entry.self] }

    @Model
    final class Session {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var captureMode: String
        var pinnedLanguage: String?
        var modelID: String
        var voice: String
        var joinedInProgress: Bool
        @Relationship(deleteRule: .cascade, inverse: \Entry.session) var entries: [Entry]

        init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, captureMode: String, pinnedLanguage: String?,
             modelID: String, voice: String, joinedInProgress: Bool, entries: [Entry] = []) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.captureMode = captureMode
            self.pinnedLanguage = pinnedLanguage
            self.modelID = modelID
            self.voice = voice
            self.joinedInProgress = joinedInProgress
            self.entries = entries
        }
    }

    @Model
    final class Entry {
        var timestamp: Date
        var language: String
        var original: String
        var english: String
        var isDropMarker: Bool
        var session: Session?

        init(timestamp: Date, language: String, original: String, english: String, isDropMarker: Bool, session: Session? = nil) {
            self.timestamp = timestamp
            self.language = language
            self.original = original
            self.english = english
            self.isDropMarker = isDropMarker
            self.session = session
        }
    }
}

/// M11 adds `Entry.isGuess`. Every TestFlight iPhone has an on-disk "ReVoxTranscripts" store whose rows lack it,
/// and `AppEnvironment.live()` opens that store with a bare `try` at launch — so the lightweight migration is
/// proved here on a real file rather than on the first TestFlight run: a store written with the pre-M11 schema
/// is reopened with the app's schema and every old row reads back as a confident phrase. The in-memory
/// containers of the other tests never exercise this path.
///
/// If a 17.0/17.1 tester ever reports a launch failure here, the fallback is `var isGuess: Bool?` read as `== true`.
@MainActor
final class TranscriptMigrationTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appendingPathComponent("\(TranscriptContainer.storeName).store") }

    /// Writes a pre-M11 store and lets its container go out of scope before the app's schema opens the file.
    private func seedPreM11Store() throws {
        let schema = Schema(versionedSchema: PreM11Schema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let session = PreM11Schema.Session(startedAt: start, endedAt: start.addingTimeInterval(30), captureMode: "microphone",
                                           pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        let rows = [
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hola", isDropMarker: false),
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(2), language: "", original: "", english: "", isDropMarker: true),
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(3), language: "ja", original: "おはよう", english: "Good morning.", isDropMarker: false),
        ]
        for row in rows {
            row.session = session
            context.insert(row)
        }
        try context.save()
    }

    func testAStoreFromBeforeM11OpensWithTheAppSchemaAndItsRowsAreConfident() throws {
        try seedPreM11Store()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "the pre-M11 store is on disk")

        let schema = Schema([Session.self, Entry.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].modelID, "small")
        let rows = sessions[0].entries.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(rows.map(\.english), ["hola", "", "Good morning."])
        XCTAssertEqual(rows.map(\.isDropMarker), [false, true, false])
        XCTAssertEqual(rows.map(\.isGuess), [false, false, false], "the lightweight migration filled the new column with the default")
        XCTAssertEqual(rows[2].original, "おはよう")

        // The migrated store takes new rows with the flag and reads them back.
        let guess = Entry(timestamp: start.addingTimeInterval(4), language: "es", original: "", english: "quizás", isDropMarker: false, isGuess: true)
        guess.session = sessions[0]
        context.insert(guess)
        try context.save()
        let reread = try ModelContext(container).fetch(FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.isGuess }))
        XCTAssertEqual(reread.map(\.english), ["quizás"])
    }
}
