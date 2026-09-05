import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// M11 §5: one JSON file per run under Application Support/ReVox/Benchmarks; the newest run for this iPhone readable.
@MainActor
final class BenchmarkStoreTests: XCTestCase {
    private var directory: URL!
    private let host = BenchmarkHost(device: "iPhone17,1", iOSVersion: "26.0.1", memoryTierGB: 8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxBenchmarks-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveWritesOneFilePerRunAndReloadsNewestFirst() throws {
        let store = BenchmarkStore(directory: directory, host: host, whisperKitVersion: "1.1.0")
        XCTAssertNil(store.latest)
        let older = BenchmarkRun.sample(date: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = BenchmarkRun.sample(date: Date(timeIntervalSince1970: 1_700_000_600))
        try store.save(older)
        try store.save(newer)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("1700000000.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("1700000600.json").path))
        XCTAssertEqual(store.runs.map(\.date), [newer.date, older.date])
        XCTAssertEqual(store.latest, newer)

        let reloaded = BenchmarkStore(directory: directory, host: host, whisperKitVersion: "1.1.0")
        XCTAssertEqual(reloaded.runs, [newer, older])
        XCTAssertEqual(reloaded.latest, newer)
    }

    func testLatestIgnoresOtherHardwareAndOtherLibraryVersions() throws {
        let store = BenchmarkStore(directory: directory, host: host, whisperKitVersion: "1.1.0")
        let mine = BenchmarkRun.sample(date: Date(timeIntervalSince1970: 1_700_000_000), device: "iPhone17,1", whisperKitVersion: "1.1.0")
        let otherPhone = BenchmarkRun.sample(date: Date(timeIntervalSince1970: 1_700_000_600), device: "iPhone14,5", whisperKitVersion: "1.1.0")
        let olderLibrary = BenchmarkRun.sample(date: Date(timeIntervalSince1970: 1_700_001_200), device: "iPhone17,1", whisperKitVersion: "1.0.0")
        try store.save(mine)
        try store.save(otherPhone)
        try store.save(olderLibrary)
        XCTAssertEqual(store.runs.count, 3, "every run is kept on disk")
        XCTAssertEqual(store.latest, mine, "the newest run made on this iPhone with this WhisperKit")
    }

    func testUndecodableFileIsSkipped() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("1699999999.json"))
        try Data("ignored".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let store = BenchmarkStore(directory: directory, host: host)
        XCTAssertEqual(store.runs, [])
        try store.save(.sample())
        XCTAssertEqual(store.runs.count, 1)
    }

    func testMissingDirectoryIsAnEmptyStoreUntilTheFirstSave() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let store = BenchmarkStore(directory: directory, host: host)
        XCTAssertEqual(store.runs, [])
        try store.save(.sample())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDefaultDirectoryIsUnderApplicationSupportReVoxBenchmarks() throws {
        let directory = try BenchmarkStore.defaultDirectory()
        XCTAssertTrue(directory.path.hasSuffix("/ReVox/Benchmarks"), directory.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(BenchmarkStore.folderName, "Benchmarks")
    }

    func testFileNameIsTheRunDateInSeconds() {
        XCTAssertEqual(BenchmarkStore.fileName(for: .sample(date: Date(timeIntervalSince1970: 1_700_000_000))), "1700000000.json")
    }

    func testCurrentHostHasHardwareAndVersion() {
        let current = BenchmarkHost.current(deviceInfo: DeviceInfo(physicalMemoryBytes: 6 * 1_073_741_824))
        XCTAssertFalse(current.device.isEmpty)
        XCTAssertNotEqual(current.device, "unknown")
        XCTAssertTrue(current.iOSVersion.contains("."), current.iOSVersion)
        XCTAssertEqual(current.memoryTierGB, 6)
    }
}
