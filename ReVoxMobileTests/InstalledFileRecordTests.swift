import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class InstalledFileRecordTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxFileRecord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "ReVoxFileRecord-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ bytes: Int, at relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    func testSnapshotListsRelativePathsAndSizesOfRegularFilesOnly() throws {
        try write(10, at: "a.bin")
        try write(20, at: "nested/b.bin")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty", isDirectory: true), withIntermediateDirectories: true)
        let snapshot = InstalledFileRecord.snapshot(of: root)
        XCTAssertEqual(snapshot, ["a.bin": 10, "nested/b.bin": 20])
        XCTAssertEqual(InstalledFileRecord.snapshot(of: root.appendingPathComponent("absent")), [:])
    }

    func testChangesReportAddedRemovedAndResized() {
        let recorded: [String: Int64] = ["a": 1, "b": 2, "c": 3]
        let current: [String: Int64] = ["a": 1, "b": 9, "d": 4]
        let changes = InstalledFileRecord.changes(recorded: recorded, current: current)
        XCTAssertEqual(changes.added, ["d"])
        XCTAssertEqual(changes.removed, ["c"])
        XCTAssertEqual(changes.resized, ["b"])
        XCTAssertEqual(changes.count, 3)
        XCTAssertFalse(changes.isEmpty)
        XCTAssertEqual(changes.summary, "1 added, 1 removed, 1 resized")
        XCTAssertTrue(InstalledFileRecord.changes(recorded: recorded, current: recorded).isEmpty)
    }

    func testRecordRoundTripAndClearPerKind() {
        let record = InstalledFileRecord(defaults: defaults)
        XCTAssertEqual(InstalledFileRecord.key(for: .vad), "installedFiles.vad")
        XCTAssertEqual(InstalledFileRecord.key(for: .pocketTTS), "installedFiles.pocketTTS")
        XCTAssertEqual(InstalledFileRecord.key(for: .whisper(.small)), "installedFiles.whisper.small")
        XCTAssertEqual(InstalledFileRecord.unpinnedKinds, [.vad, .pocketTTS])

        XCTAssertNil(record.recorded(.vad))
        record.record(.vad, files: ["silero.mlmodelc/coremldata.bin": 42])
        record.record(.pocketTTS, files: ["constants_bin/alba.safetensors": 7])
        XCTAssertEqual(record.recorded(.vad), ["silero.mlmodelc/coremldata.bin": 42])
        XCTAssertEqual(record.recorded(.pocketTTS), ["constants_bin/alba.safetensors": 7])

        record.clear(.vad)
        XCTAssertNil(record.recorded(.vad))
        XCTAssertNotNil(record.recorded(.pocketTTS), "clearing one kind leaves the other alone")
    }
}
