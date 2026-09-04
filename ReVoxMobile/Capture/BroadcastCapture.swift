import Foundation
import os
import ReVoxCore

enum BroadcastCaptureEvent: Equatable, Sendable {
    case noRing
    case attached(generation: UInt64, joinedInProgress: Bool)
    case idle                                     // header state finished / paused / failed / idle
    case stale(lastWriteAt: Double)               // heartbeat older than 3 s while the header says running
    case gap(dropped: Int)                        // ring overrun: the reader jumped forward
    case silence(seconds: Double)                 // −60 dBFS for 10 s while attached
}

/// The broadcast-mode `AudioSource` (§6.2, R10). One mapping of the ring per run, one `RingReader` owned by the
/// poll path, wake-ups from the Darwin observer plus a 100 ms timer, frames yielded with absolute ring positions.
/// `@unchecked Sendable`: every stored property is guarded by `lock`; `poll` is the only reader of the ring.
final class BroadcastCapture: AudioSource, @unchecked Sendable {
    static let pollIntervalNanoseconds: UInt64 = 100_000_000
    static let scratchFrames = 16_000
    private static let readerRecordIntervalSeconds: Double = 1
    private static let logger = Logger(subsystem: "revox", category: "capture")

    let events: AsyncStream<BroadcastCaptureEvent>
    private let eventContinuation: AsyncStream<BroadcastCaptureEvent>.Continuation
    private let appGroup: String
    private let names: BroadcastNotificationNames
    private let containerURL: URL?
    private let records: BroadcastRecordStore?
    private let clock: @Sendable () -> Double
    private let pollInterval: UInt64
    private let attachedPoster: DarwinNotificationPoster
    private let lock = NSLock()

    // Guarded by `lock`.
    private var mapping: RingFileMapping?
    private var storage: MappedRingStorage?
    private var reader: RingReader?
    private var state: AttachState = .noRing
    private var attachedGeneration: UInt64?
    private var running = false
    private var joined = false
    private var lastEmitted: BroadcastCaptureEvent?
    private var frameContinuation: AsyncStream<CapturedAudio>.Continuation?
    private var gapHandler: (@Sendable (Int) async -> Void)?
    private var silence = SilenceDetector()
    private var scratch = [Float](repeating: 0, count: BroadcastCapture.scratchFrames)
    private var lastKnownWriteCursor: UInt64 = 0
    private var lastReaderRecordAt: Double?
    private var pollTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var observer: DarwinNotificationObserver?

    init(appGroup: String, containerURL: URL?, records: BroadcastRecordStore?,
         clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
         pollInterval: UInt64 = BroadcastCapture.pollIntervalNanoseconds) {
        let names = BroadcastNotificationNames(appGroup: appGroup)
        self.appGroup = appGroup
        self.names = names
        self.containerURL = containerURL
        self.records = records
        self.clock = clock
        self.pollInterval = pollInterval
        self.attachedPoster = DarwinNotificationPoster(name: names.appAttached)
        let (stream, continuation) = AsyncStream<BroadcastCaptureEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        pollTask?.cancel()
        wakeTask?.cancel()
        observer?.stop()
        frameContinuation?.finish()
        eventContinuation.finish()
    }

    var attachState: AttachState { lock.lock(); defer { lock.unlock() }; return state }
    var joinedInProgress: Bool { lock.lock(); defer { lock.unlock() }; return joined }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// The pipeline's `noteCaptureGap()` (drop marker + `.lag`), wired by the assembler after the pipeline exists.
    func setGapHandler(_ handler: (@Sendable (Int) async -> Void)?) {
        lock.lock(); gapHandler = handler; lock.unlock()
    }

    // MARK: AudioSource

