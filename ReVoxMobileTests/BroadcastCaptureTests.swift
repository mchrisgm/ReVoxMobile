import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class SilenceDetectorTests: XCTestCase {
    func testReportsOnceAfterTenQuietSecondsAndResetsOnSound() {
        var detector = SilenceDetector()
        XCTAssertEqual(SilenceDetector.thresholdLevel, 0.001)
        XCTAssertEqual(SilenceDetector.requiredSeconds, 10)
        XCTAssertFalse(detector.observe(rms: 0, now: 0))
        XCTAssertFalse(detector.observe(rms: 0.0005, now: 9.9))
        XCTAssertTrue(detector.observe(rms: 0, now: 10))
        XCTAssertFalse(detector.observe(rms: 0, now: 25), "reported once per stretch")
        XCTAssertFalse(detector.observe(rms: 0.2, now: 26), "sound ends the stretch")
        XCTAssertFalse(detector.observe(rms: 0, now: 30))
        XCTAssertTrue(detector.observe(rms: 0, now: 40.5), "a new stretch reports again")
        detector.reset()
        XCTAssertFalse(detector.observe(rms: 0, now: 45))
        XCTAssertTrue(detector.observe(rms: 0, now: 55))
    }
}

/// §6.2 over a temp container: a `RingWriter` over the same file plays the extension.
final class BroadcastCaptureTests: XCTestCase {
    private var container: URL!
    private var suite: String!
    private var records: BroadcastRecordStore!
    private var names: BroadcastNotificationNames!
    private var now: LockedBox<Double>!
    private var capture: BroadcastCapture!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxCapture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        suite = "group.test.revox-\(UUID().uuidString)"
        records = BroadcastRecordStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        names = BroadcastNotificationNames(appGroup: suite)
        now = LockedBox<Double>(1_000)
        let clock = now!
        capture = BroadcastCapture(appGroup: suite, containerURL: container, records: records, clock: { clock.value }, pollInterval: 20_000_000)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    /// The extension side: creates the ring, begins a generation, writes the record.
    private func startExtension(generation: UInt64, prefill: Int = 0) throws -> RingWriter {
        let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: container))
        let writer = try RingWriter(storage: MappedRingStorage(mapping: mapping))
        writer.begin(generation: generation, startedAt: now.value, asbd: RingHeader.ASBD(), pid: 7)
        records.write(BroadcastStateRecord(generation: generation, state: .running, startedAt: now.value, writerPID: 7))
        if prefill > 0 {
            let block = (0 ..< prefill).map { Float($0 % 100) / 100 }
            block.withUnsafeBufferPointer { _ = writer.write($0, at: now.value, pts: RingHeader.PTS()) }
        }
        // The writer's `MappedRingStorage` retains the mapping, so the file stays mapped while the writer lives.
        return writer
    }

    private func write(_ writer: RingWriter, _ samples: [Float]) {
        samples.withUnsafeBufferPointer { _ = writer.write($0, at: now.value, pts: RingHeader.PTS()) }
        DarwinNotificationPoster(name: names.audio).post()
    }

    private func nextEvent(_ iterator: inout AsyncStream<BroadcastCaptureEvent>.AsyncIterator, seconds: Double = 3) async -> BroadcastCaptureEvent? {
        var copy = iterator
        let event = await withTimeout(seconds: seconds) { await copy.next() }
        iterator = copy
        return event
    }

    func testStartRequiresBroadcastMode() async {
        do {
            try await capture.start(.microphone)
            XCTFail("expected unsupportedMode")
        } catch {
            XCTAssertEqual(error as? CaptureError, .unsupportedMode(.microphone))
        }
        XCTAssertFalse(capture.isRunning)
    }

    func testNoRingThenAttachWhenTheExtensionCreatesIt() async throws {
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        let first = await nextEvent(&events)
        XCTAssertEqual(first, .noRing)
        XCTAssertEqual(capture.attachState, .noRing)
        let position = await capture.capturePosition()
        XCTAssertEqual(position, 0, "unmapped: the last known write cursor")

        let writer = try startExtension(generation: 1)
        let attached = await nextEvent(&events)
        XCTAssertEqual(attached, .attached(generation: 1, joinedInProgress: false))
        XCTAssertEqual(capture.attachState, .attachedLive(generation: 1))
        XCTAssertFalse(capture.joinedInProgress)
        let record = try XCTUnwrap(records.readCaptureReader())
        XCTAssertEqual(record.generation, 1)
        XCTAssertEqual(record.lastReadCursor, 0)
        XCTAssertEqual(record.lastAttachedAt, 1_000)
        write(writer, [Float](repeating: 0.5, count: 512))
        let cursor = await capture.capturePosition()
        XCTAssertEqual(cursor, 512, "capturePosition is the ring writeCursor (§5.2)")
        await capture.stop()
    }

    func testFramesCarryAbsolutePositionsAndTheReaderRecordFollows() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        let frames = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 1, joinedInProgress: false))

        now.mutate { $0 = 1_002 }
        let written = (0 ..< 1_536).map { Float($0) / 2_000 }
        write(writer, Array(written[0 ..< 512]))
        write(writer, Array(written[512 ..< 1_536]))
        var received: [Float] = []
        var lastPosition: Int64 = 0
        var iterator = frames.makeAsyncIterator()
        while received.count < 1_536 {
            var copy = iterator
            guard let chunk = await withTimeout(seconds: 3, { await copy.next() }) else { break }
            iterator = copy
            XCTAssertEqual(chunk.samples.count % 512, 0, "512-multiples only")
            XCTAssertEqual(chunk.endPosition, lastPosition + Int64(chunk.samples.count), "positions are contiguous")
            lastPosition = chunk.endPosition
            received.append(contentsOf: chunk.samples)
        }
        XCTAssertEqual(received, written)
        XCTAssertEqual(lastPosition, 1_536)
        // The record is throttled to one write per second of the source's clock, so how many of the reads above
        // wrote it depends on how the 1 536 frames happened to split. Advancing the clock past the throttle and
        // reading once more makes the assertion about the record independent of that split.
        now.mutate { $0 = 1_004 }
        write(writer, [Float](repeating: 0.25, count: 512))
        var tail = iterator
        let last = await withTimeout(seconds: 3) { await tail.next() }
        XCTAssertEqual(last?.endPosition, 2_048)
        XCTAssertEqual(records.readCaptureReader()?.lastReadCursor, 2_048, "the record follows the reads")
        XCTAssertEqual(records.readCaptureReader()?.generation, 1)
        await capture.stop()
    }

    func testJoinedInProgressWhenTheRingIsAheadByMoreThanTheCatchUp() async throws {
        _ = try startExtension(generation: 3, prefill: 40_000)
        var events = capture.events.makeAsyncIterator()
        let frames = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 3, joinedInProgress: true))
        XCTAssertTrue(capture.joinedInProgress)
        var iterator = frames.makeAsyncIterator()
        let first = await withTimeout(seconds: 3) { await iterator.next() }
        let firstStart = try XCTUnwrap(first).endPosition - Int64(try XCTUnwrap(first).samples.count)
        XCTAssertEqual(firstStart, 40_000 - Int64(RingReader.defaultCatchUpFrames), "reading starts 2 s behind the writer")
        await capture.stop()
    }

    func testOverrunBecomesAGapAndCallsTheHandler() async throws {
        let writer = try startExtension(generation: 1)
        let gaps = LockedBox<[Int]>([])
        capture.setGapHandler { dropped in gaps.mutate { $0.append(dropped) } }
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 1, joinedInProgress: false))
        // One write larger than the ring laps the attached reader in a single cursor step (RingWriter keeps the tail).
        let lap = [Float](repeating: 0.1, count: 976_000)
        lap.withUnsafeBufferPointer { _ = writer.write($0, at: now.value, pts: RingHeader.PTS()) }
        var sawGap = false
        for _ in 0 ..< 4 {
            if case .gap(let dropped)? = await nextEvent(&events) {
                XCTAssertGreaterThan(dropped, 884_000, "jumped to writeCursor − catchUp")
                sawGap = true
                break
            }
        }
        XCTAssertTrue(sawGap)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(gaps.value.count, 1, "the handler (the pipeline's noteCaptureGap) ran once")
        await capture.stop()
    }

    func testStaleHeartbeatMarksTheRecordLost() async throws {
        _ = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 1, joinedInProgress: false))
        now.mutate { $0 = 1_005 }                              // 5 s without a heartbeat
        XCTAssertEqual(await nextEvent(&events), .stale(lastWriteAt: 1_000))
        XCTAssertEqual(capture.attachState, .stale(lastWriteAt: 1_000))
        XCTAssertEqual(records.readBroadcastState()?.state, .lost)
        await capture.stop()
    }

    func testFinishedHeaderReportsIdleAndANewGenerationReattaches() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 1, joinedInProgress: false))
        writer.setState(.finished, at: now.value)
        XCTAssertEqual(await nextEvent(&events), .idle)
        XCTAssertEqual(capture.attachState, .idle)
        let second = try startExtension(generation: 2)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 2, joinedInProgress: false))
        write(second, [Float](repeating: 0.2, count: 512))
        let cursor = await capture.capturePosition()
        XCTAssertEqual(cursor, 512)
        await capture.stop()
    }

    func testSilenceIsReportedAfterTenQuietSeconds() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        XCTAssertEqual(await nextEvent(&events), .attached(generation: 1, joinedInProgress: false))
        try? await Task.sleep(nanoseconds: 60_000_000)   // one readAttached at now = 1_000 arms SilenceDetector.quietSince
        for second in 1 ... 11 {
            now.mutate { $0 = 1_000 + Double(second) }
            write(writer, [Float](repeating: 0, count: 16_000))    // the writer's 1 s meter block stays at 0
            try? await Task.sleep(nanoseconds: 30_000_000)         // let a poll observe this timestamp
        }
        var sawSilence = false
        for _ in 0 ..< 3 {
            if case .silence(let seconds)? = await nextEvent(&events) {
                XCTAssertGreaterThanOrEqual(seconds, 10)
                sawSilence = true
                break
            }
        }
        XCTAssertTrue(sawSilence)
        await capture.stop()
    }

    func testStopFinishesTheFrameStreamAndDetaches() async throws {
        _ = try startExtension(generation: 1)
        let frames = capture.frames()
        try await capture.start(.broadcast)
        try? await Task.sleep(nanoseconds: 80_000_000)
        await capture.stop()
        XCTAssertFalse(capture.isRunning)
        XCTAssertEqual(capture.attachState, .noRing)
        var iterator = frames.makeAsyncIterator()
        let end = await withTimeout(seconds: 1) { await iterator.next() }
        XCTAssertNil(end, "the run's stream is finished")
        let fresh = capture.frames()
        try await capture.start(.broadcast)
        var freshIterator = fresh.makeAsyncIterator()
        let stillOpen = await withTimeout(seconds: 0.3) { await freshIterator.next() }
        XCTAssertNil(stillOpen, "no frames were written; the new stream is open, not finished")
        await capture.stop()
    }
}
