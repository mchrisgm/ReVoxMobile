import XCTest
@testable import ReVoxCore

/// Mirrors `tests/test_transcript.py` for the format; the golden export is new.
final class TranscriptFormatterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14T22:13:20Z

    func testHeaderPrefixDropMarkerAndFileNamePattern() throws {
        XCTAssertEqual(TranscriptFormatter.headerPrefix, "# ReVox session ")
        XCTAssertEqual(TranscriptFormatter.dropMarkerText, "… (skipped: falling behind)")
        XCTAssertEqual(TranscriptFormatter.dropMarkerText.unicodeScalars.first?.value, 0x2026)
        let name = TranscriptFormatter(timeZone: utc).fileName(startedAt: start)
        XCTAssertEqual(name, "2023-11-14_22-13-20.txt")
        let pattern = try NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}\\.txt$")
        XCTAssertEqual(pattern.numberOfMatches(in: name, range: NSRange(name.startIndex..., in: name)), 1)
    }

    func testHeaderAndFileName() {
        let formatter = TranscriptFormatter(timeZone: utc)
        let header = formatter.header(startedAt: start)
        XCTAssertTrue(header.hasPrefix("# ReVox session "))
        XCTAssertEqual(header, "# ReVox session 2023-11-14T22:13:20\n")
        XCTAssertTrue(formatter.fileName(startedAt: start).hasSuffix(".txt"))
    }

    func testEntryAndDropMarkerLines() {
        let formatter = TranscriptFormatter(timeZone: utc)
        let entry = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "hola", english: "hello")
        XCTAssertEqual(formatter.line(for: entry), "[22:13:21] [es] hola\n  → hello\n")
        let empty = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hello")
        XCTAssertEqual(formatter.line(for: empty), "[22:13:21] [es] \n  → hello\n")   // the port writes an empty original
        XCTAssertEqual(formatter.dropMarkerLine(at: start.addingTimeInterval(2)), "[22:13:22] … (skipped: falling behind)\n")
    }

    func testGoldenExport() {
        let formatter = TranscriptFormatter(timeZone: utc)
        let items: [TranscriptItem] = [
            .dropMarker(start.addingTimeInterval(1)),
            .dropMarker(start.addingTimeInterval(2)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3), language: "fr", original: "", english: "yes")),
            .dropMarker(start.addingTimeInterval(4)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3_600 + 5), language: "es", original: "", english: "hello there")),
        ]
        // "\u{20}" keeps the trailing space of the empty-original line visible in the literal.
        let expected = """
        # ReVox session 2023-11-14T22:13:20
        [22:13:21] … (skipped: falling behind)
        [22:13:23] [fr]\u{20}
          → yes
        [22:13:24] … (skipped: falling behind)
        [23:13:25] [es]\u{20}
          → hello there

        """
        let text = formatter.export(startedAt: start, items: items)
        XCTAssertEqual(text, expected)
        XCTAssertEqual(Array(text.utf8), Array(expected.utf8))          // byte-for-byte, UTF-8, "\n", no BOM
        XCTAssertEqual(text.components(separatedBy: "skipped: falling behind").count - 1, 2)
    }

    func testTimestampsHonourInjectedTimeZone() {
        let plusTwo = TranscriptFormatter(timeZone: TimeZone(secondsFromGMT: 7_200)!)
        XCTAssertEqual(plusTwo.fileName(startedAt: start), "2023-11-15_00-13-20.txt")
        XCTAssertEqual(plusTwo.header(startedAt: start), "# ReVox session 2023-11-15T00:13:20\n")
        let minusFive = TranscriptFormatter(timeZone: TimeZone(secondsFromGMT: -18_000)!)
        XCTAssertEqual(minusFive.dropMarkerLine(at: start), "[17:13:20] … (skipped: falling behind)\n")
    }

    func testTranscriptEntryRoundTripsThroughCodable() throws {
        let entry = TranscriptEntry(timestamp: start, language: "es", original: "hola", english: "hello")
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptEntry.self, from: data), entry)
        let guess = TranscriptEntry(timestamp: start, language: "es", original: "", english: "maybe", isGuess: true)
        let guessData = try JSONEncoder().encode(guess)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptEntry.self, from: guessData), guess)
        XCTAssertNotEqual(guess, TranscriptEntry(timestamp: start, language: "es", original: "", english: "maybe"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: guessData) as? [String: Any])
        XCTAssertEqual(object["isGuess"] as? Bool, true)
    }

    /// An entry written before M11 has no `isGuess` and decodes as a confident phrase.
    func testAPreM11EntryDecodesAsConfident() throws {
        let json = Data(#"{"timestamp":0,"language":"es","original":"","english":"hello"}"#.utf8)
        let entry = try JSONDecoder().decode(TranscriptEntry.self, from: json)
        XCTAssertEqual(entry, TranscriptEntry(timestamp: Date(timeIntervalSinceReferenceDate: 0), language: "es", original: "", english: "hello"))
        XCTAssertFalse(entry.isGuess)
    }

    // MARK: Unsure phrases (M11, §3)

    func testGuessPrefixAndLine() {
        XCTAssertEqual(TranscriptFormatter.guessPrefix, "(unsure) ")
        let formatter = TranscriptFormatter(timeZone: utc)
        let guess = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hello", isGuess: true)
        XCTAssertEqual(formatter.line(for: guess), "[22:13:21] [es] \n  → (unsure) hello\n")
        let sure = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "hola", english: "hello")
        XCTAssertEqual(formatter.line(for: sure), "[22:13:21] [es] hola\n  → hello\n", "a confident line is unchanged")
    }

    /// The golden items plus a guess between the two consecutive markers: the guess resets the collapse, so both
    /// markers print, and the guess line carries the prefix. Everything else is the golden text, byte for byte.
    func testGoldenExportWithAGuessBetweenMarkers() {
        let formatter = TranscriptFormatter(timeZone: utc)
        let items: [TranscriptItem] = [
            .dropMarker(start.addingTimeInterval(1)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(1.5), language: "es", original: "", english: "hello", isGuess: true)),
            .dropMarker(start.addingTimeInterval(2)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3), language: "fr", original: "", english: "yes")),
            .dropMarker(start.addingTimeInterval(4)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3_600 + 5), language: "es", original: "", english: "hello there")),
        ]
        let expected = """
        # ReVox session 2023-11-14T22:13:20
        [22:13:21] … (skipped: falling behind)
        [22:13:21] [es]\u{20}
          → (unsure) hello
        [22:13:22] … (skipped: falling behind)
        [22:13:23] [fr]\u{20}
          → yes
        [22:13:24] … (skipped: falling behind)
        [23:13:25] [es]\u{20}
          → hello there

        """
        let text = formatter.export(startedAt: start, items: items)
        XCTAssertEqual(text, expected)
        XCTAssertEqual(Array(text.utf8), Array(expected.utf8))
        XCTAssertEqual(text.components(separatedBy: "skipped: falling behind").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: TranscriptFormatter.guessPrefix).count - 1, 1)
    }

    func testExportOfAnEmptySessionIsJustTheHeader() {
        let formatter = TranscriptFormatter(timeZone: utc)
        XCTAssertEqual(formatter.export(startedAt: start, items: []), formatter.header(startedAt: start))
    }
}
