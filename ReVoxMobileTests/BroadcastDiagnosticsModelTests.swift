import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class BroadcastDiagnosticsModelTests: XCTestCase {
    private var container: URL!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxDiag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: container)
    }

    private func makeModel(now: LockedBox<Double>) -> BroadcastDiagnosticsModel {
        BroadcastDiagnosticsModel(containerURL: container, records: BroadcastRecordStore(defaults: UserDefaults(suiteName: "ReVoxDiag-\(UUID().uuidString)")!),
                                  keepAlive: KeepAliveMonitor(clock: { now.value }), sessionController: AudioSessionController(session: RecordingAudioSessionSeam()),
                                  clock: { now.value })
    }

    func testSnapshotHelpers() {
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.decibels(1), 0, accuracy: 0.001)
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.decibels(0.001), -60, accuracy: 0.001)
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.decibels(0), -120, accuracy: 0.001)
        let bigEndian = RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, formatFlags: 0x0000_000E, bytesPerPacket: 4, framesPerPacket: 1,
                                        bytesPerFrame: 4, channelsPerFrame: 2, bitsPerChannel: 16)
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.formatText(bigEndian), "44100 Hz · 2 ch · 16-bit int · big-endian")
        let floatMono = RingHeader.ASBD(sampleRate: 48_000, formatID: 0x6C70_636D, formatFlags: 0x0000_0029, bytesPerPacket: 4, framesPerPacket: 1,
                                        bytesPerFrame: 4, channelsPerFrame: 1, bitsPerChannel: 32)
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.formatText(floatMono), "48000 Hz · 1 ch · 32-bit float · little-endian")
        XCTAssertEqual(BroadcastDiagnosticsModel.Snapshot.formatText(RingHeader.ASBD()), "no format yet")
    }

    func testSnapshotFromHeaderComputesRateAndAges() {
        let header = RingHeader(magic: "RVXRING1", headerBytes: 4_096, capacityFrames: 960_000, sampleRate: 16_000, channels: 1, sampleFormat: 1,
                                generation: 3, writeCursor: 32_000, readCursor: 0, state: .running, asbdChangeCount: 1, lastWriteAt: 1_000,
                                startedAt: 998, lastPTS: RingHeader.PTS(), lastAsbdChangeAt: 998,
                                sourceASBD: RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, formatFlags: 0xE, bytesPerPacket: 4, framesPerPacket: 1,
                                                            bytesPerFrame: 4, channelsPerFrame: 2, bitsPerChannel: 16),
                                droppedInputFrames: 5, micBuffersSeen: 2, overrunCount: 1, peakLevel1s: 0.5, rmsLevel1s: 0.1, writerPID: 77)
        let first = BroadcastDiagnosticsModel.Snapshot.make(header: header, previous: nil, now: 1_000.5, elapsed: 0.25)
        XCTAssertEqual(first.generation, 3)
        XCTAssertEqual(first.state, .running)
        XCTAssertEqual(first.writeCursor, 32_000)
        XCTAssertEqual(first.writtenSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(first.heartbeatAge, 0.5, accuracy: 0.001)
        XCTAssertEqual(first.rmsDB, -20, accuracy: 0.01)
        XCTAssertEqual(first.peakDB, -6.02, accuracy: 0.01)
        XCTAssertEqual(first.framesPerSecond, 0, "no previous snapshot")
        XCTAssertEqual(first.writerPID, 77)
        XCTAssertEqual(first.droppedInputFrames, 5)
        XCTAssertEqual(first.micBuffersSeen, 2)
        XCTAssertEqual(first.overrunCount, 1)
        XCTAssertEqual(first.asbdChangeCount, 1)

        var later = header
        later.writeCursor = 36_000
        let second = BroadcastDiagnosticsModel.Snapshot.make(header: later, previous: first, now: 1_000.75, elapsed: 0.25)
        XCTAssertEqual(second.framesPerSecond, 16_000, accuracy: 0.001)
    }

    func testRefreshReadsTheRingAndTheRecord() async throws {
        let now = LockedBox<Double>(5_000)
        let model = makeModel(now: now)
        await model.refresh()
        XCTAssertFalse(model.ringPresent)
        XCTAssertNil(model.snapshot)

        let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: container))
        let writer = try RingWriter(storage: MappedRingStorage(mapping: mapping))
        writer.begin(generation: 2, startedAt: 4_999, asbd: RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, channelsPerFrame: 2, bitsPerChannel: 16), pid: 9)
        [Float](repeating: 0.25, count: 1_600).withUnsafeBufferPointer { _ = writer.write($0, at: 5_000, pts: RingHeader.PTS()) }
        await model.refresh()
        XCTAssertTrue(model.ringPresent)
        XCTAssertEqual(model.snapshot?.generation, 2)
        XCTAssertEqual(model.snapshot?.writeCursor, 1_600)
        XCTAssertEqual(model.snapshot?.state, .running)
        XCTAssertEqual(model.snapshot?.sourceFormat, "44100 Hz · 2 ch · 16-bit int · little-endian")
        XCTAssertNil(model.record, "no record was written by the writer side in this test")
        XCTAssertFalse(model.engineRunning)
        XCTAssertNil(model.lastHeartbeat)
    }

    func testHoldingSessionConfiguresBroadcastModeAndStartsTheEngine() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let model = BroadcastDiagnosticsModel(containerURL: container, records: nil, keepAlive: KeepAliveMonitor(), sessionController: controller)
        await model.setHoldingSession(true)
        XCTAssertTrue(model.isHoldingSession)
        XCTAssertEqual(seam.calls, ["makeEngine", "setCategory", "setActive(true)"])
        XCTAssertEqual(seam.masks.last, AudioSessionController.broadcastMask)
        XCTAssertTrue(seam.lastEngine?.isRunning ?? false)
        await model.refresh()
        XCTAssertTrue(model.engineRunning)
        await model.setHoldingSession(false)
        XCTAssertFalse(model.isHoldingSession)
        XCTAssertFalse(seam.lastEngine?.isRunning ?? true)
    }
}
