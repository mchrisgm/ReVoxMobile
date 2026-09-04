import Foundation
import Observation
import ReVoxCore

/// The spike's instrument (§6.8, §10.4) and a permanent diagnostics page: polls the ring header four times a second
/// through its own read-only mapping, shows the `broadcast.state` record, the keep-alive heartbeats and gaps, and
/// can hold the broadcast-mode session and engine without a pipeline (the keep-alive test in broadcast mode).
@MainActor
@Observable
final class BroadcastDiagnosticsModel {
    struct Snapshot: Equatable, Sendable {
        var generation: UInt64
        var state: RingHeader.State
        var writeCursor: UInt64
        var writtenSeconds: Double
        var heartbeatAge: Double
        var rmsDB: Double
        var peakDB: Double
        var sourceFormat: String
        var asbdChangeCount: UInt32
        var droppedInputFrames: UInt64
        var micBuffersSeen: UInt64
        var overrunCount: UInt64
        var writerPID: UInt32
        var framesPerSecond: Double

        static func make(header: RingHeader, previous: Snapshot?, now: Double, elapsed: Double) -> Snapshot {
            var rate = 0.0
            if let previous, elapsed > 0, header.writeCursor >= previous.writeCursor {
                rate = Double(header.writeCursor - previous.writeCursor) / elapsed
            }
            return Snapshot(
                generation: header.generation,
                state: header.state,
                writeCursor: header.writeCursor,
                writtenSeconds: Double(header.writeCursor) / Double(max(header.sampleRate, 1)),
                heartbeatAge: now - header.lastWriteAt,
                rmsDB: decibels(header.rmsLevel1s),
                peakDB: decibels(header.peakLevel1s),
                sourceFormat: formatText(header.sourceASBD),
                asbdChangeCount: header.asbdChangeCount,
                droppedInputFrames: header.droppedInputFrames,
                micBuffersSeen: header.micBuffersSeen,
                overrunCount: header.overrunCount,
                writerPID: header.writerPID,
                framesPerSecond: rate
            )
        }

        static func decibels(_ level: Float) -> Double {
            20 * log10(max(Double(level), 1e-6))
        }

        static func formatText(_ asbd: RingHeader.ASBD) -> String {
            guard asbd.sampleRate > 0 else { return "no format yet" }
            let isFloat = asbd.formatFlags & 0x1 != 0          // kAudioFormatFlagIsFloat
            let isBigEndian = asbd.formatFlags & 0x2 != 0      // kAudioFormatFlagIsBigEndian
            return "\(Int(asbd.sampleRate)) Hz · \(asbd.channelsPerFrame) ch · \(asbd.bitsPerChannel)-bit \(isFloat ? "float" : "int") · \(isBigEndian ? "big-endian" : "little-endian")"
        }
    }

    static let pollIntervalNanoseconds: UInt64 = 250_000_000

    private(set) var snapshot: Snapshot?
    private(set) var ringPresent = false
    private(set) var record: BroadcastStateRecord?
    private(set) var lastHeartbeat: KeepAliveMonitor.Heartbeat?
    private(set) var gapCount = 0
    private(set) var engineRunning = false
    private(set) var isHoldingSession = false
    let logURL: URL?

    private let containerURL: URL?
    private let records: BroadcastRecordStore?
    private let keepAlive: KeepAliveMonitor
    private let sessionController: AudioSessionController
    private let clock: @Sendable () -> Double
    @ObservationIgnored private var mapping: RingFileMapping?
    @ObservationIgnored private var storage: MappedRingStorage?
    @ObservationIgnored private var lastRefreshAt: Double?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(containerURL: URL?, records: BroadcastRecordStore?, keepAlive: KeepAliveMonitor, sessionController: AudioSessionController,
         clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.containerURL = containerURL
        self.records = records
        self.keepAlive = keepAlive
        self.sessionController = sessionController
        self.clock = clock
        self.logURL = nil
    }

    func refresh() async {
        let now = clock()
        if storage == nil, let containerURL, let mapping = try? RingFileMapping.openExisting(at: RingFileMapping.ringURL(in: containerURL)) {
            self.mapping = mapping
            storage = MappedRingStorage(mapping: mapping)
        }
        if let storage, let header = RingHeader.read(from: storage) {
            ringPresent = true
            let elapsed = lastRefreshAt.map { now - $0 } ?? 0
            snapshot = Snapshot.make(header: header, previous: snapshot, now: now, elapsed: elapsed)
        } else {
            ringPresent = false
            snapshot = nil
        }
        lastRefreshAt = now
        record = records?.readBroadcastState()
        lastHeartbeat = keepAlive.lastHeartbeat
        gapCount = keepAlive.gapCount
        engineRunning = await sessionController.isEngineRunning
    }

    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Broadcast-mode keep-alive without a pipeline: `.playback` / `[.mixWithOthers]`, engine running, heartbeat
    /// ticking on the ring's write cursor (§6.8 spike, criterion 1 and 3).
    func setHoldingSession(_ on: Bool) async {
        if on {
            do {
                try await sessionController.configure(for: .broadcast)
                try await sessionController.startEngine()
                isHoldingSession = true
                let storage = self.storage
                keepAlive.reset()
                keepAlive.start(position: { Int64(storage?.loadCursor(at: RingHeader.Offset.writeCursor) ?? 0) }, onGap: { _ in })
            } catch {
                isHoldingSession = false
            }
        } else {
            keepAlive.stop()
            await sessionController.stopEngine()
            isHoldingSession = false
        }
        await refresh()
    }
}
