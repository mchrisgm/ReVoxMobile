import Foundation
import SwiftData

/// One History search result: the session and the earliest line that matched (§8.6).
struct SearchHit: Identifiable, Equatable {
    let session: Session
    let matchingLine: String
    let matchTimestamp: Date

    var id: PersistentIdentifier { session.persistentModelID }
}

struct SearchResult: Equatable {
    var hits: [SearchHit]
    /// True when the store rejected `localizedStandardContains` and the `contains` fallback answered (§6.10).
    var usedFallback: Bool
}

/// History search (§6.10, §8.6): entries whose English text contains the query, grouped by session.
enum TranscriptSearch {
    /// Case- and diacritic-insensitive; whether the SwiftData store translates it is measured in M6 (§10.4, §13 Q12).
    static func primaryPredicate(query: String) -> Predicate<Entry> {
        #Predicate<Entry> { entry in
            !entry.isDropMarker && entry.english.localizedStandardContains(query)
        }
    }

    /// The fallback the spec names for a store that rejects the primary predicate (case-sensitive).
    static func fallbackPredicate(query: String) -> Predicate<Entry> {
        #Predicate<Entry> { entry in
            !entry.isDropMarker && entry.english.contains(query)
        }
    }

    static func matchingEntries(query: String, in context: ModelContext) throws -> (entries: [Entry], usedFallback: Bool) {
        let sort = [SortDescriptor(\Entry.timestamp)]
        do {
            return (try context.fetch(FetchDescriptor<Entry>(predicate: primaryPredicate(query: query), sortBy: sort)), false)
        } catch {
            return (try context.fetch(FetchDescriptor<Entry>(predicate: fallbackPredicate(query: query), sortBy: sort)), true)
        }
    }

    /// One hit per session (the earliest matching line), newest session first; a blank query fetches nothing.
    static func hits(query: String, in context: ModelContext) throws -> SearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResult(hits: [], usedFallback: false) }
        let (entries, usedFallback) = try matchingEntries(query: trimmed, in: context)
        var firstBySession: [PersistentIdentifier: SearchHit] = [:]
        for entry in entries {
            guard let session = entry.session else { continue }
            let id = session.persistentModelID
            if firstBySession[id] == nil {
                firstBySession[id] = SearchHit(session: session, matchingLine: entry.english, matchTimestamp: entry.timestamp)
            }
        }
        let hits = firstBySession.values.sorted { $0.session.startedAt > $1.session.startedAt }
        return SearchResult(hits: hits, usedFallback: usedFallback)
    }
}
