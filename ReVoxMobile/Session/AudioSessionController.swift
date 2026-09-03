import AVFAudio
import Foundation
import os
import ReVoxCore

enum AudioSessionError: Error, Equatable {
    case notConfigured
}

/// Owns the audio session and the single engine (§6.8, R8). Every session or engine call goes through the seam.
///
/// Ducking: `duck()` applies the on-edge and `restore()` the deactivation cycle. The blocking steps of a cycle run on a
/// private serial queue bridged with a continuation, so every step is a suspension point at which the actor accepts
/// the next request. `pendingDuck` is the latest request, `appliedDuck` whether the mask most recently handed to
/// `setCategory` carried `.duckOthers`, `isDucked` the published value assigned only at the end of a cycle; the
/// end-of-cycle reconciliation runs one more edge while the two disagree.
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
    private static let logger = Logger(subsystem: "revox", category: "session")
    private static let duckingLogger = Logger(subsystem: "revox", category: "ducking")

    // MARK: Ducking state (§6.8)

    private(set) var onEdge: DuckingOnEdge = .optionsOnly
    /// The requested state: the latest thing the coordinator asked for, at any time.
    private(set) var pendingDuck = false
    /// The applied state: whether the mask most recently passed to `setCategory` carried `.duckOthers`.
    private(set) var appliedDuck = false
    private(set) var cycleInProgress = false
    /// The published state, assigned `appliedDuck` at the end of every cycle and never mid-cycle.
    private(set) var isDucked = false
    /// Reconciliation passes run so far (diagnostic for the on-device measurement).
    private(set) var extraPassCount = 0
    private var lastReportedDucked = false
    private let cycleQueue = DispatchQueue(label: "revox.session.cycle")

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
        clearDucking()
    }

    /// Re-applying the resident mask outside a cycle (configuration, media-services reset) also restores the whole
    /// §6.8 invariant `isDucked == appliedDuck == pendingDuck`, not just `appliedDuck`: otherwise a reset while ducked
    /// would leave `isDucked` true with `.duckOthers` genuinely off, the next speaking-false edge would find
    /// `appliedDuck == false` and return without a cycle, and the Live "Ducking" pill would strand for the rest of the
    /// session. The `.duckingChanged(false)` is emitted only when the last reported value was true.
    private func clearDucking() {
        appliedDuck = false
        pendingDuck = false
        isDucked = false
        if lastReportedDucked {
            lastReportedDucked = false
            eventContinuation.yield(.duckingChanged(false))
        }
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
            Self.duckingLogger.info("route change reason=\(reason.rawValue, privacy: .public)")
            eventContinuation.yield(.routeChanged(reason))
        case .mediaServicesReset:
            tearDownEngine()
            engine = session.makeEngine()
            do {
                if let mode {
                    try session.setCategory(Self.residentMask(for: mode))
                    try session.setActive(true, options: [])
                    clearDucking()
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

    // MARK: Ducker (§6.8, R8)

    /// A-on (default) or B-on (the fallback); changed only between sessions, never inside a cycle.
    func setDuckingOnEdge(_ edge: DuckingOnEdge) {
        onEdge = edge
    }

    /// Speaking-true edge. Records the request; while a cycle runs it returns at once (the cycle reads `pendingDuck`
    /// at its reactivation step or in its reconciliation); otherwise a no-op when already applied (Windows
    /// `Ducker.duck`: `if self._ducked: return`), else the on-edge.
    func duck() async {
        pendingDuck = true
        guard mode != nil, engine != nil else { return }   // before configure: only the request is recorded
        if cycleInProgress { return }
        guard !appliedDuck else { return }
        await runCycle(startingWith: .on)
    }

    /// Speaking-false edge after the coordinator's hold, mute and stop. Idempotent: when not applied and no cycle runs
    /// it makes no session call (Windows `Ducker.restore`: `if not self._ducked: return`).
    func restore() async {
        pendingDuck = false
        guard mode != nil, engine != nil else { return }
        if cycleInProgress { return }
        guard appliedDuck else { return }
        await runCycle(startingWith: .off)
    }

    private enum Edge {
        case on, off
    }

    private func runCycle(startingWith edge: Edge) async {
        cycleInProgress = true
        let start = ContinuousClock.now
        do {
            try await runEdge(edge)
            // End-of-cycle reconciliation: one more edge while the applied mask disagrees with the latest request.
            var passes = 0
            while appliedDuck != pendingDuck {
                passes += 1
                extraPassCount += 1
                if passes > 1 {
                    Self.duckingLogger.notice("reconciliation pass \(passes, privacy: .public): the coordinator changed its mind again")
                }
                try await runEdge(pendingDuck ? .on : .off)
            }
        } catch {
            await recoverSession(after: error)
        }
        cycleInProgress = false
        isDucked = appliedDuck
        let milliseconds = Int((ContinuousClock.now - start) / .milliseconds(1))
        let running = engine?.isRunning ?? false
        Self.duckingLogger.info("cycle done edge=\(edge == .on ? "on" : "off", privacy: .public) onEdge=\(self.onEdge.rawValue, privacy: .public) ducked=\(self.isDucked, privacy: .public) engineRunning=\(running, privacy: .public) ms=\(milliseconds, privacy: .public)")
        if isDucked != lastReportedDucked {
            lastReportedDucked = isDucked
            eventContinuation.yield(.duckingChanged(isDucked))
        }
    }

    private func runEdge(_ edge: Edge) async throws {
        guard let mode else { throw AudioSessionError.notConfigured }
        let resident = Self.residentMask(for: mode)
        switch (edge, onEdge) {
        case (.on, .optionsOnly):
            // A-on: the options-only "on" mask on the active session (R8); route options identical, .mixWithOthers explicit.
            let wantDuck = pendingDuck
            let mask = wantDuck ? resident.adding(.duckOthers) : resident
            let session = self.session
            try await perform { try session.setCategory(mask) }
            appliedDuck = wantDuck
            Self.duckingLogger.info("on-edge options-only applied duck=\(wantDuck, privacy: .public)")
        case (.on, .fullCycle):
            // B-on: the session was mixable and un-ducked, nothing was interrupted, so nothing to notify.
            try await deactivationCycle(resident: resident, notifyOthers: false)
        case (.off, _):
            // B-off: the documented path — ducking ends when the session deactivates.
            try await deactivationCycle(resident: resident, notifyOthers: true)
        }
    }

    /// pause → setActive(false[, notify]) → setCategory(resident, or resident + .duckOthers when a duck is pending)
    /// → setActive(true) → engine.start() → guarded play(). The mask is decided at the reactivation step.
    private func deactivationCycle(resident: SessionMask, notifyOthers: Bool) async throws {
        guard let engine else { throw AudioSessionError.notConfigured }
        let session = self.session
        try await perform { engine.pause() }   // deactivating with a rendering engine returns .isBusy (§6.8)
        try await perform { try session.setActive(false, options: notifyOthers ? [.notifyOthersOnDeactivation] : []) }
        let wantDuck = pendingDuck
        let mask = wantDuck ? resident.adding(.duckOthers) : resident
        try await perform { try session.setCategory(mask) }
        appliedDuck = wantDuck
        try await perform { try session.setActive(true, options: []) }
        try await perform { try engine.start() }
        guardedPlay()
        Self.duckingLogger.info("deactivation cycle notify=\(notifyOthers, privacy: .public) applied duck=\(wantDuck, privacy: .public)")
    }

    /// Runs one blocking session or engine call on the serial cycle queue; the actor is free while it runs.
    private func perform(_ step: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cycleQueue.async {
                do {
                    try step()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Invariant (§6.8): the session is never left inactive. On any thrown step, re-apply the resident mask, activate,
    /// start the engine and play, log, and clear every ducking flag (a lost duck costs one un-ducked phrase: the
    /// coordinator's next false edge forwards a no-op restore and its next true edge re-issues `duck()`).
    private func recoverSession(after error: Error) async {
        Self.duckingLogger.error("ducking cycle failed: \(String(describing: error), privacy: .public); restoring the resident session")
        appliedDuck = false
        pendingDuck = false
        guard let mode, let engine else { return }
        let resident = Self.residentMask(for: mode)
        let session = self.session
        do {
            try await perform { try session.setCategory(resident) }
            try await perform { try session.setActive(true, options: []) }
            try await perform {
                if !engine.isRunning { try engine.start() }
            }
            guardedPlay()
        } catch {
            Self.duckingLogger.error("session recovery failed: \(String(describing: error), privacy: .public)")
        }
    }
}
