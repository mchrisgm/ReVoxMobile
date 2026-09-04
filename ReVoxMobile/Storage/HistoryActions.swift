import Foundation
import SwiftData

enum HistoryActionsError: Error, Equatable, CustomStringConvertible {
    case needTwoSessions

    var description: String {
        switch self {
        case .needTwoSessions: return "Select at least two sessions to merge"
        }
    }
}

/// Deleting and merging transcripts (§6.10, §8.6). Single-row deletion is unconfirmed (a common, expected
/// action); Clear All, the Session detail Delete and Merge sit behind a `confirmationDialog` whose copy lives here
/// so it is tested.
struct HistoryActions {
    static let clearAllTitle = "Clear All"
    static let clearAllMessage = "Every transcript on this iPhone will be deleted. You cannot undo this action."
    static let deleteSessionTitle = "Delete this session?"
    static let mergeTitle = "Merge"
    static let mergeMessage = "They become one session, in time order. The originals are removed. You cannot undo this action."

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

    /// M9: one session from many. Its entries are every selected session's entries in timestamp order, as new rows
    /// — never re-parented, so the cascade that removes the originals cannot take them along. The metadata is the
    /// earliest session's, the end is the latest end, and `joinedInProgress` is true if any of them was.
    @discardableResult
    func merge(_ sessions: [Session]) throws -> Session {
        guard sessions.count >= 2 else { throw HistoryActionsError.needTwoSessions }
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        let first = ordered[0]
        let merged = Session(startedAt: first.startedAt,
                             endedAt: Self.latestEnd(of: ordered),
                             captureMode: first.captureMode,
                             pinnedLanguage: first.pinnedLanguage,
                             modelID: first.modelID,
                             voice: first.voice,
                             joinedInProgress: ordered.contains { $0.joinedInProgress })
        context.insert(merged)
        let rows = ordered.flatMap(\.entries).sorted { $0.timestamp < $1.timestamp }
        for row in rows {
            let copy = Entry(timestamp: row.timestamp, language: row.language, original: row.original,
                             english: row.english, isDropMarker: row.isDropMarker)
            copy.session = merged
            context.insert(copy)
        }
        for session in ordered {
            context.delete(session)
        }
        try context.save()
        return merged
    }

    /// The latest `endedAt`, or the latest entry of a session that never recorded an end.
    static func latestEnd(of sessions: [Session]) -> Date? {
        sessions.compactMap { $0.endedAt ?? $0.entries.map(\.timestamp).max() }.max()
    }

    static func mergeConfirmationTitle(count: Int) -> String {
        "Merge \(count) sessions?"
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
