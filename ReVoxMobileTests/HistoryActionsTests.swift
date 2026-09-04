import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class HistoryActionsTests: XCTestCase {
    private var container: ModelContainer!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<3 {
            let session = Session(startedAt: start.addingTimeInterval(Double(index) * 60), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
            context.insert(session)
            for offset in 1...2 {
                let entry = Entry(timestamp: session.startedAt.addingTimeInterval(Double(offset)), language: "es", original: "", english: "line \(index).\(offset)", isDropMarker: false)
                entry.session = session
                context.insert(entry)
            }
        }
        try context.save()
    }

    private func counts() throws -> (sessions: Int, entries: Int) {
        let context = ModelContext(container)
        return (try context.fetchCount(FetchDescriptor<Session>()), try context.fetchCount(FetchDescriptor<Entry>()))
    }

    func testDeleteRemovesTheSessionAndCascadesToItsEntries() throws {
        let context = ModelContext(container)
        let actions = HistoryActions(context: context)
        let before = try actions.sessionCount()
        XCTAssertEqual(before, 3)
        let sessions = try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.startedAt)]))
        try actions.delete(sessions[1])
        let after = try counts()
        XCTAssertEqual(after.sessions, 2)
        XCTAssertEqual(after.entries, 4, "the two entries of the deleted session are gone")
        let remaining = try ModelContext(container).fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.startedAt)]))
        XCTAssertEqual(remaining.map(\.startedAt), [start, start.addingTimeInterval(120)])
    }

    func testDeleteAllRemovesEverythingAndReportsTheCount() throws {
        let actions = HistoryActions(context: ModelContext(container))
        let removed = try actions.deleteAll()
        XCTAssertEqual(removed, 3)
        let after = try counts()
        XCTAssertEqual(after.sessions, 0)
        XCTAssertEqual(after.entries, 0)
        let second = try actions.deleteAll()
        XCTAssertEqual(second, 0)
        let remaining = try actions.sessionCount()
        XCTAssertEqual(remaining, 0)
    }

    func testDialogCopy() {
        XCTAssertEqual(HistoryActions.clearAllTitle, "Clear All")
        XCTAssertEqual(HistoryActions.clearAllConfirmationTitle(count: 1), "Delete 1 session?")
        XCTAssertEqual(HistoryActions.clearAllConfirmationTitle(count: 3), "Delete 3 sessions?")
        XCTAssertEqual(HistoryActions.clearAllMessage, "Every transcript on this iPhone will be deleted. You cannot undo this action.")
        XCTAssertEqual(HistoryActions.deleteSessionTitle, "Delete this session?")
        XCTAssertEqual(HistoryActions.deleteSessionMessage(entryCount: 12), "This session has 12 entries. You cannot undo this action.")
        XCTAssertEqual(HistoryActions.deleteSessionMessage(entryCount: 1), "This session has 1 entry. You cannot undo this action.")
        XCTAssertEqual(HistoryActions.deleteSessionMessage(entryCount: 0), "This session has no entries. You cannot undo this action.")
    }
}
