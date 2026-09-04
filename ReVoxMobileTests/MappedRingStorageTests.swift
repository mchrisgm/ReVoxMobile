import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// R10 ring bridge over a real file: two MAP_SHARED mappings of one temp file stand in for the two processes.
final class MappedRingStorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxRing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var ringURL: URL { RingFileMapping.ringURL(in: directory) }

    func testRingURLIsUnderApplicationSupportReVox() {
        XCTAssertEqual(ringURL.path, directory.appendingPathComponent("Library/Application Support/ReVox/audio-ring-v1.bin").path)
        XCTAssertEqual(ringURL.lastPathComponent, RingLayout.fileName)
    }

    func testOpenExistingReportsAbsentAndTooSmallAndNeverCreates() throws {
        XCTAssertThrowsError(try RingFileMapping.openExisting(at: ringURL)) { error in
            XCTAssertEqual(error as? RingFileError, .absent)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: ringURL.path), "the app side never creates the file")
        try FileManager.default.createDirectory(at: ringURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: ringURL.path, contents: Data(count: 100)))
        XCTAssertThrowsError(try RingFileMapping.openExisting(at: ringURL)) { error in
            XCTAssertEqual(error as? RingFileError, .tooSmall(actualBytes: 100))
        }
        let size = try FileManager.default.attributesOfItem(atPath: ringURL.path)[.size] as? Int
        XCTAssertEqual(size, 100, "the app side never grows the file either")
    }

    func testOpenCreatingCreatesGrowsExcludesFromBackupAndNeverShrinks() throws {
        let created = try RingFileMapping.openCreating(at: ringURL)
        XCTAssertEqual(created.count, RingLayout.v1.totalBytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: ringURL.path)[.size] as? Int, 3_844_096)
        let values = try ringURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        let handle = try FileHandle(forUpdating: ringURL)
        try handle.truncate(atOffset: 4_000_000)
        try handle.close()
        let reopened = try RingFileMapping.openCreating(at: ringURL)
        XCTAssertEqual(reopened.count, RingLayout.v1.totalBytes, "the mapping covers the layout")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: ringURL.path)[.size] as? Int, 4_000_000, "never shrunk")
    }

    func testCursorAccessorsRoundTripThroughTheShimAsLittleEndian() throws {
        let storage = MappedRingStorage(mapping: try RingFileMapping.openCreating(at: ringURL))
        XCTAssertEqual(storage.count, 3_844_096)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.writeCursor), 0)
        storage.storeCursor(0x0102_0304_0506_0708, at: RingHeader.Offset.writeCursor)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.writeCursor), 0x0102_0304_0506_0708)
        let bytes = (0 ..< 8).map { storage.base.load(fromByteOffset: RingHeader.Offset.writeCursor + $0, as: UInt8.self) }
        XCTAssertEqual(bytes, [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01], "same on-disk order as HeapRingStorage")
    }

    func testZeroDataRegionLeavesTheHeaderAlone() throws {
        let mapping = try RingFileMapping.openCreating(at: ringURL)
        let storage = MappedRingStorage(mapping: mapping)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 4, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 9)
        [Float](repeating: 0.25, count: 512).withUnsafeBufferPointer { _ = writer.write($0, at: 1_001, pts: RingHeader.PTS()) }
        mapping.zeroDataRegion()
        XCTAssertEqual((mapping.base + RingLayout.v1.headerBytes).load(as: Float.self), 0)
        XCTAssertEqual(RingHeader.read(from: storage)?.generation, 4)
        XCTAssertEqual(RingHeader.read(from: storage)?.writeCursor, 512)
    }

    func testWriterAndReaderOnTwoMappingsAndTwoThreads() throws {
        let writerStorage = MappedRingStorage(mapping: try RingFileMapping.openCreating(at: ringURL))
        let readerStorage = MappedRingStorage(mapping: try RingFileMapping.openExisting(at: ringURL))
        let writer = try RingWriter(storage: writerStorage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 1)
        let reader = try RingReader(storage: readerStorage)
        XCTAssertEqual(reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil), .attachedLive(generation: 1))

        let blocks = 200
        let total = blocks * 512
        let writerThread = Thread {
            for block in 0 ..< blocks {
                let samples = (0 ..< 512).map { Float(block * 512 + $0) }
                samples.withUnsafeBufferPointer { _ = writer.write($0, at: 1_001, pts: RingHeader.PTS()) }
                usleep(200)
            }
        }
        writerThread.start()

        var received: [Float] = []
        var scratch = [Float](repeating: 0, count: 16_000)
        let deadline = Date().addingTimeInterval(10)
        while received.count < total, Date() < deadline {
            let result = scratch.withUnsafeMutableBufferPointer { reader.read(into: $0) }
            switch result {
            case .frames(let count):
                received.append(contentsOf: scratch[0 ..< count])
            case .gap:
                XCTFail("no overrun expected: the reader keeps up with 200 µs blocks")
            case .idle:
                usleep(100)
            }
        }
        XCTAssertEqual(received.count, total)
        XCTAssertEqual(received, (0 ..< total).map(Float.init))
        XCTAssertEqual(reader.readCursor, UInt64(total))
        XCTAssertEqual(writerStorage.loadCursor(at: RingHeader.Offset.readCursor), UInt64(total), "the reader's cursor is visible through the writer's mapping")
        XCTAssertEqual(RingHeader.read(from: writerStorage)?.writeCursor, UInt64(total))
    }
}
