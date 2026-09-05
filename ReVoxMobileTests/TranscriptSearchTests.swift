import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class TranscriptSearchTests: XCTestCase {
    private var container: ModelContainer!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = try TranscriptContainer.make(inMemory: true)
        try seed()
    }

    /// Two sessions an hour apart; the newer one is the broadcast session. The row at offset 0.5 is a drop marker
    /// carrying text that matches two of the queries below and sorting *before* the first real match of its session,
    /// so both predicates' `!entry.isDropMarker` clause is load-bearing: delete it and "marker" returns a hit and
    /// `hits(query: "morning")` picks the marker as the older session's earliest matching line.
    /// M11: the row at offset 0.7 is a guess in the same position, and `!entry.isGuess` is load-bearing the same way.
    private func seed() throws {
        let context = ModelContext(container)
        let older = Session(startedAt: start, captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        let newer = Session(startedAt: start.addingTimeInterval(3_600), captureMode: "broadcast", pinnedLanguage: "es", modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(older)
        context.insert(newer)
        let rows: [(session: Session, offset: TimeInterval, english: String, isDrop: Bool)] = [
            (older, 0.5, "good morning marker", true),
            (older, 1, "good morning everyone", false),
            (older, 2, "", true),
            (older, 3, "the meeting starts now", false),
            (newer, 5, "Good evening", false),
            (newer, 6, "see you tomorrow morning", false),
        ]
        for row in rows {
            let entry = Entry(timestamp: row.session.startedAt.addingTimeInterval(row.offset), language: row.isDrop ? "" : "es",
                              original: "", english: row.english, isDropMarker: row.isDrop)
            entry.session = row.session
            context.insert(entry)
        }
        let guess = Entry(timestamp: older.startedAt.addingTimeInterval(0.7), language: "es", original: "",
                          english: "good morning guessed", isDropMarker: false, isGuess: true)
        guess.session = older
        context.insert(guess)
        try context.save()
    }

    /// M11: a guess is never a hit, and never the earliest matching line of its session.
    func testUnsurePhrasesAreNeverSearchHits() throws {
        let guessed = try TranscriptSearch.hits(query: "guessed", in: ModelContext(container))
        XCTAssertTrue(guessed.hits.isEmpty, "a guess never matches, even when its text contains the query")
        let morning = try TranscriptSearch.hits(query: "morning", in: ModelContext(container))
        XCTAssertEqual(morning.hits.count, 2)
        XCTAssertEqual(morning.hits[1].matchingLine, "good morning everyone",
                       "the guess sorts before the first confident match of its session and is skipped")
        let descriptor = FetchDescriptor<Entry>(predicate: TranscriptSearch.fallbackPredicate(query: "guessed"))
        let fallback = try ModelContext(container).fetch(descriptor)
        XCTAssertTrue(fallback.isEmpty, "the fallback predicate excludes guesses too")
    }

    func testExactMatchGroupsBySessionNewestFirstWithTheEarliestMatchingLine() throws {
        let result = try TranscriptSearch.hits(query: "morning", in: ModelContext(container))
        XCTAssertEqual(result.hits.count, 2)
        XCTAssertEqual(result.hits[0].session.captureMode, "broadcast")
        XCTAssertEqual(result.hits[0].matchingLine, "see you tomorrow morning")
        XCTAssertEqual(result.hits[1].session.captureMode, "microphone")
        XCTAssertEqual(result.hits[1].matchingLine, "good morning everyone")
        XCTAssertEqual(result.hits[1].matchTimestamp, start.addingTimeInterval(1))
        XCTAssertEqual(Set(result.hits.map(\.id)).count, 2, "one hit per session, never two rows for the same session")
    }

    func testDropMarkersAndNonMatchesAreExcluded() throws {
        let meeting = try TranscriptSearch.hits(query: "meeting", in: ModelContext(container))
        XCTAssertEqual(meeting.hits.map(\.matchingLine), ["the meeting starts now"])
        let zebra = try TranscriptSearch.hits(query: "zebra", in: ModelContext(container))
        XCTAssertTrue(zebra.hits.isEmpty)
        // "good morning marker" is a drop marker at offset 0.5 whose text matches both queries.
        let marker = try TranscriptSearch.hits(query: "marker", in: ModelContext(container))
        XCTAssertTrue(marker.hits.isEmpty, "a drop marker never matches, even when its text contains the query")
        let morning = try TranscriptSearch.hits(query: "morning", in: ModelContext(container))
        XCTAssertEqual(morning.hits.count, 2)
        XCTAssertEqual(morning.hits[1].matchingLine, "good morning everyone",
                       "the marker sorts first in that session and is skipped, so the earliest *real* match wins")
        XCTAssertEqual(morning.hits[1].matchTimestamp, start.addingTimeInterval(1))
    }

    func testBlankQueryReturnsNothingWithoutFetching() throws {
        let spaces = try TranscriptSearch.hits(query: "   ", in: ModelContext(container))
        XCTAssertEqual(spaces, SearchResult(hits: [], usedFallback: false))
        let empty = try TranscriptSearch.hits(query: "", in: ModelContext(container))
        XCTAssertEqual(empty, SearchResult(hits: [], usedFallback: false))
    }

    func testQueryIsTrimmedBeforeMatching() throws {
        let result = try TranscriptSearch.hits(query: "  meeting\n", in: ModelContext(container))
        XCTAssertEqual(result.hits.count, 1)
    }

    /// §10.4 / §13 Q12 was ASSUMED, and this is where it is pinned: `localizedStandardContains` is case-insensitive
    /// when the store translates it, and the `contains` fallback is case-sensitive. A green run is the simulator
    /// evidence for row 1 of `docs/measurements/m6-history-export.md`.
    ///
    /// The plan expected a `print` here and a `grep` of the CI log, but xcbeautify does not carry test stdout into
    /// the log (run 33887832648 contains no such line), so a print would be evidence nobody can read. Asserting the
    /// assumption is both visible and stronger: if a future SwiftData stops translating the predicate this test goes
    /// red, which is exactly the discovery the measurement row asks for. Search itself keeps working either way —
    /// `TranscriptSearch` falls back at runtime — so the failure is a documentation task, not an outage: record it
    /// in the measurement row and add the "Search matches exact case only" sentence to the README, as row 1 says.
    func testTheStoreTranslatesLocalizedStandardContains() throws {
        let result = try TranscriptSearch.hits(query: "GOOD", in: ModelContext(container))
        XCTAssertFalse(result.usedFallback, "the store rejected localizedStandardContains and the contains fallback answered")
        XCTAssertEqual(result.hits.count, 2, "localizedStandardContains matches regardless of case")
    }

    func testFallbackPredicateIsPlainContains() throws {
        let descriptor = FetchDescriptor<Entry>(predicate: TranscriptSearch.fallbackPredicate(query: "Good"), sortBy: [SortDescriptor(\Entry.timestamp)])
        let matched = try ModelContext(container).fetch(descriptor)
        XCTAssertEqual(matched.map(\.english), ["Good evening"])
    }
}
