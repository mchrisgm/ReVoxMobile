import XCTest
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class TranscriptExporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var directory: URL!
    private let utc = TimeZone(identifier: "UTC")!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14T22:13:20Z

    override func setUpWithError() throws {
        container = try TranscriptContainer.make(inMemory: true)
        context = ModelContext(container)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxExporter-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The session of `TranscriptFormatterTests.testGoldenExport` (core), stored the way `TranscriptStore` stores it,
    /// inserted out of timestamp order so the exporter's sort is exercised.
    private func goldenSession() throws -> Session {
        let session = Session(startedAt: start, captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
        context.insert(session)
        let rows = [
            Entry(timestamp: start.addingTimeInterval(3_600 + 5), language: "es", original: "", english: "hello there", isDropMarker: false),
            Entry(timestamp: start.addingTimeInterval(1), language: "", original: "", english: "", isDropMarker: true),
            Entry(timestamp: start.addingTimeInterval(3), language: "fr", original: "", english: "yes", isDropMarker: false),
            Entry(timestamp: start.addingTimeInterval(4), language: "", original: "", english: "", isDropMarker: true),
        ]
        for row in rows {
            row.session = session
            context.insert(row)
        }
        try context.save()
        return session
    }

    func testTextMatchesTheGoldenExportInTimestampOrder() throws {
        let exporter = TranscriptExporter(directory: directory, formatter: TranscriptFormatter(timeZone: utc))
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
        let text = exporter.text(for: try goldenSession())
        XCTAssertEqual(text, expected)
        XCTAssertEqual(Array(text.utf8), Array(expected.utf8))          // byte-for-byte, UTF-8, "\n", no BOM
        XCTAssertEqual(text.components(separatedBy: TranscriptFormatter.dropMarkerText).count - 1, 2)
    }

    func testExportWritesTheFileUnderTheWindowsFileNameWithoutBOM() throws {
        let exporter = TranscriptExporter(directory: directory, formatter: TranscriptFormatter(timeZone: utc))
        let session = try goldenSession()
        let url = try exporter.export(session)
        XCTAssertEqual(url.lastPathComponent, "2023-11-14_22-13-20.txt")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(exporter.fileName(for: session), "2023-11-14_22-13-20.txt")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(2)), Array("# ".utf8), "no UTF-8 BOM")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), exporter.text(for: session))
    }

    func testExportOverwritesAnEarlierFileOfTheSameSession() throws {
        let exporter = TranscriptExporter(directory: directory, formatter: TranscriptFormatter(timeZone: utc))
        let session = try goldenSession()
        let first = try exporter.export(session)
        let extra = Entry(timestamp: start.addingTimeInterval(7_200), language: "de", original: "", english: "later", isDropMarker: false)
        extra.session = session
        context.insert(extra)
        try context.save()
        let second = try exporter.export(session)
        XCTAssertEqual(first, second)
        let reread = try String(contentsOf: second, encoding: .utf8)
        XCTAssertTrue(reread.hasSuffix("  → later\n"))
    }

    func testEmptySessionExportsTheHeaderOnly() throws {
        let exporter = TranscriptExporter(directory: directory, formatter: TranscriptFormatter(timeZone: utc))
        let session = Session(startedAt: start, captureMode: "broadcast", pinnedLanguage: "es", modelID: "base", voice: "alba", joinedInProgress: true)
        context.insert(session)
        try context.save()
        XCTAssertEqual(exporter.text(for: session), "# ReVox session 2023-11-14T22:13:20\n")
        XCTAssertEqual(TranscriptExporter.sortedEntries(of: session), [])
    }

    func testDefaultDirectoryIsTheReVoxTemporaryFolder() {
        let url = TranscriptExporter.defaultDirectory()
        XCTAssertEqual(url.lastPathComponent, TranscriptExporter.directoryName)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, FileManager.default.temporaryDirectory.standardizedFileURL)
    }
}
