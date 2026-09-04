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
        let event1 = await nextEvent(&events)
        XCTAssertEqual(event1, .attached(generation: 1, joinedInProgress: false))

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
        let event2 = await nextEvent(&events)
        XCTAssertEqual(event2, .attached(generation: 3, joinedInProgress: true))
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
        let event3 = await nextEvent(&events)
        XCTAssertEqual(event3, .attached(generation: 1, joinedInProgress: false))
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
        let event4 = await nextEvent(&events)
        XCTAssertEqual(event4, .attached(generation: 1, joinedInProgress: false))
        now.mutate { $0 = 1_005 }                              // 5 s without a heartbeat
        let event5 = await nextEvent(&events)
        XCTAssertEqual(event5, .stale(lastWriteAt: 1_000))
        XCTAssertEqual(capture.attachState, .stale(lastWriteAt: 1_000))
        XCTAssertEqual(records.readBroadcastState()?.state, .lost)
        await capture.stop()
    }

    func testFinishedHeaderReportsIdleAndANewGenerationReattaches() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        let event6 = await nextEvent(&events)
        XCTAssertEqual(event6, .attached(generation: 1, joinedInProgress: false))
        writer.setState(.finished, at: now.value)
        let event7 = await nextEvent(&events)
        XCTAssertEqual(event7, .idle)
        XCTAssertEqual(capture.attachState, .idle)
        let second = try startExtension(generation: 2)
        let event8 = await nextEvent(&events)
        XCTAssertEqual(event8, .attached(generation: 2, joinedInProgress: false))
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
        let event9 = await nextEvent(&events)
        XCTAssertEqual(event9, .attached(generation: 1, joinedInProgress: false))
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

    func testSpeakingEdgesProduceASelfCaptureMeasurement() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        let frames = capture.frames()
        try await capture.start(.broadcast)
        let event10 = await nextEvent(&events)
        XCTAssertEqual(event10, .attached(generation: 1, joinedInProgress: false))
        capture.noteSpeakingEdge(true)
        try? await Task.sleep(nanoseconds: 50_000_000)                            // the drain task stamps it at writeCursor 0
        write(writer, [Float](repeating: 0.5, count: 8_000))                      // ReVox's voice, re-captured
        try? await Task.sleep(nanoseconds: 100_000_000)
        capture.noteSpeakingEdge(false)                                           // player finished at writeCursor 8 000
        try? await Task.sleep(nanoseconds: 50_000_000)                            // the drain task stamps the false edge
        write(writer, [Float](repeating: 0.5, count: 3_072))                      // the tail still in flight
        write(writer, [Float](repeating: 0, count: 40_960))                       // silence past the 2 s window
        var iterator = frames.makeAsyncIterator()
        var consumed = 0
        while consumed < 52_032, let chunk = await withTimeout(seconds: 3, { await iterator.next() }) {
            consumed += chunk.samples.count
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let measurement = try XCTUnwrap(capture.lastSelfCaptureMeasurement)
        XCTAssertEqual(measurement.edgePosition, 8_000)
        XCTAssertEqual(Double(measurement.tailFrames), 3_072, accuracy: 512, "the voice tail after the false edge, in ring frames")
        XCTAssertEqual(measurement.peakWhileSpeaking, 0.5)
        await capture.stop()
    }

    /// §4.3: the player's `SpeakingCallback` may fire on an audio-completion thread, so `noteSpeakingEdge` must never
    /// wait on `lock` — which `poll` holds across `records?.write`, the frame `yield` and `feedProbe`. The injected
    /// clock is called inside that lock, so parking it there parks a poll inside the lock for the whole measurement.
    func testSpeakingEdgeDoesNotWaitForAPollHoldingTheLock() async throws {
        let release = DispatchSemaphore(value: 0)
        let park = LockedBox<Bool>(false)
        let inside = LockedBox<Bool>(false)
        let clock = now!
        let parked = BroadcastCapture(appGroup: suite, containerURL: container, records: records, clock: {
            if park.value {
                park.mutate { $0 = false }                 // park exactly one poll, inside `lock`
                inside.mutate { $0 = true }
                release.wait()
            }
            return clock.value
        }, pollInterval: 20_000_000)
        try await parked.start(.broadcast)                 // the 20 ms poll task starts calling the clock
        park.mutate { $0 = true }
        for _ in 0 ..< 300 where !inside.value {           // await, never block this thread: the poll needs one
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(inside.value, "a poll is parked inside the lock")
        let began = Date()
        parked.noteSpeakingEdge(true)                      // yields into the edge stream; must not touch `lock`
        parked.noteSpeakingEdge(false)
        let elapsed = Date().timeIntervalSince(began)
        release.signal()                                   // let the parked poll finish before any assertion fails
        XCTAssertLessThan(elapsed, 0.5, "noteSpeakingEdge blocked on the poll lock")
        await parked.stop()
    }

    // MARK: docs/security-review-m5.md

    /// Finding 2, end to end: the sanitising lives in `RingReader.read`, so this proves the composition — nothing
    /// non-finite reaches the pipeline, and therefore nothing can wedge the VAD's LSTM state for the rest of the run.
    func testNonFiniteRingSamplesNeverReachThePipeline() async throws {
        let writer = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        let frames = capture.frames()
        try await capture.start(.broadcast)
        let attached = await nextEvent(&events)
        XCTAssertEqual(attached, .attached(generation: 1, joinedInProgress: false))
        var poisoned = [Float](repeating: 0.25, count: 512)
        poisoned[7] = .nan
        poisoned[300] = .infinity
        poisoned[301] = -.infinity
        write(writer, poisoned)
        var iterator = frames.makeAsyncIterator()
        let next = await withTimeout(seconds: 3) { await iterator.next() }
        let chunk = try XCTUnwrap(next)
        XCTAssertTrue(chunk.samples.allSatisfy { $0.isFinite })
        XCTAssertEqual(chunk.samples[7], 0)
        XCTAssertEqual(chunk.samples[300], 0)
        XCTAssertEqual(chunk.samples[301], 0)
        XCTAssertEqual(chunk.samples[8], 0.25)
        await capture.stop()
    }

    /// Finding 6: the six Darwin names derive from the App Group id, which ships in the Info.plist, and Darwin
    /// notifications are unauthenticated — any app on the device can post them in a loop. Each wake costs a plist
    /// decode and a poll under `lock`, so the wake path is rate-limited while timer ticks are not.
    func testAWakeFloodIsCoalescedButTimerTicksAreNot() async throws {
        _ = try startExtension(generation: 1)
        var events = capture.events.makeAsyncIterator()
        _ = capture.frames()
        try await capture.start(.broadcast)
        let attached = await nextEvent(&events)
        XCTAssertEqual(attached, .attached(generation: 1, joinedInProgress: false))
        let before = capture.pollCount
        for _ in 0 ..< 1_000 {
            capture.poll(wake: names.audio)                       // a hostile flood, synchronously
        }
        let afterFlood = capture.pollCount
        XCTAssertLessThanOrEqual(afterFlood - before, 2, "1 000 wakes inside one clock tick collapse to at most one poll, plus at most one timer tick")
        capture.poll(wake: nil)
        capture.poll(wake: nil)
        XCTAssertGreaterThanOrEqual(capture.pollCount - afterFlood, 2, "the 100 ms timer is never coalesced: it is how a missed notification is recovered")
        XCTAssertEqual(BroadcastCapture.minimumWakeSpacingSeconds, 0.01)
        await capture.stop()
    }
}
