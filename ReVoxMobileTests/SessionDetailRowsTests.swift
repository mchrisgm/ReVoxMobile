import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SessionDetailRowsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testRowsFollowTimestampOrderAndMapMarkers() throws {
        let context = ModelContext(try TranscriptContainer.make(inMemory: true))
        let session = Session(startedAt: start, captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        context.insert(session)
        let rows = [
            Entry(timestamp: start.addingTimeInterval(5), language: "de", original: "", english: "later", isDropMarker: false),
            Entry(timestamp: start.addingTimeInterval(2), language: "", original: "", english: "", isDropMarker: true),
            Entry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "first", isDropMarker: false),
        ]
        for row in rows {
            row.session = session
            context.insert(row)
        }
        try context.save()

        let mapped = SessionDetailRows.rows(for: session)
        XCTAssertEqual(mapped.map(\.time), [start.addingTimeInterval(1), start.addingTimeInterval(2), start.addingTimeInterval(5)])
        XCTAssertEqual(mapped.map(\.kind), [.entry(language: "es", english: "first"), .dropMarker, .entry(language: "de", english: "later")])
        XCTAssertEqual(Set(mapped.map(\.id)).count, 3, "every row has its own identity")
    }

    func testSingleRowMapping() {
        let entry = Entry(timestamp: start, language: "fr", original: "", english: "yes", isDropMarker: false)
        let row = SessionDetailRows.row(for: entry)
        XCTAssertEqual(row.time, start)
        XCTAssertEqual(row.kind, .entry(language: "fr", english: "yes"))
        let marker = SessionDetailRows.row(for: Entry(timestamp: start, language: "", original: "", english: "", isDropMarker: true))
        XCTAssertEqual(marker.kind, .dropMarker)
    }

    func testLanguagePinText() {
        XCTAssertEqual(SessionDetailRows.languagePinText(nil), SettingsViewModel.autoDetectTitle)
        XCTAssertEqual(SessionDetailRows.languagePinText("es"), "es")
    }
}