    func frames() -> AsyncStream<CapturedAudio> {
        lock.lock()
        defer { lock.unlock() }
        frameContinuation?.finish()
        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .unbounded)
        frameContinuation = continuation
        return stream
    }

    /// The ring `writeCursor` now (acquire load), or the last one seen while mapped (§5.2 "which cursor").
    func capturePosition() async -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        if let storage {
            lastKnownWriteCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)
        }
        return Int64(lastKnownWriteCursor)
    }

    func start(_ mode: CaptureMode) async throws {
        guard mode == .broadcast else { throw CaptureError.unsupportedMode(mode) }
        lock.lock()
        running = true
        joined = false
        state = .noRing
        attachedGeneration = nil
        lastEmitted = nil
        silence.reset()
        let observer = DarwinNotificationObserver(names: names.extensionToApp)
        self.observer = observer
        observer.start()
        let interval = pollInterval
        wakeTask = Task { [weak self] in
            for await name in observer.names {
                self?.poll(wake: name)
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll(wake: nil)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
        lock.unlock()
    }

    func stop() async {
        lock.lock()
        running = false
        pollTask?.cancel()
        pollTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        observer?.stop()
        observer = nil
        frameContinuation?.finish()
        frameContinuation = nil
        if let storage {
            lastKnownWriteCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)
        }
        reader = nil
        storage = nil
        mapping = nil                                     // munmap in deinit
        state = .noRing
        attachedGeneration = nil
        lock.unlock()
    }

    // MARK: One wake or tick (§6.2 "Reading")

    func poll(wake: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        let now = clock()
        if let wake, wake != names.audio {
            // Measurement row 12: is the cross-process record fresh right after a Darwin wake?
            let recordState = records?.readBroadcastState()?.state.rawValue ?? "none"
            Self.logger.info("wake=\(wake.split(separator: ".").last.map(String.init) ?? wake, privacy: .public) record.state=\(recordState, privacy: .public)")
        }
        guard ensureMapped() else {
            emit(.noRing)
            state = .noRing
            return
        }
        guard let reader, let storage else { return }
        if case .attachedLive(let generation) = state {
            let header = reader.header
            if header.generation != generation {
                state = .idle                              // a new broadcast started: re-attach on this tick
                attachedGeneration = nil
            } else {
                readAttached(reader: reader, storage: storage, header: header, now: now)
                return
            }
        }
        attach(reader: reader, now: now)
    }

    /// Maps the file and creates the reader; false while the file is absent, short or its header not yet written.
    private func ensureMapped() -> Bool {
        if storage == nil {
            guard let containerURL, let mapping = try? RingFileMapping.openExisting(at: RingFileMapping.ringURL(in: containerURL)) else {
                return false
            }
            self.mapping = mapping
            storage = MappedRingStorage(mapping: mapping)
        }
        if reader == nil, let storage {
            reader = try? RingReader(storage: storage)         // .badMagic until the extension wrote the header
        }
        return reader != nil
    }

    private func attach(reader: RingReader, now: Double) {
        let headerBefore = reader.header
        let stored = records?.readCaptureReader()
        let result = reader.attach(now: now, storedReadCursor: stored?.lastReadCursor, storedGeneration: stored?.generation)
        state = result
        switch result {
        case .attachedLive(let generation):
            attachedGeneration = generation
            joined = headerBefore.writeCursor > UInt64(RingReader.defaultCatchUpFrames)
            silence.reset()
            writeReaderRecord(reader: reader, generation: generation, now: now, force: true)
            attachedPoster.post()
            Self.logger.info("attached generation=\(generation, privacy: .public) readCursor=\(reader.readCursor, privacy: .public) joined=\(self.joined, privacy: .public)")
            emit(.attached(generation: generation, joinedInProgress: joined))
        case .stale(let lastWriteAt):
            markLost(now: now)
            emit(.stale(lastWriteAt: lastWriteAt))
        case .idle:
            emit(.idle)
        case .noRing:
            emit(.noRing)
        }
    }

    private func readAttached(reader: RingReader, storage: MappedRingStorage, header: RingHeader, now: Double) {
        lastKnownWriteCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)
        let result = scratch.withUnsafeMutableBufferPointer { reader.read(into: $0) }
        switch result {
        case .frames(let count):
            let position = Int64(reader.readCursor)
            frameContinuation?.yield(CapturedAudio(samples: Array(scratch[0 ..< count]), endPosition: position))
            writeReaderRecord(reader: reader, generation: header.generation, now: now, force: false)
        case .gap(let dropped):
            writeReaderRecord(reader: reader, generation: header.generation, now: now, force: true)
            emit(.gap(dropped: dropped))
            if let gapHandler {
                Task { await gapHandler(dropped) }
            }
        case .idle:
            if header.state != .running {
                state = .idle
                attachedGeneration = nil
                emit(.idle)
                return
            }
            if now - header.lastWriteAt > RingReader.staleAfterSeconds {
                state = .stale(lastWriteAt: header.lastWriteAt)
                attachedGeneration = nil
                markLost(now: now)
                emit(.stale(lastWriteAt: header.lastWriteAt))
                return
            }
        }
        if silence.observe(rms: header.rmsLevel1s, now: now) {
            emit(.silence(seconds: SilenceDetector.requiredSeconds))
        }
    }

    private func writeReaderRecord(reader: RingReader, generation: UInt64, now: Double, force: Bool) {
        guard force || lastReaderRecordAt == nil || now - (lastReaderRecordAt ?? 0) >= Self.readerRecordIntervalSeconds else { return }
        lastReaderRecordAt = now
        records?.write(CaptureReaderRecord(lastAttachedAt: now, lastReadCursor: reader.readCursor, generation: generation))
    }

    /// §9 "Broadcast heartbeat stale (extension killed)": stop reading; record `lost`.
    private func markLost(now: Double) {
        guard let records, var record = records.readBroadcastState(), record.state != .lost else { return }
        record.state = .lost
        record.finishedAt = now
        records.write(record)
    }

    /// State-like events are emitted on change only; `.gap` and `.silence` every time.
    private func emit(_ event: BroadcastCaptureEvent) {
        switch event {
        case .gap, .silence:
            eventContinuation.yield(event)
        default:
            guard event != lastEmitted else { return }
            lastEmitted = event
            eventContinuation.yield(event)
        }
    }
}
