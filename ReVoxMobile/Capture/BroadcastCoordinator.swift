import Foundation
import Observation
import ReVoxCore

/// Main-actor view of the broadcast (§6.2 "State record", §9): probes the record and the ring header on launch,
/// `didBecomeActive` and the started/stopped wakes; turns `BroadcastCaptureEvent`s into the Live status texts and
/// the events the view model acts on; asks for a foreground start when a live broadcast is found while idle.
@MainActor
@Observable
final class BroadcastCoordinator {
    static let startPromptText = "Start a broadcast to listen to other apps"
    static let endedText = "Broadcast ended"
    static let staleText = "The broadcast stopped unexpectedly"
    static let silentText = "No audio from the app (some players are not captured)"
    static let joinedText = "Joined a broadcast in progress"

    static func failedText(_ reason: String) -> String {
        "Broadcast failed: \(reason)"
    }

    enum Event: Equatable, Sendable {
        case attached(joinedInProgress: Bool)
        case ended(reason: String?)
        case stale
        case silent
    }

    private(set) var attachState: AttachState = .noRing
    private(set) var statusText: String? = BroadcastCoordinator.startPromptText
    /// From the last probe: the record says running and the ring heartbeat is fresh (meaningful while not attached).
    private(set) var isBroadcastLive = false
    let events: AsyncStream<Event>
    var onBroadcastLive: (@MainActor () async -> Void)?

    var isAttached: Bool {
        if case .attachedLive = attachState { return true }
        return false
    }

    /// The Live screen shows the picker (§8.2) while no broadcast is attached or known to be live.
    var needsBroadcast: Bool { !isAttached && !isBroadcastLive }

    private let capture: BroadcastCapture
    private let records: BroadcastRecordStore?
    private let containerURL: URL?
    private let names: BroadcastNotificationNames
    private let clock: @Sendable () -> Double
    private let continuation: AsyncStream<Event>.Continuation
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var observer: DarwinNotificationObserver?
    /// Kept for the coordinator's life rather than re-created per probe: `openExisting` is an open + fstat + mmap of
    /// 3.84 MB, and `probe()` runs on the main actor on every `started`/`stopped` wake — which any app on the device
    /// can post (docs/security-review-m5.md finding 6). The extension only ever grows this file, never replaces it,
    /// so one mapping stays valid across broadcasts; a new generation is detected from the header, not the mapping.
    @ObservationIgnored private var mapping: RingFileMapping?
    @ObservationIgnored private var storage: MappedRingStorage?

    init(capture: BroadcastCapture, records: BroadcastRecordStore?, containerURL: URL?, names: BroadcastNotificationNames,
         clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.capture = capture
        self.records = records
        self.containerURL = containerURL
        self.names = names
        self.clock = clock
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
    }

    /// Observes the capture's events for the app's lifetime and the started/stopped wakes for the idle case.
    func start() {
        stop()
        let capture = self.capture
        captureTask = Task { [weak self] in
            for await event in capture.events {
                guard let self else { return }
                self.handle(event)
            }
        }
        let observer = DarwinNotificationObserver(names: [names.started, names.stopped])
        self.observer = observer
        observer.start()
        wakeTask = Task { [weak self] in
            for await _ in observer.names {
                guard let self else { return }
                await self.probe()
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        observer?.stop()
        observer = nil
    }

    func applicationDidBecomeActive() async {
        await probe()
    }

    /// Reads the record and the header (a transient read-only mapping); a live broadcast found while not attached
    /// asks the environment to start the pipeline from the foreground (§6.2).
    func probe() async {
        let record = records?.readBroadcastState()
        let header = currentHeader()
        let evaluated = Self.evaluate(record: record, header: header, now: clock())
        if case .attachedLive = evaluated {
            isBroadcastLive = true
            if !isAttached, statusText == Self.startPromptText || statusText == Self.endedText {
                statusText = nil
            }
            if !isAttached, let onBroadcastLive {
                await onBroadcastLive()
            }
        } else {
            isBroadcastLive = false
            if !isAttached, statusText == nil {
                statusText = Self.startPromptText
            }
        }
    }

    func handle(_ event: BroadcastCaptureEvent) {
        switch event {
        case .noRing:
            attachState = .noRing
            isBroadcastLive = false
            statusText = Self.startPromptText
        case .attached(let generation, let joinedInProgress):
            attachState = .attachedLive(generation: generation)
            isBroadcastLive = true
            statusText = joinedInProgress ? Self.joinedText : nil
            continuation.yield(.attached(joinedInProgress: joinedInProgress))
        case .idle:
            attachState = .idle
            isBroadcastLive = false
            let reason = records?.readBroadcastState()?.finishReason      // only the extension's own failure text (§6.2)
            statusText = reason.map(Self.failedText) ?? Self.endedText
            continuation.yield(.ended(reason: reason))
        case .stale(let lastWriteAt):
            attachState = .stale(lastWriteAt: lastWriteAt)
            isBroadcastLive = false
            statusText = Self.staleText
            continuation.yield(.stale)
        case .gap:
            break                                                        // the pipeline's `.lag` badge covers it
        case .silence:
            statusText = Self.silentText
            continuation.yield(.silent)
        }
    }

    /// The §5.9 attach table applied to a probe: the ring header is the truth, the record only adds the reason.
    static func evaluate(record: BroadcastStateRecord?, header: RingHeader?, now: Double) -> AttachState {
        guard let header else { return .noRing }
        switch header.state {
        case .running:
            return header.isHeartbeatFresh(now: now) ? .attachedLive(generation: header.generation) : .stale(lastWriteAt: header.lastWriteAt)
        case .idle, .paused, .finished, .failed:
            return .idle
        }
    }

    /// The header through the cached mapping; nil while the file is absent, short or its header unwritten.
    func currentHeader() -> RingHeader? {
        if storage == nil {
            guard let containerURL,
                  let mapping = try? RingFileMapping.openExisting(at: RingFileMapping.ringURL(in: containerURL)) else { return nil }
            self.mapping = mapping
            storage = MappedRingStorage(mapping: mapping)
        }
        guard let storage else { return nil }
        return RingHeader.read(from: storage)
    }
}
