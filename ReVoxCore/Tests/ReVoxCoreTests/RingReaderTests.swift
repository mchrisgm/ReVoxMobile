import XCTest
@testable import ReVoxCore

/// R10 ring bridge: the reader's attach table, wrap, guard, overrun and generation handling.
final class RingReaderTests: XCTestCase {
    private func makeRing(generation: UInt64 = 1, startedAt: Double = 1_000) throws -> (HeapRingStorage, RingWriter) {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: generation, startedAt: startedAt, asbd: RingHeader.ASBD(), pid: 42)
        return (storage, writer)
    }

    private func write(_ writer: RingWriter, _ samples: [Float], at time: Double = 1_001) {
        samples.withUnsafeBufferPointer { _ = writer.write($0, at: time, pts: RingHeader.PTS()) }
    }

    private func read(_ reader: RingReader, capacity: Int = 16_000, guard guardFrames: Int = RingReader.defaultGuardFrames) -> (ReadResult, [Float]) {
        var buffer = [Float](repeating: 0, count: capacity)
        let result = buffer.withUnsafeMutableBufferPointer { reader.read(into: $0, guard: guardFrames) }
        return (result, buffer)
    }

    func testDefaultGuardCatchUpStale() {
        XCTAssertEqual(RingReader.defaultGuardFrames, 16_000)
        XCTAssertEqual(RingReader.defaultCatchUpFrames, 32_000)
        XCTAssertEqual(RingReader.staleAfterSeconds, 3)
    }

    func testInitErrors() throws {
        XCTAssertThrowsError(try RingReader(storage: HeapRingStorage(bytes: 100))) {
            XCTAssertEqual($0 as? RingError, .tooSmall)
        }
        XCTAssertThrowsError(try RingReader(storage: HeapRingStorage(layout: .v1))) {   // never written: no magic
            XCTAssertEqual($0 as? RingError, .badMagic)
        }
        let (storage, _) = try makeRing()
        storage.base.storeUInt32(480_000, RingHeader.Offset.capacityFrames)
        XCTAssertThrowsError(try RingReader(storage: storage)) {
            XCTAssertEqual($0 as? RingError, .unsupportedLayout)
        }
    }

    func testAttachTable() throws {
        let (storage, writer) = try makeRing(generation: 2, startedAt: 1_000)
        write(writer, [Float](repeating: 0, count: 50_000), at: 1_001)             // writeCursor 50 000
        let reader = try RingReader(storage: storage)

        // running, fresh heartbeat, no record → live, cursor = writeCursor − catchUp
        XCTAssertEqual(reader.attach(now: 1_002, storedReadCursor: nil, storedGeneration: nil), .attachedLive(generation: 2))
        XCTAssertEqual(reader.readCursor, 18_000)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.readCursor), 18_000)

        // a record for this generation ahead of the catch-up point is honoured
        XCTAssertEqual(reader.attach(now: 1_002, storedReadCursor: 40_000, storedGeneration: 2), .attachedLive(generation: 2))
        XCTAssertEqual(reader.readCursor, 40_000)

        // a record behind the catch-up point is overridden
        XCTAssertEqual(reader.attach(now: 1_002, storedReadCursor: 1_000, storedGeneration: 2), .attachedLive(generation: 2))
        XCTAssertEqual(reader.readCursor, 18_000)

        // a record ahead of the writer is clamped
        XCTAssertEqual(reader.attach(now: 1_002, storedReadCursor: 99_000, storedGeneration: 2), .attachedLive(generation: 2))
        XCTAssertEqual(reader.readCursor, 50_000)

        // heartbeat older than 3 s → stale, nothing read
        XCTAssertEqual(reader.attach(now: 1_004.5, storedReadCursor: nil, storedGeneration: nil), .stale(lastWriteAt: 1_001))
        XCTAssertEqual(reader.attach(now: 1_004, storedReadCursor: nil, storedGeneration: nil), .attachedLive(generation: 2))   // exactly 3 s is live

        // paused / finished / failed / idle → idle
        for state in [RingHeader.State.paused, .finished, .failed, .idle] {
            writer.setState(state, at: 1_002)
            XCTAssertEqual(reader.attach(now: 1_002, storedReadCursor: nil, storedGeneration: nil), .idle, "\(state)")
        }
    }

    func testGenerationChangeResetsReader() throws {
        let (storage, writer) = try makeRing(generation: 3)
        write(writer, [Float](repeating: 0, count: 40_000))
        let reader = try RingReader(storage: storage)
        // the stored record is from generation 2: its cursor is ignored, the header is trusted
        XCTAssertEqual(reader.attach(now: 1_001, storedReadCursor: 39_000, storedGeneration: 2), .attachedLive(generation: 3))
        XCTAssertEqual(reader.readCursor, 8_000)
    }

    func testReadReturns512MultiplesOnly() throws {
        let (storage, writer) = try makeRing()
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        write(writer, (0 ..< 1_000).map(Float.init))
        let (first, buffer) = read(reader)
        XCTAssertEqual(first, .frames(512))
        XCTAssertEqual(reader.readCursor, 512)
        XCTAssertEqual(Array(buffer[0 ..< 512]), (0 ..< 512).map(Float.init))
        XCTAssertEqual(read(reader).0, .idle)                                        // 488 pending < 512
        write(writer, (1_000 ..< 1_024).map(Float.init))
        let (second, secondBuffer) = read(reader)
        XCTAssertEqual(second, .frames(512))
        XCTAssertEqual(Array(secondBuffer[0 ..< 512]), (512 ..< 1_024).map(Float.init))
        XCTAssertEqual(reader.readCursor, 1_024)
        XCTAssertEqual(storage.loadCursor(at: RingHeader.Offset.readCursor), 1_024)
        XCTAssertEqual(read(reader).0, .idle)
    }

    func testReadIsBoundedByTheBuffer() throws {
        let (storage, writer) = try makeRing()
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        write(writer, [Float](repeating: 1, count: 20_000))
        XCTAssertEqual(read(reader, capacity: 16_000).0, .frames(15_872))            // 31 × 512
        XCTAssertEqual(read(reader, capacity: 16_000).0, .frames(4_096))             // 4 128 left → 8 × 512
        XCTAssertEqual(read(reader).0, .idle)
    }

    func testWriteAcrossWrapReadsBackInOrder() throws {
        let (storage, writer) = try makeRing()
        write(writer, [Float](repeating: 0, count: 959_744))                          // 1 874 × 512, 256 before the end
        let reader = try RingReader(storage: storage)
        XCTAssertEqual(reader.attach(now: 1_001, storedReadCursor: 959_744, storedGeneration: 1), .attachedLive(generation: 1))
        XCTAssertEqual(reader.readCursor, 959_744)
        let ramp = (0 ..< 1_024).map(Float.init)
        write(writer, ramp)                                                           // wraps after 256 samples
        let (result, buffer) = read(reader)
        XCTAssertEqual(result, .frames(1_024))
        XCTAssertEqual(Array(buffer[0 ..< 1_024]), ramp)
        XCTAssertEqual(reader.readCursor, 960_768)
    }

    func testLaggingReaderGetsGapAndJumps() throws {
        let (storage, writer) = try makeRing()
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        for _ in 0 ..< 60 {
            write(writer, [Float](repeating: 0.5, count: 16_000))                     // 960 000 frames: exactly one lap
        }
        let (result, _) = read(reader)
        XCTAssertEqual(result, .gap(dropped: 928_000))                                // 960 000 − 32 000
        XCTAssertEqual(reader.readCursor, 928_000)
        XCTAssertEqual(reader.overrunCount, 1)
        XCTAssertEqual(reader.header?.overrunCount, 1)
        XCTAssertEqual(read(reader).0, .frames(15_872))                               // reading resumes from the jump
    }

    func testGuardBoundaryIsExact() throws {
        // capacity − guard = 944 000 frames behind the writer still reads …
        let (storage, writer) = try makeRing()
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        write(writer, [Float](repeating: 0.5, count: 944_000))
        XCTAssertEqual(read(reader).0, .frames(15_872))
        XCTAssertEqual(reader.overrunCount, 0)

        // … one frame more is an overrun.
        let (storage2, writer2) = try makeRing()
        let reader2 = try RingReader(storage: storage2)
        _ = reader2.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        write(writer2, [Float](repeating: 0.5, count: 944_001))
        XCTAssertEqual(read(reader2).0, .gap(dropped: 944_001 - 32_000))
        XCTAssertEqual(reader2.readCursor, 912_001)
        XCTAssertEqual(reader2.overrunCount, 1)
    }

    func testOvertakingWriterDiscardsCopy() throws {
        let inner = HeapRingStorage(layout: .v1)
        let storage = OvertakingCursorStorage(inner: inner, advance: 950_000)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 42)
        write(writer, (0 ..< 1_024).map(Float.init))
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_001, storedReadCursor: nil, storedGeneration: nil)
        storage.arm()                                                                 // second load inside read() jumps ahead
        let (result, _) = read(reader)
        XCTAssertEqual(result, .gap(dropped: 951_024 - 32_000))
        XCTAssertEqual(reader.readCursor, 919_024)
        XCTAssertEqual(reader.overrunCount, 1)
        XCTAssertEqual(reader.header?.overrunCount, 1)
    }

    func testRewindingWriterDiscardsCopyAndLeavesTheCursor() throws {
        // A broadcast restarting mid-read: RingWriter.begin zeroes writeCursor, so the reader's post-copy re-check
        // can see a cursor behind its own start. Nothing is consumed and no header field is touched — the adapter
        // re-attaches on the generation change.
        let inner = HeapRingStorage(layout: .v1)
        let storage = RewindingCursorStorage(inner: inner, rewindTo: 0)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 42)
        write(writer, (0 ..< 1_024).map(Float.init))
        let reader = try RingReader(storage: storage)
        XCTAssertEqual(reader.attach(now: 1_001, storedReadCursor: 1_024, storedGeneration: 1), .attachedLive(generation: 1))
        XCTAssertEqual(reader.readCursor, 1_024)
        write(writer, (1_024 ..< 2_048).map(Float.init))
        storage.arm()                                                                 // second load inside read() rewinds
        XCTAssertEqual(read(reader).0, .idle)
        XCTAssertEqual(reader.readCursor, 1_024)
        XCTAssertEqual(reader.overrunCount, 0)
        XCTAssertEqual(inner.loadCursor(at: RingHeader.Offset.readCursor), 1_024)
        XCTAssertEqual(inner.base.loadUInt64(RingHeader.Offset.overrunCount), 0)
    }

    func testHeaderReflectsWriter() throws {
        let (storage, writer) = try makeRing(generation: 9)
        let reader = try RingReader(storage: storage)
        XCTAssertEqual(reader.header?.generation, 9)
        XCTAssertEqual(reader.header?.writerPID, 42)
        write(writer, [Float](repeating: 0, count: 512), at: 1_234)
        XCTAssertEqual(reader.header?.writeCursor, 512)
        XCTAssertEqual(reader.header?.lastWriteAt, 1_234)
    }

    // MARK: docs/security-review-m5.md — a hostile or corrupted ring must degrade, never trap

    func testACursorAboveThePlausibleBoundIsRefusedInsteadOfTrapping() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 1)
        let reader = try RingReader(storage: storage)
        XCTAssertEqual(reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil), .attachedLive(generation: 1))

        // One flipped bit in bit 63 of the 8 bytes at offset 32 — the magic and the geometry are untouched, so every
        // check that runs once at init still passes. `Int(_: UInt64)` on this value would trap.
        storage.storeCursor(0x8000_0000_0004_0000, at: RingHeader.Offset.writeCursor)
        var scratch = [Float](repeating: 0, count: 1_024)
        let result = scratch.withUnsafeMutableBufferPointer { reader.read(into: $0) }
        XCTAssertEqual(result, .idle, "a lying cursor is nothing to read, not a gap of 9 quintillion frames")
        XCTAssertEqual(reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil), .noRing)
        XCTAssertEqual(RingReader.maxPlausibleCursor, 1 << 48)
    }

    func testACorruptedMagicAfterInitReadsAsNilInsteadOfCrashing() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 1)
        let reader = try RingReader(storage: storage)
        XCTAssertNotNil(reader.header)
        storage.base.storeBytes(of: UInt8(0xFF), toByteOffset: RingHeader.Offset.magic, as: UInt8.self)
        XCTAssertNil(reader.header, "the writer is another process; the page can stop being a header at any time")
        XCTAssertEqual(reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil), .noRing)
    }

    func testNonFiniteSamplesAreZeroedBeforeTheyLeaveTheRing() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 1_000, asbd: RingHeader.ASBD(), pid: 1)
        let reader = try RingReader(storage: storage)
        _ = reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil)
        var poisoned = [Float](repeating: 0.25, count: 512)
        poisoned[7] = .nan
        poisoned[300] = .infinity
        poisoned[301] = -.infinity
        poisoned.withUnsafeBufferPointer { _ = writer.write($0, at: 1_000, pts: RingHeader.PTS()) }

        var scratch = [Float](repeating: -1, count: 1_024)
        let result = scratch.withUnsafeMutableBufferPointer { reader.read(into: $0) }
        XCTAssertEqual(result, .frames(512))
        let read = Array(scratch[0 ..< 512])
        XCTAssertTrue(read.allSatisfy { $0.isFinite }, "one NaN would poison the VAD's LSTM state for the whole run")
        XCTAssertEqual(read[7], 0)
        XCTAssertEqual(read[300], 0)
        XCTAssertEqual(read[301], 0)
        XCTAssertEqual(read[8], 0.25, "finite samples are untouched")
    }

    func testAHeartbeatFromTheFutureIsStaleNotLive() throws {
        let storage = HeapRingStorage(layout: .v1)
        let writer = try RingWriter(storage: storage)
        writer.begin(generation: 1, startedAt: 5_000, asbd: RingHeader.ASBD(), pid: 1)
        let reader = try RingReader(storage: storage)
        // The device clock stepped backwards (an NTP correction, or the user editing the date) after the extension
        // was killed with `state == running`. A one-sided window would call this dead broadcast live.
        XCTAssertEqual(reader.attach(now: 1_000, storedReadCursor: nil, storedGeneration: nil), .stale(lastWriteAt: 5_000))
        let header = try XCTUnwrap(reader.header)
        XCTAssertFalse(header.isHeartbeatFresh(now: 1_000))
        XCTAssertFalse(header.isHeartbeatFresh(now: 5_004))
        XCTAssertTrue(header.isHeartbeatFresh(now: 5_002))
        XCTAssertTrue(header.isHeartbeatFresh(now: 4_998))
        XCTAssertFalse(header.isHeartbeatFresh(now: .nan), "a non-finite clock is never fresh")
    }
}
