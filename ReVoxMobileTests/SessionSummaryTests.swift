import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SessionSummaryTests: XCTestCase {
    private var context: ModelContext!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        context = ModelContext(try TranscriptContainer.make(inMemory: true))
    }

    private func session(captureMode: String = "microphone", endedAt: Date? = nil,
                         entries: [(offset: TimeInterval, english: String, isDrop: Bool)]) throws -> Session {
        let session = Session(startedAt: start, endedAt: endedAt, captureMode: captureMode, pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        for entry in entries {
            let row = Entry(timestamp: start.addingTimeInterval(entry.offset), language: entry.isDrop ? "" : "es", original: "", english: entry.english, isDropMarker: entry.isDrop)
            row.session = session
            context.insert(row)
        }
        try context.save()
        return session
    }

    /// M11: the same shape with the guess flag instead of the drop flag.
    private func sessionWithGuesses(_ entries: [(offset: TimeInterval, english: String, isGuess: Bool)]) throws -> Session {
        let session = Session(startedAt: start, captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        for entry in entries {
            let row = Entry(timestamp: start.addingTimeInterval(entry.offset), language: "es", original: "", english: entry.english,
                            isDropMarker: false, isGuess: entry.isGuess)
            row.session = session
            context.insert(row)
        }
        try context.save()
        return session
    }

    func testCountsExcludeDropMarkersAndFirstLineIsTheEarliestEntry() throws {
        let summary = SessionSummary(session: try session(endedAt: start.addingTimeInterval(125), entries: [
            (9, "second", false), (2, "", true), (3, "first", false), (10, "", true),
        ]))
        XCTAssertEqual(summary.entryCount, 2)
        XCTAssertEqual(summary.dropCount, 2)
        XCTAssertEqual(summary.dropCountText, "2 phrases skipped", "M10: the Session detail header shows the skips")
        XCTAssertEqual(summary.firstEnglishLine, "first")
        XCTAssertEqual(summary.previewText, "first")
        XCTAssertEqual(summary.entryCountText, "2 entries")
        XCTAssertEqual(summary.duration, 125)
        XCTAssertEqual(summary.durationText, "2:05")
        XCTAssertEqual(summary.sourceTitle, "Microphone")
        XCTAssertEqual(summary.modelID, "small")
        XCTAssertEqual(summary.voice, "alba")
    }

    func testDurationFallsBackToTheLastEntryWhenTheSessionNeverClosed() throws {
        let summary = SessionSummary(session: try session(captureMode: "broadcast", entries: [(4, "a", false), (40, "b", false)]))
        XCTAssertNil(summary.endedAt)
        XCTAssertEqual(summary.duration, 40)
        XCTAssertEqual(summary.durationText, "0:40")
        XCTAssertEqual(summary.captureMode, .broadcast)
        XCTAssertEqual(summary.sourceTitle, "Other apps")
    }

    func testEmptySessionTexts() throws {
        let summary = SessionSummary(session: try session(entries: []))
        XCTAssertEqual(summary.entryCount, 0)
        XCTAssertEqual(summary.entryCountText, "0 entries")
        XCTAssertNil(summary.firstEnglishLine)
        XCTAssertEqual(summary.previewText, SessionSummary.noEntriesText)
        XCTAssertNil(summary.duration)
        XCTAssertEqual(summary.durationText, "0:00")
        XCTAssertNil(summary.dropCountText, "no skips, no row")
    }

    func testOneEntryIsSingular() throws {
        let summary = SessionSummary(session: try session(entries: [(1, "hi", false)]))
        XCTAssertEqual(summary.entryCountText, "1 entry")
    }

    func testOneSkipIsSingular() throws {
        let summary = SessionSummary(session: try session(entries: [(1, "hi", false), (2, "", true)]))
        XCTAssertEqual(summary.dropCount, 1)
        XCTAssertEqual(summary.dropCountText, "1 phrase skipped")
        XCTAssertEqual(summary.entryCountText, "1 entry", "skips never count as entries")
    }

    /// M10: the History row's second line is one wrapping sentence built here, with the source's symbol beside it.
    func testMetaLineAndSymbolFollowTheSource() throws {
        let microphone = SessionSummary(session: try session(entries: [(1, "hi", false), (2, "there", false)]))
        XCTAssertEqual(microphone.metaLineText, "Microphone · 2 entries")
        XCTAssertEqual(microphone.sourceSymbolName, "mic")

        let joined = Session(startedAt: start, captureMode: "broadcast", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: true)
        context.insert(joined)
        try context.save()
        let broadcast = SessionSummary(session: joined)
        XCTAssertEqual(broadcast.metaLineText, "Other apps · 0 entries · joined in progress")
        XCTAssertEqual(broadcast.sourceSymbolName, "iphone.radiowaves.left.and.right")
    }

    func testInvalidCaptureModeFallsBackToMicrophone() throws {
        let summary = SessionSummary(session: try session(captureMode: "loopback", entries: []))
        XCTAssertEqual(summary.captureMode, .microphone)
    }

    // MARK: Unsure phrases (M11)

    func testGuessesCountAsEntriesButNeverAsThePreviewWhileAConfidentLineExists() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "maybe", true), (2, "first", false), (3, "perhaps", true)]))
        XCTAssertEqual(summary.entryCount, 3)
        XCTAssertEqual(summary.entryCountText, "3 entries")
        XCTAssertEqual(summary.guessCount, 2)
        XCTAssertEqual(summary.guessCountText, "2 unsure phrases")
        XCTAssertEqual(summary.firstEnglishLine, "first", "the earliest confident line, not the earliest line")
        XCTAssertEqual(summary.previewText, "first")
        XCTAssertFalse(summary.previewIsGuess)
        XCTAssertFalse(SessionRowView.accessibilityText(for: summary).contains(SessionRowView.guessPreviewPrefix))
    }

    func testASessionOfOnlyGuessesPreviewsAGuessAndSaysSo() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "maybe", true)]))
        XCTAssertEqual(summary.guessCountText, "1 unsure phrase")
        XCTAssertEqual(summary.previewText, "maybe")
        XCTAssertTrue(summary.previewIsGuess)
        XCTAssertTrue(SessionRowView.accessibilityText(for: summary).hasSuffix(". Unsure: maybe."))
        XCTAssertEqual(SessionRowView.guessPreviewPrefix, "Unsure: ")
        XCTAssertEqual(SessionSummary.guessSymbolName, "questionmark.circle")
    }

    func testASessionWithoutGuessesHasNoUnsureRow() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "sure", false)]))
        XCTAssertEqual(summary.guessCount, 0)
        XCTAssertNil(summary.guessCountText, "no guesses, no row")
        XCTAssertFalse(summary.previewIsGuess)
        XCTAssertTrue(SessionRowView.accessibilityText(for: summary).hasSuffix(". sure."))
    }

    func testDurationTextFormats() {
        XCTAssertEqual(SessionSummary.durationText(0), "0:00")
        XCTAssertEqual(SessionSummary.durationText(59.9), "0:59")
        XCTAssertEqual(SessionSummary.durationText(61), "1:01")
        XCTAssertEqual(SessionSummary.durationText(3_600 + 190), "1:03:10")
        XCTAssertEqual(SessionSummary.durationText(-5), "0:00")
    }
}
