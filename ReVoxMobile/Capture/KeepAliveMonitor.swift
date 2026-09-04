import Foundation
import os

/// The keep-alive heartbeat of §6.8 (pass criterion 1) and the suspension detector of §9: every second the
/// capture position and the wall clock are appended to a log ring (and, when a `logURL` is given, to a text file
/// on disk — nothing shares or exports it, and nothing should: differenced at 1 Hz the file is a timestamped record
/// of when the user was translating and for how long); a gap of more than 3 s between two heartbeats means iOS suspended the
/// process, so the caller adds a transcript drop marker. `@unchecked Sendable`: every stored property is guarded
/// by `lock`; the tick task is the only writer while running.
final class KeepAliveMonitor: @unchecked Sendable {
    static let intervalNanoseconds: UInt64 = 1_000_000_000
    static let gapThresholdSeconds: Double = 3
    static let logRingCapacity = 3_600
    /// The file is truncated at `start()` and capped here, because `reset()` used to leave it growing forever:
    /// ~40 bytes per second of translating is ~3.4 MB a day of use (docs/security-review-m5.md finding 7).
    static let logByteCap = 512 * 1_024

    struct Heartbeat: Equatable, Sendable {
        let position: Int64
        let at: Double
    }

    enum Event: Equatable, Sendable {
        case heartbeat(Heartbeat)
        case gap(seconds: Double, before: Heartbeat, after: Heartbeat)
    }

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let clock: @Sendable () -> Double
    private let logURL: URL?
    private let interval: UInt64
    private let lock = NSLock()
    private var ring: [Heartbeat] = []
    private var gaps = 0
    private var tickTask: Task<Void, Never>?
    private var logHandle: FileHandle?
    private static let logger = Logger(subsystem: "revox", category: "keepalive")

    init(clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }, logURL: URL? = nil,
         interval: UInt64 = KeepAliveMonitor.intervalNanoseconds) {
        self.clock = clock
        self.logURL = logURL
        self.interval = interval
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        tickTask?.cancel()
        try? logHandle?.close()
        continuation.finish()
    }

    var heartbeats: [Heartbeat] { lock.lock(); defer { lock.unlock() }; return ring }
    var gapCount: Int { lock.lock(); defer { lock.unlock() }; return gaps }
    var lastHeartbeat: Heartbeat? { lock.lock(); defer { lock.unlock() }; return ring.last }

    /// One tick: compares with the previous heartbeat, appends to the ring and the file, yields the event.
    @discardableResult
    func record(position: Int64) -> Event {
        let beat = Heartbeat(position: position, at: clock())
        lock.lock()
        let previous = ring.last
        ring.append(beat)
        if ring.count > Self.logRingCapacity {
            ring.removeFirst(ring.count - Self.logRingCapacity)
        }
        var event = Event.heartbeat(beat)
        if let previous, beat.at - previous.at > Self.gapThresholdSeconds {
            gaps += 1
            event = .gap(seconds: beat.at - previous.at, before: previous, after: beat)
        }
        appendToLogLocked(beat: beat, event: event)
        lock.unlock()
        if case .gap(let seconds, _, _) = event {
            Self.logger.error("heartbeat gap \(seconds, privacy: .public) s: the app was suspended")
        }
        continuation.yield(event)
        return event
    }

    /// Ticks every `interval` until `stop()`; a gap calls `onGap` (the pipeline's drop marker) before the next tick.
    func start(position: @escaping @Sendable () async -> Int64, onGap: @escaping @Sendable (Double) async -> Void) {
        stop()
        let interval = self.interval
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let event = self.record(position: await position())
                if case .gap(let seconds, _, _) = event {
                    await onGap(seconds)
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
        lock.lock(); tickTask = task; lock.unlock()
    }

    func stop() {
        lock.lock()
        let task = tickTask
        tickTask = nil
        lock.unlock()
        task?.cancel()
    }

    /// Clears the ring, the counters and the log file (a new session starts a new log).
    func reset() {
        lock.lock()
        ring = []
        gaps = 0
        try? logHandle?.truncate(atOffset: 0)
        try? logHandle?.seek(toOffset: 0)
        lock.unlock()
    }

    private func appendToLogLocked(beat: Heartbeat, event: Event) {
        guard let logURL else { return }
        if logHandle == nil {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                // The same protection class as the ring file it describes, and out of iCloud backups: the folder
                // also holds the settings file, which the user *does* want backed up, so the exclusion goes on this
                // file rather than the directory (docs/security-review-m5.md finding 7).
                FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                var excluded = logURL
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? excluded.setResourceValues(values)
            }
            logHandle = try? FileHandle(forWritingTo: logURL)
            _ = try? logHandle?.seekToEnd()
        }
        if let offset = try? logHandle?.offset(), offset > UInt64(Self.logByteCap) {
            try? logHandle?.truncate(atOffset: 0)
            try? logHandle?.seek(toOffset: 0)
        }
        var line = String(format: "heartbeat position=%lld at=%.3f", beat.position, beat.at)
        if case .gap(let seconds, _, _) = event {
            line += String(format: " gap=%.3f", seconds)
        }
        line += "\n"
        // `write(contentsOf:)`, never `write(_:)`: the legacy overload raises NSFileHandleOperationException, which
        // Swift cannot catch, so a full disk — a realistic state right after a Whisper download — would terminate the
        // app on every heartbeat (docs/security-review-m5.md finding 7).
        try? logHandle?.write(contentsOf: Data(line.utf8))
    }
}
