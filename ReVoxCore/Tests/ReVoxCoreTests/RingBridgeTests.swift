import XCTest
@testable import ReVoxCore

/// R10 ring bridge: layout, header bytes, writer.
final class RingBridgeTests: XCTestCase {
    private func sampleHeader() -> RingHeader {
        RingHeader(magic: "RVXRING1", headerBytes: 4_096, capacityFrames: 960_000, sampleRate: 16_000, channels: 1,
                   sampleFormat: 1, generation: 7, writeCursor: 0x0102_0304_0506_0708, readCursor: 0x1122_3344_5566_7788,
                   state: .paused, asbdChangeCount: 3, lastWriteAt: 1_700_000_000.5, startedAt: 1_700_000_000.25,
                   lastPTS: RingHeader.PTS(value: -42, timescale: 44_100, flags: 0x0000_0003), lastAsbdChangeAt: 1_700_000_001.0,
                   sourceASBD: RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, formatFlags: 0x0000_000E,
                                               bytesPerPacket: 4, framesPerPacket: 1, bytesPerFrame: 4, channelsPerFrame: 2,
                                               bitsPerChannel: 16, reserved: 0),
                   droppedInputFrames: 9, micBuffersSeen: 10, overrunCount: 11, peakLevel1s: 0.5, rmsLevel1s: 0.25, writerPID: 4_242)
    }

    func testLayoutConstants() {
        let layout = RingLayout.v1
        XCTAssertEqual(layout.magic, "RVXRING1")
        XCTAssertEqual(layout.headerBytes, 4_096)
        XCTAssertEqual(layout.capacityFrames, 960_000)
        XCTAssertEqual(layout.sampleRate, 16_000)
        XCTAssertEqual(layout.dataBytes, 3_840_000)
        XCTAssertEqual(layout.totalBytes, 3_844_096)
        XCTAssertEqual(RingLayout.fileName, "audio-ring-v1.bin")
    }

    func testHeapStorageSizedExactly() {
        let storage = HeapRingStorage(layout: .v1)
        XCTAssertEqual(storage.count, 3_844_096)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.writeCursor), 0)   // zero-initialised
        storage.storeCursor(123, at: RingHeader.Offset.writeCursor)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.writeCursor), 123)
        XCTAssertEqual(HeapRingStorage(bytes: 100).count, 100)
    }

    func testHeaderGoldenBytesAndRoundTrip() {
        let storage = HeapRingStorage(layout: .v1)
        let header = sampleHeader()
        header.write(to: storage)
        let bytes = (0 ..< 172).map { storage.base.load(fromByteOffset: $0, as: UInt8.self) }
        XCTAssertEqual(Array(bytes[0 ..< 8]), Array("RVXRING1".utf8))
        XCTAssertEqual(Array(bytes[8 ..< 12]), [0x00, 0x10, 0x00, 0x00])                 // 4096 LE
        XCTAssertEqual(Array(bytes[12 ..< 16]), [0x00, 0xA6, 0x0E, 0x00])                // 960000 = 0x000EA600 LE
        XCTAssertEqual(Array(bytes[16 ..< 20]), [0x80, 0x3E, 0x00, 0x00])                // 16000 LE
        XCTAssertEqual(Array(bytes[20 ..< 22]), [0x01, 0x00])                            // channels
        XCTAssertEqual(Array(bytes[22 ..< 24]), [0x01, 0x00])                            // Float32 LE
        XCTAssertEqual(Array(bytes[24 ..< 32]), [7, 0, 0, 0, 0, 0, 0, 0])                // generation
        XCTAssertEqual(Array(bytes[32 ..< 40]), [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])   // writeCursor
        XCTAssertEqual(Array(bytes[40 ..< 48]), [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])   // readCursor
        XCTAssertEqual(Array(bytes[48 ..< 52]), [2, 0, 0, 0])                            // state paused
        XCTAssertEqual(Array(bytes[52 ..< 56]), [3, 0, 0, 0])                            // asbdChangeCount
        XCTAssertEqual(Array(bytes[56 ..< 64]), withUnsafeBytes(of: (1_700_000_000.5).bitPattern.littleEndian, Array.init))
        XCTAssertEqual(Array(bytes[64 ..< 72]), withUnsafeBytes(of: (1_700_000_000.25).bitPattern.littleEndian, Array.init))
        XCTAssertEqual(Array(bytes[72 ..< 80]), withUnsafeBytes(of: Int64(-42).littleEndian, Array.init))
        XCTAssertEqual(Array(bytes[80 ..< 84]), [0x44, 0xAC, 0x00, 0x00])                // timescale 44100
        XCTAssertEqual(Array(bytes[84 ..< 88]), [3, 0, 0, 0])                            // pts flags
        XCTAssertEqual(Array(bytes[88 ..< 96]), withUnsafeBytes(of: (1_700_000_001.0).bitPattern.littleEndian, Array.init))
        XCTAssertEqual(Array(bytes[96 ..< 104]), withUnsafeBytes(of: (44_100.0).bitPattern.littleEndian, Array.init))   // ASBD.mSampleRate
        XCTAssertEqual(Array(bytes[104 ..< 108]), [0x6D, 0x63, 0x70, 0x6C])              // 'lpcm'
        XCTAssertEqual(Array(bytes[108 ..< 112]), [0x0E, 0, 0, 0])
        XCTAssertEqual(Array(bytes[112 ..< 116]), [4, 0, 0, 0])
        XCTAssertEqual(Array(bytes[116 ..< 120]), [1, 0, 0, 0])
        XCTAssertEqual(Array(bytes[120 ..< 124]), [4, 0, 0, 0])
        XCTAssertEqual(Array(bytes[124 ..< 128]), [2, 0, 0, 0])
        XCTAssertEqual(Array(bytes[128 ..< 132]), [16, 0, 0, 0])
        XCTAssertEqual(Array(bytes[132 ..< 136]), [0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[136 ..< 144]), [9, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[144 ..< 152]), [10, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[152 ..< 160]), [11, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(Array(bytes[160 ..< 164]), [0x00, 0x00, 0x00, 0x3F])              // 0.5f
        XCTAssertEqual(Array(bytes[164 ..< 168]), [0x00, 0x00, 0x80, 0x3E])              // 0.25f
        XCTAssertEqual(Array(bytes[168 ..< 172]), [0x92, 0x10, 0x00, 0x00])              // pid 4242
        XCTAssertEqual(RingHeader.read(from: storage), header)
    }

    func testReadReturnsNilOnBadMagicOrShortStorage() {
        XCTAssertNil(RingHeader.read(from: HeapRingStorage(layout: .v1)))               // zeroed: no magic
        XCTAssertNil(RingHeader.read(from: HeapRingStorage(bytes: 100)))
        let storage = HeapRingStorage(layout: .v1)
        sampleHeader().write(to: storage)
        storage.base.storeBytes(of: UInt8(ascii: "X"), toByteOffset: 0, as: UInt8.self)
        XCTAssertNil(RingHeader.read(from: storage))
    }

    func testWriterBeginWritesHeader() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        let asbd = RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, channelsPerFrame: 2, bitsPerChannel: 16)
        writer.begin(generation: 3, startedAt: 1_000, asbd: asbd, pid: 77)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.magic, "RVXRING1")
        XCTAssertEqual(header.headerBytes, 4_096)
        XCTAssertEqual(header.capacityFrames, 960_000)
        XCTAssertEqual(header.sampleRate, 16_000)
        XCTAssertEqual(header.channels, 1)
        XCTAssertEqual(header.sampleFormat, 1)
        XCTAssertEqual(header.generation, 3)
        XCTAssertEqual(header.writeCursor, 0)
        XCTAssertEqual(header.readCursor, 0)
        XCTAssertEqual(header.state, .running)
        XCTAssertEqual(header.startedAt, 1_000)
        XCTAssertEqual(header.lastWriteAt, 1_000)
        XCTAssertEqual(header.sourceASBD, asbd)
        XCTAssertEqual(header.writerPID, 77)
        XCTAssertEqual(writer.writeCursor, 0)
    }

    func testWriteAcrossWrapBoundaryPlacesSamplesPhysically() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        let zeros = [Float](repeating: 0, count: 959_800)
        zeros.withUnsafeBufferPointer { _ = writer.write($0, at: 1, pts: RingHeader.PTS()) }
        let ramp = (0 ..< 400).map { Float($0) }
        let cursor = ramp.withUnsafeBufferPointer { writer.write($0, at: 2, pts: RingHeader.PTS(value: 1_024, timescale: 44_100, flags: 1)) }
        XCTAssertEqual(cursor, 960_200)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.writeCursor), 960_200)
        let data = storage.base + RingLayout.v1.headerBytes
        XCTAssertEqual(data.load(fromByteOffset: 959_800 * 4, as: Float.self), 0)      // first ramp sample
        XCTAssertEqual(data.load(fromByteOffset: 959_999 * 4, as: Float.self), 199)    // last sample before the wrap
        XCTAssertEqual(data.load(fromByteOffset: 0, as: Float.self), 200)              // continues at the start
        XCTAssertEqual(data.load(fromByteOffset: 199 * 4, as: Float.self), 399)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.lastWriteAt, 2)                                           // heartbeat after the cursor
        XCTAssertEqual(header.lastPTS, RingHeader.PTS(value: 1_024, timescale: 44_100, flags: 1))
    }

    func testWriterCountersStateAndMeter() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        writer.noteDroppedInput(frames: 1_024)
        writer.noteDroppedInput(frames: 1)
        writer.noteMicBuffer()
        writer.noteFormatChange(RingHeader.ASBD(sampleRate: 48_000, channelsPerFrame: 1), at: 5)
        writer.setState(.paused, at: 6)
        var header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.droppedInputFrames, 1_025)
        XCTAssertEqual(header.micBuffersSeen, 1)
        XCTAssertEqual(header.asbdChangeCount, 1)
        XCTAssertEqual(header.lastAsbdChangeAt, 5)
        XCTAssertEqual(header.sourceASBD.sampleRate, 48_000)
        XCTAssertEqual(header.state, .paused)
        XCTAssertEqual(header.lastWriteAt, 6)
        // 1 s of ±0.5 square wave fills the meter block: peak 0.5, rms 0.5
        let square = (0 ..< 16_000).map { $0 % 2 == 0 ? Float(0.5) : Float(-0.5) }
        square.withUnsafeBufferPointer { _ = writer.write($0, at: 7, pts: RingHeader.PTS()) }
        header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.peakLevel1s, 0.5)
        XCTAssertEqual(header.rmsLevel1s, 0.5, accuracy: 0.0001)
    }

    func testWriterRejectsTooSmallStorage() {
        XCTAssertThrowsError(try RingWriter(storage: HeapRingStorage(bytes: 100))) { error in
            XCTAssertEqual(error as? RingError, .tooSmall)
        }
    }

    func testWriteLongerThanCapacityKeepsTail() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        let long = (0 ..< 960_100).map { Float($0) }
        let cursor = long.withUnsafeBufferPointer { writer.write($0, at: 1, pts: RingHeader.PTS()) }
        XCTAssertEqual(cursor, 960_100)
        let data = storage.base + RingLayout.v1.headerBytes
        XCTAssertEqual(data.load(fromByteOffset: 100 * 4, as: Float.self), 100)        // physical 100 = absolute 100
        XCTAssertEqual(data.load(fromByteOffset: 0, as: Float.self), 960_000)          // physical 0 = absolute 960 000
    }

    func testAnEmptyWriteOnlyTouchesTheHeartbeat() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        let cursor = [Float]().withUnsafeBufferPointer { writer.write($0, at: 9, pts: RingHeader.PTS(value: 3, timescale: 1, flags: 0)) }
        XCTAssertEqual(cursor, 0)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.writeCursor, 0)
        XCTAssertEqual(header.lastWriteAt, 9)
        XCTAssertEqual(header.lastPTS.value, 3)
    }

    func testNegativeDroppedInputIsIgnored() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        writer.noteDroppedInput(frames: -5)
        XCTAssertEqual(RingHeader.read(from: storage)?.droppedInputFrames, 0)
        writer.noteDroppedInput(frames: 2)
        XCTAssertEqual(RingHeader.read(from: storage)?.droppedInputFrames, 2)
    }

    func testBeginResetsTheCountersOfThePreviousGeneration() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 0, asbd: RingHeader.ASBD(), pid: 1)
        writer.noteDroppedInput(frames: 7)
        writer.noteMicBuffer()
        [Float](repeating: 0, count: 512).withUnsafeBufferPointer { _ = writer.write($0, at: 1, pts: RingHeader.PTS()) }
        writer.begin(generation: 2, startedAt: 5, asbd: RingHeader.ASBD(), pid: 1)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.generation, 2)
        XCTAssertEqual(header.writeCursor, 0)
        XCTAssertEqual(header.droppedInputFrames, 0)
        XCTAssertEqual(header.micBuffersSeen, 0)
        XCTAssertEqual(writer.writeCursor, 0)
    }

    func testAZeroByteStorageIsSafe() {
        let storage = HeapRingStorage(bytes: 0)
        XCTAssertEqual(storage.count, 0)
        XCTAssertNil(RingHeader.read(from: storage))
        XCTAssertThrowsError(try RingWriter(storage: storage)) { XCTAssertEqual($0 as? RingError, .tooSmall) }
        XCTAssertThrowsError(try RingReader(storage: storage)) { XCTAssertEqual($0 as? RingError, .tooSmall) }
    }

    func testAnUnknownStateReadsAsFailed() throws {
        let storage = HeapRingStorage(layout: .v1)
        sampleHeader().write(to: storage)
        storage.base.storeUInt32(99, RingHeader.Offset.state)
        XCTAssertEqual(RingHeader.read(from: storage)?.state, .failed)
    }
}
