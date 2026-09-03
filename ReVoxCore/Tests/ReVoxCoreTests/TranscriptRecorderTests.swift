import XCTest
@testable import ReVoxCore

/// Mirrors `tests/test_transcript.py` over the in-memory sink.
final class TranscriptRecorderTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecorder() -> TranscriptRecorder {
        TranscriptRecorder(startedAt: start, formatter: TranscriptFormatter(timeZone: utc))
    }

    func testExportStartsWithHeader() async {
        let recorder = makeRecorder()
        let text = await recorder.exportText()
        XCTAssertTrue(text.hasPrefix("# ReVox session "))
    }

    func testAddAppendsEntryLines() async {
        let recorder = makeRecorder()
        await recorder.add(TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hello"))
        let text = await recorder.exportText()
        XCTAssertTrue(text.contains("[es] \n"))
        XCTAssertTrue(text.contains("  → hello"))
        let items = await recorder.items
        XCTAssertEqual(items.count, 1)
    }

    func testDropMarkerDeduplicated() async {
        let recorder = makeRecorder()
        await recorder.addDropMarker(at: start.addingTimeInterval(1))
        await recorder.addDropMarker(at: start.addingTimeInterval(2))
        await recorder.add(TranscriptEntry(timestamp: start.addingTimeInterval(3), language: "fr", original: "", english: "yes"))
        await recorder.addDropMarker(at: start.addingTimeInterval(4))
        let text = await recorder.exportText()
        XCTAssertEqual(text.components(separatedBy: "skipped: falling behind").count - 1, 2)
        let items = await recorder.items
        XCTAssertEqual(items.count, 3)                        // the second consecutive marker was not recorded
    }

    func testCloseIdempotent() async {
        let recorder = makeRecorder()
        await recorder.close()
        await recorder.close()
        let closed = await recorder.isClosed
        XCTAssertTrue(closed)
        await recorder.add(TranscriptEntry(timestamp: start, language: "es", original: "", english: "late"))
        await recorder.addDropMarker(at: start)
        let items = await recorder.items
        XCTAssertTrue(items.isEmpty)                          // ignored after close
    }
}
