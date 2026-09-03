import AVFAudio
import Foundation
import os
import ReVoxCore

enum AudioSessionError: Error, Equatable {
    case notConfigured
}

/// Owns the audio session and the single engine (§6.8, R8). Every session or engine call goes through the seam.
actor AudioSessionController: Ducker {
    static let microphoneMask = SessionMask(
        category: .playAndRecord, mode: .default,
        options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]
    )
    static let broadcastMask = SessionMask(category: .playback, mode: .default, options: [.mixWithOthers])

    static func residentMask(for mode: CaptureMode) -> SessionMask {
        switch mode {
        case .microphone: return microphoneMask
        case .broadcast: return broadcastMask
        }
    }

    nonisolated let events: AsyncStream<SessionEvent>
    private let eventContinuation: AsyncStream<SessionEvent>.Continuation
    private let session: any AudioSessionSeam
    private var engine: (any AudioEngineSeam)?
    private(set) var mode: CaptureMode?
    private var playHook: (@Sendable () -> Void)?
    private var routeChangeHandler: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?
    private(set) var playCount = 0
    /// The latest ducking request (M4 applies it in the cycles; M3 only records it).
    private(set) var pendingDuck = false
    private static let logger = Logger(subsystem: "revox", category: "session")

    init(session: any AudioSessionSeam = LiveAudioSessionSeam()) {
        self.session = session
        let (stream, continuation) = AsyncStream<SessionEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.eventContinuation = continuation
    }

    // MARK: Configuration (foreground, before pipeline.start)

    func configure(for mode: CaptureMode) throws {
        if self.mode != mode || engine == nil {
            tearDownEngine()
            engine = session.makeEngine()
            self.mode = mode
        }
        try session.setCategory(Self.residentMask(for: mode))
        try session.setActive(true, options: [])
    }

    /// The real engine for tap installation and player-node attachment; nil until configured (and in tests).
    func engineForGraph() -> AVAudioEngine? {
        engine?.engine
    }

    // MARK: Engine and the guarded play hook (§6.7)

    /// Installed by `AudioPlayer`; the closure is `playerNode.play()` and nothing else ever calls it.
    func setPlayHook(_ hook: (@Sendable () -> Void)?) {
        playHook = hook
    }

    /// Installed by `MicrophoneCapture.start(_:)` and cleared by its `stop()`. Every `routeChangeNotification`
    /// reason is forwarded verbatim; the capture source rebuilds the tap on `.oldDeviceUnavailable` and
    /// `.newDeviceAvailable` and ignores the rest, including `.categoryChange` (§6.1, §6.8).
    func setRouteChangeHandler(_ handler: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?) {
        routeChangeHandler = handler
    }

    func startEngine() throws {
        guard let engine else { throw AudioSessionError.notConfigured }
        engine.prepare()
        try engine.start()
        guardedPlay()
    }

    /// The only call site of `play()`: after a successful start and only while the engine runs.
    func guardedPlay() {
        guard let engine, engine.isRunning, let playHook else { return }
        playCount += 1
        playHook()
    }

    func stopEngine() {
        engine?.stop()
    }

    var isEngineRunning: Bool {
        engine?.isRunning ?? false
    }

    private func tearDownEngine() {
        engine?.stop()
        engine = nil
    }

    // MARK: Interruptions, routes, media services (§6.8, §9)

    func handle(_ event: InterruptionEvent) {
        switch event {
        case .began:
            eventContinuation.yield(.pausedByIOS)
        case .ended(let shouldResume):
            Self.logger.info("interruption ended shouldResume=\(shouldResume, privacy: .public)")
            do {
                try session.setActive(true, options: [])
                try startEngine()
                eventContinuation.yield(.resumed)
            } catch {
                Self.logger.error("resume after interruption failed: \(String(describing: error), privacy: .public)")
                eventContinuation.yield(.resumeFailed)
            }
        case .routeChanged(let reason):
            routeChangeHandler?(reason)   // §6.1/§6.8: the mic tap rebuild for device changes
            eventContinuation.yield(.routeChanged(reason))
        case .mediaServicesReset:
            tearDownEngine()
            engine = session.makeEngine()
            do {
                if let mode {
                    try session.setCategory(Self.residentMask(for: mode))
                    try session.setActive(true, options: [])
                }
                try startEngine()
            } catch {
                Self.logger.error("rebuild after media services reset failed: \(String(describing: error), privacy: .public)")
            }
            eventContinuation.yield(.audioRestarted)
        }
    }

    // MARK: The capture source's status line (§6.1)

    /// Puts the capture source's own status on the one stream the Live screen observes; `nil` clears it.
    /// `MicrophoneCapture` calls this after a tap rebuild has exhausted its retries with no input, and again
    /// with `nil` when a later rebuild finds one (Task 30).
    func publishCaptureStatus(_ text: String?) {
        eventContinuation.yield(.captureStatus(text))
    }

    // MARK: Ducker (M3 records the request; M4 implements the on-edge and the deactivation cycle)

    func duck() async {
        pendingDuck = true
    }

    func restore() async {
        pendingDuck = false
    }
}
