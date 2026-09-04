import Foundation
import SwiftData

/// Deleting transcripts (§6.10, §8.6). Single-row deletion is unconfirmed (a common, expected action); Clear All
/// and the Session detail Delete sit behind a `confirmationDialog` whose copy lives here so it is tested.
struct HistoryActions {
    static let clearAllTitle = "Clear All"
    static let clearAllMessage = "Every transcript on this iPhone will be deleted. You cannot undo this action."
    static let deleteSessionTitle = "Delete this session?"

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func sessionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Session>())
    }

    /// The relationship's `.cascade` rule removes the entries with the session.
    func delete(_ session: Session) throws {
        context.delete(session)
        try context.save()
    }

    /// Deletes session by session (not `delete(model:)`, which bypasses the cascade rule) and returns the count.
    @discardableResult
    func deleteAll() throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<Session>())
        for session in sessions {
            context.delete(session)
        }
        try context.save()
        return sessions.count
    }

    static func clearAllConfirmationTitle(count: Int) -> String {
        count == 1 ? "Delete 1 session?" : "Delete \(count) sessions?"
    }

    static func deleteSessionMessage(entryCount: Int) -> String {
        let entries: String
        switch entryCount {
        case 0: entries = "no entries"
        case 1: entries = "1 entry"
        default: entries = "\(entryCount) entries"
        }
        return "This session has \(entries). You cannot undo this action."
    }
}
