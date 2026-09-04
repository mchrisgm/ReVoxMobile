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
/// `@unchecked Sendable`: every stored property except the two below is guarded by `lock`; `poll` is the only
/// reader of the ring.
final class BroadcastCapture: AudioSource, @unchecked Sendable {
    static let pollIntervalNanoseconds: UInt64 = 100_000_000
    static let scratchFrames = 16_000
    static let minimumWakeSpacingSeconds: Double = 0.01
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
    // Not guarded by `lock`: `AsyncStream.Continuation.yield` is thread-safe and never waits, which is what lets
    // `noteSpeakingEdge` run on the player's audio-completion thread (§4.3). Both are set once, in `init`.
    private let speakingEdgeContinuation: AsyncStream<Bool>.Continuation
    private var speakingEdgeTask: Task<Void, Never>?

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
    private var probe = SelfCaptureProbe()
    private var lastMeasurement: SelfCaptureProbe.Measurement?
    private var lastWakePoll: Double?
    private(set) var pollCount = 0
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
        let (edges, edgeContinuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .unbounded)
        self.speakingEdgeContinuation = edgeContinuation
        // The single in-order drain of §4.3: one task for the capture's whole lifetime, so a fast true → false pair
        // can never be applied out of order. `self` is fully initialised here, so the capture may be used.
        speakingEdgeTask = Task { [weak self] in
            for await speaking in edges {
                self?.applySpeakingEdge(speaking)
            }
        }
    }

    deinit {
        pollTask?.cancel()
        wakeTask?.cancel()
        observer?.stop()
        speakingEdgeTask?.cancel()
        speakingEdgeContinuation.finish()
        frameContinuation?.finish()
        eventContinuation.finish()
    }

    var attachState: AttachState { lock.lock(); defer { lock.unlock() }; return state }
    var joinedInProgress: Bool { lock.lock(); defer { lock.unlock() }; return joined }
    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    var lastSelfCaptureMeasurement: SelfCaptureProbe.Measurement? { lock.lock(); defer { lock.unlock() }; return lastMeasurement }

    /// A player speaking edge. Called from the player's synchronous `SpeakingCallback`, which may be an audio
    /// completion thread, so this takes no lock and does no work: it only yields into the unbounded edge stream
    /// (§4.3 "never touch actors synchronously"). It can therefore never wait on a `poll` that is holding `lock`
    /// across `records?.write`, the frame `yield` and `feedProbe`.
    func noteSpeakingEdge(_ speaking: Bool) {
        speakingEdgeContinuation.yield(speaking)
    }

    /// The drain side of `noteSpeakingEdge`, on the task started in `init`: stamps the edge with the ring
    /// `writeCursor` now (§5.2 "which cursor") and feeds the M5 probe. Off the audio thread, so `lock` is safe here.
    private func applySpeakingEdge(_ speaking: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if let storage {
            lastKnownWriteCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)
        }
        probe.speakingChanged(speaking, atPosition: Int64(clamping: lastKnownWriteCursor))
    }

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
        return Int64(clamping: lastKnownWriteCursor)
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
        probe = SelfCaptureProbe()                     // a fresh run measures its own phrases only
        lastMeasurement = nil
        lastWakePoll = nil
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
        // The six Darwin names derive from the App Group id, which ships in the Info.plist, and Darwin notifications
        // are system-wide and unauthenticated: any app on the device can post them. Each wake costs a plist decode
        // and a poll under `lock`, so a flood is a battery and responsiveness attack from outside our sandbox.
        // Timer ticks are never coalesced — only wakes, which the bridge doc already calls hints rather than facts
        // (docs/security-review-m5.md finding 6).
        if wake != nil {
            if let last = lastWakePoll, now - last < Self.minimumWakeSpacingSeconds, now >= last { return }
            lastWakePoll = now
        }
        pollCount += 1
        if let wake, wake != names.audio {
            // Measurement row 12: is the cross-process record fresh right after a Darwin wake? `.debug` because a
            // foreign poster would otherwise fill the unified log through it; raise it while filling row 12.
            let recordState = records?.readBroadcastState()?.state.rawValue ?? "none"
            Self.logger.debug("wake=\(wake.split(separator: ".").last.map(String.init) ?? wake, privacy: .public) record.state=\(recordState, privacy: .public)")
        }
        guard ensureMapped() else {
            emit(.noRing)
            state = .noRing
            return
        }
        guard let reader, let storage else { return }
        if case .attachedLive(let generation) = state {
            guard let header = reader.header else {          // the magic stopped being ours: treat it as no ring
                state = .noRing
                attachedGeneration = nil
                emit(.noRing)
                return
            }
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
        guard let headerBefore = reader.header else {
            state = .noRing
            emit(.noRing)
            return
        }
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
            feedProbe(count: count, endPosition: position)
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
            if !header.isHeartbeatFresh(now: now) {
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

    /// One RMS/peak per 512-frame chunk of the frames just read, in ring positions (M5 measurement rows 6 and 7).
    private func feedProbe(count: Int, endPosition: Int64) {
        let chunk = Segmenter.chunkSamples
        var offset = 0
        while offset + chunk <= count {
            var sumSquares: Float = 0
            var peak: Float = 0
            for index in offset ..< offset + chunk {
                let value = scratch[index]
                sumSquares += value * value
                peak = max(peak, abs(value))
            }
            let chunkEnd = endPosition - Int64(count - offset - chunk)
            if let measurement = probe.observe(chunkEndingAt: chunkEnd, rms: (sumSquares / Float(chunk)).squareRoot(), peak: peak) {
                lastMeasurement = measurement
                Self.logger.info("selfcapture edge=\(measurement.edgePosition, privacy: .public) lastVoiceEnd=\(measurement.lastVoiceEnd, privacy: .public) tailFrames=\(measurement.tailFrames, privacy: .public) peakWhileSpeaking=\(measurement.peakWhileSpeaking, privacy: .public) peakAfterEdge=\(measurement.peakAfterEdge, privacy: .public)")
            }
            offset += chunk
        }
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
