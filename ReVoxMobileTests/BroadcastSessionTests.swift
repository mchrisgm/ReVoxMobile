import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class BroadcastSessionTests: XCTestCase {
    private var storage: HeapRingStorage!
    private var writer: RingWriter!
    private var defaults: UserDefaults!
    private var records: BroadcastRecordStore!
    private var suite: String!
    private var posted: [String] = []
    private var now: Double = 1_000

    override func setUpWithError() throws {
        storage = HeapRingStorage(layout: .v1)
        writer = try RingWriter(storage: storage)
        suite = "ReVoxSession-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        records = BroadcastRecordStore(defaults: defaults)
        posted = []
        now = 1_000
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeSession(previousGeneration: UInt64 = 4) -> BroadcastSession {
        BroadcastSession(writer: writer, records: records, notifiers: .recording { [unowned self] in self.posted.append($0) },
                         previousGeneration: previousGeneration, pid: 321, clock: { [unowned self] in self.now })
    }

    func testStartBeginsTheRingWritesTheRecordAndPostsStarted() throws {
        let session = makeSession()
        XCTAssertEqual(session.generation, 5)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.generation, 5)
        XCTAssertEqual(header.state, .running)
        XCTAssertEqual(header.startedAt, 1_000)
        XCTAssertEqual(header.writerPID, 321)
        let record = try XCTUnwrap(records.readBroadcastState())
        XCTAssertEqual(record, session.record)
        XCTAssertEqual(record.generation, 5)
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.startedAt, 1_000)
        XCTAssertEqual(record.writerPID, 321)
        XCTAssertEqual(record.contractVersion, 1)
        XCTAssertEqual(record.ringFile, "audio-ring-v1.bin")
        XCTAssertNil(record.sourceASBD)
        XCTAssertEqual(posted, ["started"])
    }

    func testAudioNotificationEveryHundredMilliseconds() {
        let session = makeSession()
        let block = [Float](repeating: 0.1, count: 400)
        for _ in 0 ..< 3 {                                   // 1 200 frames: below the cadence
            block.withUnsafeBufferPointer { session.write($0, pts: RingHeader.PTS()) }
        }
        XCTAssertEqual(session.audioPostCount, 0)
        block.withUnsafeBufferPointer { session.write($0, pts: RingHeader.PTS(value: 4_096, timescale: 44_100, flags: 1)) }   // 1 600
        XCTAssertEqual(session.audioPostCount, 1)
        XCTAssertEqual(posted, ["started", "audio"])
        for _ in 0 ..< 16 {                                  // 6 400 more frames → 4 more posts
            block.withUnsafeBufferPointer { session.write($0, pts: RingHeader.PTS()) }
        }
        XCTAssertEqual(session.audioPostCount, 5)
        XCTAssertEqual(session.writtenFrames, 8_000)
        XCTAssertEqual(writer.writeCursor, 8_000)
        XCTAssertEqual(RingHeader.read(from: storage)?.lastPTS, RingHeader.PTS(), "the last write's PTS")
        XCTAssertEqual(records.readBroadcastState()?.state, .running, "audio never rewrites the record")
    }

    func testFormatChangeUpdatesHeaderRecordAndPostsOnce() throws {
        let session = makeSession()
        let asbd = RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, formatFlags: 0xE, bytesPerPacket: 4, framesPerPacket: 1,
                                   bytesPerFrame: 4, channelsPerFrame: 2, bitsPerChannel: 16)
        now = 1_001
        session.formatChanged(asbd)
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.sourceASBD, asbd)
        XCTAssertEqual(header.asbdChangeCount, 1)
        XCTAssertEqual(header.lastAsbdChangeAt, 1_001)
        let record = try XCTUnwrap(records.readBroadcastState())
        XCTAssertEqual(record.sourceASBD, SourceFormatRecord(asbd))
        XCTAssertEqual(record.asbdChangeCount, 1)
        XCTAssertEqual(posted, ["started", "formatChanged"])
        session.formatChanged(RingHeader.ASBD(sampleRate: 48_000, formatID: 0x6C70_636D, channelsPerFrame: 1, bitsPerChannel: 16))
        XCTAssertEqual(records.readBroadcastState()?.asbdChangeCount, 2)
        XCTAssertEqual(posted.filter { $0 == "formatChanged" }.count, 2)
    }

    func testAnnotationDroppedInputAndMicBuffers() throws {
        let session = makeSession()
        session.annotated(bundleID: "com.example.player")
        XCTAssertEqual(records.readBroadcastState()?.annotatedBundleID, "com.example.player")
        session.droppedInput(frames: 1_024)
        session.droppedInput(frames: 1)
        XCTAssertEqual(RingHeader.read(from: storage)?.droppedInputFrames, 1_025)
        let before = posted.count
        session.micBuffer()
        session.micBuffer()
        session.micBuffer()
        XCTAssertEqual(RingHeader.read(from: storage)?.micBuffersSeen, 3)
        XCTAssertTrue(try XCTUnwrap(records.readBroadcastState()).micToggleSeen)
        XCTAssertEqual(posted.count, before, "diagnostics never post")
        defaults.removeObject(forKey: BroadcastStateRecord.key)
        session.micBuffer()
        XCTAssertNil(records.readBroadcastState(), "the record is written on the first mic buffer only")
    }

    func testPauseResumeFinishTransitions() throws {
        let session = makeSession()
        now = 1_010
        session.paused()
        XCTAssertEqual(RingHeader.read(from: storage)?.state, .paused)
        XCTAssertEqual(RingHeader.read(from: storage)?.lastWriteAt, 1_010)
        XCTAssertEqual(records.readBroadcastState()?.state, .paused)
        now = 1_020
        session.resumed()
        XCTAssertEqual(RingHeader.read(from: storage)?.state, .running)
        XCTAssertEqual(records.readBroadcastState()?.state, .running)
        now = 1_030
        session.finished()
        let header = try XCTUnwrap(RingHeader.read(from: storage))
        XCTAssertEqual(header.state, .finished)
        XCTAssertEqual(header.writeCursor, 0, "cursors are never touched by transitions")
        let record = try XCTUnwrap(records.readBroadcastState())
        XCTAssertEqual(record.state, .finished)
        XCTAssertEqual(record.finishedAt, 1_030)
        XCTAssertNil(record.finishReason, "no reason for a normal end (§6.2)")
        XCTAssertEqual(posted, ["started", "paused", "resumed", "stopped"])
    }

    func testFailedRecordsTheReasonAndPostsStopped() throws {
        let session = makeSession()
        now = 1_005
        session.failed(reason: "ReVox could not read the audio format")
        XCTAssertEqual(RingHeader.read(from: storage)?.state, .failed)
        let record = try XCTUnwrap(records.readBroadcastState())
        XCTAssertEqual(record.state, .failed)
        XCTAssertEqual(record.finishedAt, 1_005)
        XCTAssertEqual(record.finishReason, "ReVox could not read the audio format")
        XCTAssertEqual(posted, ["started", "stopped"])
    }

    func testDarwinNotifiersAreBuiltFromTheNames() {
        let notifiers = BroadcastNotifiers.darwin(names: BroadcastNotificationNames(appGroup: "group.test.revox-\(UUID().uuidString)"))
        notifiers.audio()        // posting to a name nobody observes is a no-op that must not trap
        notifiers.started()
        notifiers.stopped()
    }
}
