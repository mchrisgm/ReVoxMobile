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

    // MARK: Merge (M9)

    private func sortedSessions(_ context: ModelContext) throws -> [Session] {
        try context.fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\Session.startedAt)]))
    }

    func testMergeMakesOneSessionInTimeOrderAndRemovesTheOriginals() throws {
        let context = ModelContext(container)
        let sessions = try sortedSessions(context)
        // A drop marker in the middle session, and an end time only on the last, to prove both survive.
        let marker = Entry(timestamp: sessions[1].startedAt.addingTimeInterval(1.5), language: "", original: "", english: "", isDropMarker: true)
        marker.session = sessions[1]
        context.insert(marker)
        sessions[2].endedAt = sessions[2].startedAt.addingTimeInterval(90)
        sessions[2].joinedInProgress = true
        try context.save()

        let merged = try HistoryActions(context: context).merge([sessions[2], sessions[0], sessions[1]])

        let after = try counts()
        XCTAssertEqual(after.sessions, 1, "the originals are gone")
        XCTAssertEqual(after.entries, 7, "6 lines plus the marker, copied, and the originals' rows cascaded away")
        XCTAssertEqual(merged.startedAt, start, "the earliest session's start")
        XCTAssertEqual(merged.endedAt, sessions[2].startedAt.addingTimeInterval(90), "the latest end")
        XCTAssertTrue(merged.joinedInProgress)
        XCTAssertEqual(merged.modelID, "small")
        let lines = merged.entries.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(lines.map(\.english), ["line 0.1", "line 0.2", "line 1.1", "", "line 1.2", "line 2.1", "line 2.2"])
        XCTAssertEqual(lines.filter(\.isDropMarker).count, 1)
        XCTAssertEqual(merged.entries.count, 7)
    }

    func testMergeNeedsAtLeastTwoSessions() throws {
        let context = ModelContext(container)
        let sessions = try sortedSessions(context)
        XCTAssertThrowsError(try HistoryActions(context: context).merge([sessions[0]])) { error in
            XCTAssertEqual(error as? HistoryActionsError, .needTwoSessions)
        }
        XCTAssertThrowsError(try HistoryActions(context: context).merge([]))
        XCTAssertEqual(try counts().sessions, 3, "nothing changed")
    }

    func testLatestEndFallsBackToTheLastEntry() throws {
        let context = ModelContext(container)
        let sessions = try sortedSessions(context)
        let end = HistoryActions.latestEnd(of: sessions)
        XCTAssertEqual(end, sessions[2].startedAt.addingTimeInterval(2), "no session recorded an end, so the last entry is it")
    }

    func testMergeCopy() {
        XCTAssertEqual(HistoryActions.mergeConfirmationTitle(count: 3), "Merge 3 sessions?")
        XCTAssertEqual(HistoryActions.mergeMessage, "They become one session, in time order. The originals are removed. You cannot undo this action.")
        XCTAssertEqual(String(describing: HistoryActionsError.needTwoSessions), "Select at least two sessions to merge")
    }
}
