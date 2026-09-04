import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class BroadcastStateRecordTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "ReVoxRecords-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNotificationNamesDeriveFromTheAppGroup() {
        let names = BroadcastNotificationNames(appGroup: "group.example.revox")
        XCTAssertEqual(names.started, "group.example.revox.broadcast.started")
        XCTAssertEqual(names.paused, "group.example.revox.broadcast.paused")
        XCTAssertEqual(names.resumed, "group.example.revox.broadcast.resumed")
        XCTAssertEqual(names.stopped, "group.example.revox.broadcast.stopped")
        XCTAssertEqual(names.formatChanged, "group.example.revox.broadcast.formatChanged")
        XCTAssertEqual(names.audio, "group.example.revox.broadcast.audio")
        XCTAssertEqual(names.appAttached, "group.example.revox.app.attached")
        XCTAssertEqual(names.extensionToApp, [names.started, names.paused, names.resumed, names.stopped, names.formatChanged, names.audio])
    }

    func testBroadcastStateRoundTripsAsAPropertyListDictionary() throws {
        let store = BroadcastRecordStore(defaults: defaults)
        XCTAssertNil(store.readBroadcastState())
        var record = BroadcastStateRecord(generation: 3, state: .running, startedAt: 1_700_000_000.5, writerPID: 4_242)
        record.sourceASBD = SourceFormatRecord(RingHeader.ASBD(sampleRate: 44_100, formatID: 0x6C70_636D, formatFlags: 0xE, bytesPerPacket: 4,
                                                                framesPerPacket: 1, bytesPerFrame: 4, channelsPerFrame: 2, bitsPerChannel: 16))
        record.asbdChangeCount = 1
        record.annotatedBundleID = "com.example.player"
        store.write(record)

        let dictionary = try XCTUnwrap(defaults.dictionary(forKey: BroadcastStateRecord.key))
        XCTAssertEqual(dictionary["contractVersion"] as? Int, 1)
        XCTAssertEqual(dictionary["ringFile"] as? String, "audio-ring-v1.bin")
        XCTAssertEqual(dictionary["state"] as? String, "running")
        XCTAssertEqual(dictionary["generation"] as? Int, 3)
        XCTAssertNil(dictionary["finishReason"], "nil fields are omitted")
        XCTAssertEqual((dictionary["sourceASBD"] as? [String: Any])?["channelsPerFrame"] as? Int, 2)
        XCTAssertEqual(store.readBroadcastState(), record)

        record.state = .failed
        record.finishedAt = 1_700_000_100
        record.finishReason = "ReVox could not open its shared audio buffer"
        store.write(record)
        XCTAssertEqual(store.readBroadcastState()?.state, .failed)
        XCTAssertEqual(store.readBroadcastState()?.finishReason, "ReVox could not open its shared audio buffer")
        XCTAssertEqual(store.readBroadcastState()?.sourceASBD?.asbd.sampleRate, 44_100)
    }

    func testCaptureReaderRecordRoundTrips() {
        let store = BroadcastRecordStore(defaults: defaults)
        XCTAssertNil(store.readCaptureReader())
        let record = CaptureReaderRecord(lastAttachedAt: 1_700_000_000, lastReadCursor: 0x0102_0304_0506, generation: 7)
        store.write(record)
        XCTAssertEqual(store.readCaptureReader(), record)
        XCTAssertEqual(defaults.dictionary(forKey: CaptureReaderRecord.key)?["generation"] as? Int, 7)
    }

    func testCorruptDictionaryReadsAsNil() {
        let store = BroadcastRecordStore(defaults: defaults)
        defaults.set(["state": 12, "generation": "x"], forKey: BroadcastStateRecord.key)
        XCTAssertNil(store.readBroadcastState())
    }

    /// `convenience init?(appGroup:)` returns nil exactly when `UserDefaults(suiteName:)` does: the app's own bundle
    /// identifier and the global domain are not suites. Both halves of the `?` are exercised here.
    func testStoreIsCreatedForAnAppGroupSuiteAndRefusedForTheOwnBundleID() throws {
        XCTAssertNotNil(BroadcastRecordStore(appGroup: suite))
        let ownBundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertNil(BroadcastRecordStore(appGroup: ownBundleID), "the app's own bundle id is not a valid suite")
    }
}
