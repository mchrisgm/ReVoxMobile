import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class ModelStorageTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxStorage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ bytes: Int, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    func testAllocatedBytesSumsRegularFilesAndIsZeroForAMissingFolder() throws {
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try write(10_000, at: folder.appendingPathComponent("a.bin"))
        try write(70_000, at: folder.appendingPathComponent("nested/b.bin"))
        let allocated = ModelStorage.allocatedBytes(under: folder)
        XCTAssertGreaterThanOrEqual(allocated, 80_000, "the allocated size never undercounts the logical size")
        XCTAssertLessThan(allocated, 80_000 + 2 * 1_048_576, "block rounding stays below one MiB per file")
        XCTAssertEqual(ModelStorage.allocatedBytes(under: root.appendingPathComponent("absent")), 0)
    }

    func testFoldersPerKindFollowTheLayout() {
        let small = ModelCatalog.whisper(.small)
        XCTAssertEqual(ModelStorage.folders(for: .whisper(.small), layout: layout).map(\.path),
                       [layout.whisperFolder(small).path, layout.whisperSidecarCache(small).path, layout.tokenizerFolder(small).path])
        XCTAssertEqual(ModelStorage.folders(for: .vad, layout: layout).map(\.path), [layout.vadRepoDirectory.path])
        XCTAssertEqual(ModelStorage.folders(for: .pocketTTS, layout: layout).map(\.path),
                       [layout.fluidModelsDirectory.appendingPathComponent(ModelLayout.pocketTTSFolder, isDirectory: true).path])
    }

    func testUsageCountsInstalledKindsOnlyAndPassesFreeBytesThrough() throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        try write(50_000, at: layout.whisperFolder(ModelCatalog.whisper(.base)).appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin"))
        try FakeInstallSteps.fabricateVAD(in: layout)
        let usage = ModelStorage.usage(layout: layout, availableBytes: 12_000_000_000)
        XCTAssertEqual(Set(usage.bytesByKind.keys), [.whisper(.base), .vad])
        XCTAssertNil(usage.bytes(for: .whisper(.small)))
        XCTAssertNil(usage.bytes(for: .pocketTTS))
        XCTAssertGreaterThanOrEqual(usage.bytes(for: .whisper(.base)) ?? 0, 50_000)
        XCTAssertEqual(usage.totalBytes, usage.bytesByKind.values.reduce(0, +))
        XCTAssertEqual(usage.freeBytes, 12_000_000_000)
        XCTAssertNil(ModelStorage.usage(layout: layout, availableBytes: nil).freeBytes)
        XCTAssertEqual(ModelStorageUsage.empty.totalBytes, 0)
    }

    func testALeftoverTokenizerFolderDoesNotCountAsAnInstalledModel() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        try FileManager.default.removeItem(at: layout.whisperFolder(ModelCatalog.whisper(.tiny)))
        XCTAssertNil(ModelStorage.usage(layout: layout, availableBytes: nil).bytes(for: .whisper(.tiny)))
    }
}
