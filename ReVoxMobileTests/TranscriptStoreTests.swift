import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

final class TranscriptStoreTests: XCTestCase {
    private var container: ModelContainer!
    private let startedAt = Date(timeIntervalSince1970: 1_756_800_000)

    override func setUpWithError() throws {
        container = try TranscriptContainer.make(inMemory: true)
    }

    private func metadata() -> SessionMetadata {
        SessionMetadata(startedAt: startedAt, captureMode: .microphone, pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
    }

    /// Every read-back goes through a second context, never the actor's own (§6.10).
    private func fetchSessions() throws -> [Session] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.startedAt)]))
    }

    private func entries(of session: Session) -> [Entry] {
        session.entries.sorted { $0.timestamp < $1.timestamp }
    }

    func testAddIsPersistedAndReadableFromASecondContext() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "es", original: "", english: "hello"))
        await store.flush()

        let sessions = try fetchSessions()
        XCTAssertEqual(sessions.count, 1)
        let rows = entries(of: sessions[0])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].english, "hello")
        XCTAssertEqual(rows[0].language, "es")
        XCTAssertEqual(rows[0].original, "")
        XCTAssertFalse(rows[0].isDropMarker)
        XCTAssertNil(sessions[0].endedAt)
    }

    func testSessionMetadataIsPersisted() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.close()
        let sessions = try fetchSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].startedAt, startedAt)
        XCTAssertEqual(sessions[0].captureMode, "microphone")
        XCTAssertNil(sessions[0].pinnedLanguage)
        XCTAssertEqual(sessions[0].modelID, "small")
        XCTAssertEqual(sessions[0].voice, "system")
        XCTAssertFalse(sessions[0].joinedInProgress)
        XCTAssertNotNil(sessions[0].endedAt)
    }

    func testDropMarkerDeduplicated() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.addDropMarker(at: startedAt.addingTimeInterval(1))
        await store.addDropMarker(at: startedAt.addingTimeInterval(2))
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(3), language: "de", original: "", english: "hi"))
        await store.addDropMarker(at: startedAt.addingTimeInterval(4))
        await store.close()

        let rows = entries(of: try fetchSessions()[0])
        XCTAssertEqual(rows.map(\.isDropMarker), [true, false, true])
        XCTAssertEqual(rows.filter(\.isDropMarker).count, 2)
    }

    func testClosePersistsEndedAtAndIgnoresLaterWrites() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "fr", original: "", english: "one"))
        await store.close()
        await store.close()
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(2), language: "fr", original: "", english: "two"))
        await store.addDropMarker(at: startedAt.addingTimeInterval(3))

        let session = try fetchSessions()[0]
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(entries(of: session).map(\.english), ["one"])
    }

    func testRapidAddsAreCoalescedButAllPersistedByClose() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        for index in 0..<5 {
            await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(Double(index)), language: "es", original: "", english: "line \(index)"))
        }
        let savesBeforeClose = await store.saveCount
        XCTAssertLessThan(savesBeforeClose, 5, "adds within one second share a save")
        await store.close()
        let rows = entries(of: try fetchSessions()[0])
        XCTAssertEqual(rows.map(\.english), (0..<5).map { "line \($0)" })
    }

    func testExportTextEqualsFormatterOverPersistedEntries() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "es", original: "", english: "hola"))
        await store.addDropMarker(at: startedAt.addingTimeInterval(2))
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(3), language: "es", original: "", english: "adiós"))
        await store.close()

        let expected = await store.exportText()
        let session = try fetchSessions()[0]
        let rebuilt = TranscriptFormatter().export(startedAt: session.startedAt, items: TranscriptStore.items(from: entries(of: session)))
        XCTAssertEqual(rebuilt, expected)
        XCTAssertTrue(expected.hasPrefix(TranscriptFormatter.headerPrefix))
        XCTAssertTrue(expected.contains("  → hola\n"))
        XCTAssertEqual(expected.components(separatedBy: TranscriptFormatter.dropMarkerText).count - 1, 1)
    }
}
