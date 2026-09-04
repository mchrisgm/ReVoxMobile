import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class BroadcastCoordinatorTests: XCTestCase {
    private var container: URL!
    private var suite: String!
    private var records: BroadcastRecordStore!
    private var now: LockedBox<Double>!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxCoord-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        suite = "group.test.revox-\(UUID().uuidString)"
        records = BroadcastRecordStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        now = LockedBox<Double>(2_000)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    private func makeCoordinator() -> BroadcastCoordinator {
        let clock = now!
        let capture = BroadcastCapture(appGroup: suite, containerURL: container, records: records, clock: { clock.value }, pollInterval: 20_000_000)
        return BroadcastCoordinator(capture: capture, records: records, containerURL: container, names: BroadcastNotificationNames(appGroup: suite), clock: { clock.value })
    }

    private func header(state: RingHeader.State, generation: UInt64 = 1, lastWriteAt: Double) -> RingHeader {
        RingHeader(magic: "RVXRING1", headerBytes: 4_096, capacityFrames: 960_000, sampleRate: 16_000, channels: 1, sampleFormat: 1,
                   generation: generation, writeCursor: 0, readCursor: 0, state: state, asbdChangeCount: 0, lastWriteAt: lastWriteAt,
                   startedAt: lastWriteAt, lastPTS: RingHeader.PTS(), lastAsbdChangeAt: 0, sourceASBD: RingHeader.ASBD(),
                   droppedInputFrames: 0, micBuffersSeen: 0, overrunCount: 0, peakLevel1s: 0, rmsLevel1s: 0, writerPID: 1)
    }

    func testEvaluateFollowsTheAttachTable() {
        let running = BroadcastStateRecord(generation: 1, state: .running, startedAt: 1_000, writerPID: 1)
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: nil, header: nil, now: 1_000), .noRing)
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: running, header: nil, now: 1_000), .noRing, "a record without a ring is nothing to attach to")
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: running, header: header(state: .running, lastWriteAt: 999), now: 1_000), .attachedLive(generation: 1))
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: nil, header: header(state: .running, lastWriteAt: 999), now: 1_000), .attachedLive(generation: 1), "no record: trust the header")
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: running, header: header(state: .running, lastWriteAt: 996), now: 1_000), .stale(lastWriteAt: 996))
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: running, header: header(state: .finished, lastWriteAt: 999), now: 1_000), .idle)
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: running, header: header(state: .paused, lastWriteAt: 999), now: 1_000), .idle)
        var lost = running
        lost.state = .lost
        XCTAssertEqual(BroadcastCoordinator.evaluate(record: lost, header: header(state: .running, lastWriteAt: 999), now: 1_000), .attachedLive(generation: 1), "a fresh heartbeat overrides a stale record")
    }

    func testCaptureEventsBecomeStatusTextsAndEvents() async throws {
        let coordinator = makeCoordinator()
        var events = coordinator.events.makeAsyncIterator()
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.startPromptText)
        XCTAssertTrue(coordinator.needsBroadcast)

        coordinator.handle(.attached(generation: 4, joinedInProgress: true))
        XCTAssertEqual(coordinator.attachState, .attachedLive(generation: 4))
        XCTAssertTrue(coordinator.isAttached)
        XCTAssertFalse(coordinator.needsBroadcast)
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.joinedText)
        XCTAssertEqual(await events.next(), .attached(joinedInProgress: true))

        coordinator.handle(.silence(seconds: 10))
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.silentText)
        XCTAssertEqual(await events.next(), .silent)

        coordinator.handle(.idle)
        XCTAssertEqual(coordinator.attachState, .idle)
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.endedText)
        XCTAssertEqual(await events.next(), .ended(reason: nil))
        XCTAssertTrue(coordinator.needsBroadcast)

        var failed = BroadcastStateRecord(generation: 4, state: .failed, startedAt: 1_000, writerPID: 1)
        failed.finishReason = "ReVox could not read the audio format"
        records.write(failed)
        coordinator.handle(.attached(generation: 5, joinedInProgress: false))
        XCTAssertNil(coordinator.statusText, "attached and not joined: the status line has nothing to say")
        _ = await events.next()
        coordinator.handle(.idle)
        XCTAssertEqual(coordinator.statusText, "Broadcast failed: ReVox could not read the audio format")
        XCTAssertEqual(await events.next(), .ended(reason: "ReVox could not read the audio format"))

        coordinator.handle(.stale(lastWriteAt: 990))
        XCTAssertEqual(coordinator.attachState, .stale(lastWriteAt: 990))
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.staleText)
        XCTAssertEqual(await events.next(), .stale)

        coordinator.handle(.noRing)
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.startPromptText)
        coordinator.handle(.gap(dropped: 100))
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.startPromptText, "gaps are the pipeline's business")
    }

    func testProbeFindsALiveBroadcastAndAsksForAStart() async throws {
        let coordinator = makeCoordinator()
        let starts = LockedBox<Int>(0)
        coordinator.onBroadcastLive = { starts.mutate { $0 += 1 } }
        await coordinator.probe()
        XCTAssertFalse(coordinator.isBroadcastLive)
        XCTAssertEqual(starts.value, 0)

        let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: container))
        let writer = try RingWriter(storage: MappedRingStorage(mapping: mapping))
        writer.begin(generation: 2, startedAt: now.value, asbd: RingHeader.ASBD(), pid: 1)
        records.write(BroadcastStateRecord(generation: 2, state: .running, startedAt: now.value, writerPID: 1))
        await coordinator.applicationDidBecomeActive()
        XCTAssertTrue(coordinator.isBroadcastLive)
        XCTAssertFalse(coordinator.needsBroadcast, "a live broadcast exists: no picker")
        XCTAssertEqual(starts.value, 1)

        coordinator.handle(.attached(generation: 2, joinedInProgress: false))
        await coordinator.probe()
        XCTAssertEqual(starts.value, 1, "already attached: no second start")

        writer.setState(.finished, at: now.value)
        coordinator.handle(.idle)
        await coordinator.probe()
        XCTAssertFalse(coordinator.isBroadcastLive)
        XCTAssertTrue(coordinator.needsBroadcast)
        XCTAssertEqual(starts.value, 1)
    }

    func testStartedAndStoppedWakesProbeWhileIdle() async throws {
        let coordinator = makeCoordinator()
        let starts = LockedBox<Int>(0)
        coordinator.onBroadcastLive = { starts.mutate { $0 += 1 } }
        coordinator.start()
        defer { coordinator.stop() }
        let names = BroadcastNotificationNames(appGroup: suite)

        let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: container))
        let writer = try RingWriter(storage: MappedRingStorage(mapping: mapping))
        writer.begin(generation: 1, startedAt: now.value, asbd: RingHeader.ASBD(), pid: 1)
        records.write(BroadcastStateRecord(generation: 1, state: .running, startedAt: now.value, writerPID: 1))
        DarwinNotificationPoster(name: names.started).post()
        await waitUntil("live after the started wake") { coordinator.isBroadcastLive }
        XCTAssertEqual(starts.value, 1)

        writer.setState(.finished, at: now.value)
        var record = try XCTUnwrap(records.readBroadcastState())
        record.state = .finished
        records.write(record)
        DarwinNotificationPoster(name: names.stopped).post()
        await waitUntil("not live after the stopped wake") { !coordinator.isBroadcastLive }
        XCTAssertEqual(coordinator.statusText, BroadcastCoordinator.startPromptText)
    }
}
