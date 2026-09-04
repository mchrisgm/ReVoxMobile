import Foundation
import ReVoxCore

/// The six extension → app Darwin posts, built once per broadcast (§7.3, §7.4). Plain closures: no allocation per call.
struct BroadcastNotifiers {
    let started: () -> Void
    let paused: () -> Void
    let resumed: () -> Void
    let stopped: () -> Void
    let formatChanged: () -> Void
    let audio: () -> Void

    static func darwin(names: BroadcastNotificationNames) -> BroadcastNotifiers {
        let started = DarwinNotificationPoster(name: names.started)
        let paused = DarwinNotificationPoster(name: names.paused)
        let resumed = DarwinNotificationPoster(name: names.resumed)
        let stopped = DarwinNotificationPoster(name: names.stopped)
        let formatChanged = DarwinNotificationPoster(name: names.formatChanged)
        let audio = DarwinNotificationPoster(name: names.audio)
        return BroadcastNotifiers(started: { started.post() }, paused: { paused.post() }, resumed: { resumed.post() },
                                  stopped: { stopped.post() }, formatChanged: { formatChanged.post() }, audio: { audio.post() })
    }

    static func recording(_ log: @escaping (String) -> Void) -> BroadcastNotifiers {
        BroadcastNotifiers(started: { log("started") }, paused: { log("paused") }, resumed: { log("resumed") },
                           stopped: { log("stopped") }, formatChanged: { log("formatChanged") }, audio: { log("audio") })
    }
}

/// One broadcast's life on the writer side (§7.1, §7.4): the header through `RingWriter`, the `"broadcast.state"`
/// record written only at transitions, the Darwin posts, and the `.audio` cadence of one post per 1 600 frames.
/// Not Sendable: owned by the ReplayKit callback thread.
final class BroadcastSession {
    static let audioPostEveryFrames = 1_600

    private let writer: RingWriter
    private let records: BroadcastRecordStore?
    private let notifiers: BroadcastNotifiers
    private let clock: () -> Double
    private(set) var record: BroadcastStateRecord
    private var framesSinceAudioPost = 0
    private(set) var audioPostCount = 0
    private(set) var writtenFrames: UInt64 = 0

    var generation: UInt64 { record.generation }

    init(writer: RingWriter, records: BroadcastRecordStore?, notifiers: BroadcastNotifiers, previousGeneration: UInt64, pid: Int32,
         clock: @escaping () -> Double) {
        self.writer = writer
        self.records = records
        self.notifiers = notifiers
        self.clock = clock
        let now = clock()
        let started = previousGeneration + 1
        writer.begin(generation: started, startedAt: now, asbd: RingHeader.ASBD(), pid: UInt32(bitPattern: pid))
        record = BroadcastStateRecord(generation: started, state: .running, startedAt: now, writerPID: pid)
        records?.write(record)
        notifiers.started()
    }

    func annotated(bundleID: String?) {
        record.annotatedBundleID = bundleID
        records?.write(record)
    }

    func formatChanged(_ asbd: RingHeader.ASBD) {
        writer.noteFormatChange(asbd, at: clock())
        record.sourceASBD = SourceFormatRecord(asbd)
        record.asbdChangeCount += 1
        records?.write(record)
        notifiers.formatChanged()
    }

    /// Data, then cursor (release), then heartbeat inside `RingWriter.write`; then the ≤ 10/s wake-up.
    func write(_ frames: UnsafeBufferPointer<Float>, pts: RingHeader.PTS) {
        guard frames.count > 0 else { return }
        _ = writer.write(frames, at: clock(), pts: pts)
        writtenFrames += UInt64(frames.count)
        framesSinceAudioPost += frames.count
        if framesSinceAudioPost >= Self.audioPostEveryFrames {
            framesSinceAudioPost = 0
            audioPostCount += 1
            notifiers.audio()
        }
    }

    func droppedInput(frames: Int) {
        writer.noteDroppedInput(frames: frames)
    }

    /// `.audioMic` buffers are ignored and counted (§11); the record notes the Control Center mic toggle once.
    func micBuffer() {
        writer.noteMicBuffer()
        if !record.micToggleSeen {
            record.micToggleSeen = true
            records?.write(record)
        }
    }

    func paused() {
        writer.setState(.paused, at: clock())
        record.state = .paused
        records?.write(record)
        notifiers.paused()
    }

    func resumed() {
        writer.setState(.running, at: clock())
        record.state = .running
        records?.write(record)
        notifiers.resumed()
    }

    /// Ends the broadcast. `annotatedBundleID` is cleared here and in `failed()`: it names the third-party app whose
    /// content the user was consuming — the most disclosing value in the whole bridge — and unlike the ring file the
    /// App Group's plist is not excluded from backup, so a value left behind is copied into every iCloud backup and
    /// stays until the next broadcast, which may never come. It is only useful while one is live, which is exactly
    /// when the Diagnostics screen is worth looking at (docs/security-review-m5.md finding 5).
    func finished() {
        let now = clock()
        writer.setState(.finished, at: now)
        record.state = .finished
        record.finishedAt = now
        record.annotatedBundleID = nil          // §11, see the note on `finished()`
        records?.write(record)
        notifiers.stopped()
    }

    /// Only for the extension's own failures (§7.1 step 6); `reason` is the user-readable text iOS also shows.
    func failed(reason: String) {
        let now = clock()
        writer.setState(.failed, at: now)
        record.state = .failed
        record.finishedAt = now
        record.finishReason = reason
        record.annotatedBundleID = nil          // §11, see the note on `finished()`
        records?.write(record)
        notifiers.stopped()
    }
}
