import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class AudioSessionControllerTests: XCTestCase {
    func testMicrophoneConfigurationAppliesTheR8MaskThenActivates() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)

        XCTAssertEqual(seam.calls, ["makeEngine", "setCategory", "setActive(true)"])
        let mask = try XCTUnwrap(seam.masks.first)
        XCTAssertEqual(mask.category, .playAndRecord)
        XCTAssertEqual(mask.mode, .default)
        XCTAssertEqual(mask.options, [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker])
        XCTAssertEqual(AudioSessionController.residentMask(for: .microphone), AudioSessionController.microphoneMask)
        XCTAssertEqual(AudioSessionController.residentMask(for: .broadcast), AudioSessionController.broadcastMask)
        XCTAssertEqual(AudioSessionController.broadcastMask.options, [.mixWithOthers])
        XCTAssertFalse(mask.options.contains(.duckOthers), ".duckOthers is never resident")
    }

    func testGuardedPlayFiresOnlyAfterASuccessfulEngineStart() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let hookCalls = Counter()
        await controller.setPlayHook { hookCalls.increment() }
        try await controller.configure(for: .microphone)
        let engine = try XCTUnwrap(seam.lastEngine)

        await controller.guardedPlay()
        XCTAssertEqual(hookCalls.value, 0, "engine not running")

        engine.startFails = true
        do {
            try await controller.startEngine()
            XCTFail("expected the start failure to propagate")
        } catch {}
        XCTAssertEqual(hookCalls.value, 0)

        engine.startFails = false
        try await controller.startEngine()
        XCTAssertEqual(hookCalls.value, 1)
        XCTAssertEqual(engine.prepareCount, 2)
        let playCount = await controller.playCount
        XCTAssertEqual(playCount, 1)
    }

    func testModeSwitchTearsDownThePreviousEngine() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let first = try XCTUnwrap(seam.lastEngine)
        try await controller.configure(for: .microphone)
        XCTAssertEqual(seam.engines.count, 1, "same mode keeps the engine")

        try await controller.configure(for: .broadcast)
        XCTAssertEqual(seam.engines.count, 2)
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(seam.masks.last?.category, .playback)
        XCTAssertEqual(seam.masks.last?.options, [.mixWithOthers])
    }

    func testInterruptionEndedReactivatesRestartsAndPlaysOnce() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let hookCalls = Counter()
        await controller.setPlayHook { hookCalls.increment() }
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        var iterator = controller.events.makeAsyncIterator()

        engine.isRunning = false   // iOS stopped the engine with the interruption
        await controller.handle(.began)
        let paused = await iterator.next()
        XCTAssertEqual(paused, .pausedByIOS)

        await controller.handle(.ended(shouldResume: true))
        let resumed = await iterator.next()
        XCTAssertEqual(resumed, .resumed)
        XCTAssertEqual(seam.calls.suffix(1), ["setActive(true)"])
        XCTAssertEqual(engine.startCount, 2)
        XCTAssertEqual(hookCalls.value, 2)
    }

    func testInterruptionEndedWithoutResumeIsAttemptedOnceThenReported() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        var iterator = controller.events.makeAsyncIterator()

        engine.isRunning = false
        engine.startFails = true
        await controller.handle(.ended(shouldResume: false))
        let event = await iterator.next()
        XCTAssertEqual(event, .resumeFailed)
        XCTAssertEqual(engine.startCount, 2, "exactly one attempt")
    }

    func testMediaServicesResetRebuildsEngineAndReappliesTheCategory() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        var iterator = controller.events.makeAsyncIterator()

        await controller.handle(.mediaServicesReset)
        let event = await iterator.next()
        XCTAssertEqual(event, .audioRestarted)
        XCTAssertEqual(seam.engines.count, 2)
        XCTAssertEqual(seam.calls.suffix(3), ["makeEngine", "setCategory", "setActive(true)"])
        XCTAssertEqual(seam.masks.last, AudioSessionController.microphoneMask)
        XCTAssertTrue(seam.lastEngine?.isRunning ?? false)
    }

    /// The session is never deactivated by a stop (`.mixWithOthers`, §6.8), so iOS keeps delivering interruptions to
    /// an idle ReVox. One that lands while nothing runs must neither start the engine — a `.playAndRecord` engine
    /// pulling the input lights the microphone indicator with no run in progress — nor tell the Live screen that a
    /// translation was paused.
    func testInterruptionWhileNothingRunsTouchesNeitherTheEngineNorTheScreen() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let hookCalls = Counter()
        await controller.setPlayHook { hookCalls.increment() }
        try await controller.configure(for: .microphone)
        let engine = try XCTUnwrap(seam.lastEngine)
        var iterator = controller.events.makeAsyncIterator()
        let callsBefore = seam.calls.count

        await controller.handle(.began)
        await controller.handle(.ended(shouldResume: true))
        XCTAssertEqual(engine.startCount, 0, "no run was in progress: the engine stays down")
        XCTAssertEqual(hookCalls.value, 0)
        XCTAssertEqual(seam.calls.count, callsBefore, "the session is not reactivated either")
        let event = await withTimeout(seconds: 0.3) { await iterator.next() }
        XCTAssertNil(event, "nothing is paused, so nothing is reported")
    }

    /// The same after a run: `AudioPlayer.stop()` stops the engine, and an interruption that follows is not a reason
    /// to bring it back.
    func testInterruptionAfterStopEngineDoesNotRestartIt() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        await controller.stopEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        var iterator = controller.events.makeAsyncIterator()

        await controller.handle(.began)
        await controller.handle(.ended(shouldResume: true))
        XCTAssertEqual(engine.startCount, 1, "only the run's own start")
        XCTAssertFalse(engine.isRunning)
        let event = await withTimeout(seconds: 0.3) { await iterator.next() }
        XCTAssertNil(event)
    }

    /// A media-services reset while idle still rebuilds the engine and re-applies the resident mask (the next run
    /// needs both), but the rebuilt engine is left stopped and the screen is not told that audio restarted.
    func testMediaServicesResetWhileIdleRebuildsWithoutStartingTheEngine() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        var iterator = controller.events.makeAsyncIterator()

        await controller.handle(.mediaServicesReset)
        XCTAssertEqual(seam.engines.count, 2)
        XCTAssertEqual(seam.calls.suffix(3), ["makeEngine", "setCategory", "setActive(true)"])
        XCTAssertEqual(seam.lastEngine?.startCount, 0, "idle: the rebuilt engine is not started")
        XCTAssertFalse(seam.lastEngine?.isRunning ?? true)
        let event = await withTimeout(seconds: 0.3) { await iterator.next() }
        XCTAssertNil(event, "no run to restart, nothing to show")
    }

    // MARK: AVAudioEngineConfigurationChange (§6.8, §9 "Route change")

    /// When the output hardware's format changes (speaker ↔ headphones) `AVAudioEngine` stops itself and posts
    /// `AVAudioEngineConfigurationChange`. In microphone mode `MicrophoneCapture` rebuilds its tap and restarts the
    /// engine; in broadcast mode there is no tap and nobody did, so every later clip was scheduled into a stopped
    /// engine, `.dataPlayedBack` never fired, `isSpeaking` stayed true and the self-capture gate dropped the rest
    /// of the session's audio. The controller owns the engine in that mode, so it restarts it.
    func testBroadcastEngineIsRestartedAfterAConfigurationChange() async throws {
        let seam = RecordingAudioSessionSeam()
        let center = NotificationCenter()
        let controller = AudioSessionController(session: seam, center: center)
        let hookCalls = Counter()
        await controller.setPlayHook { hookCalls.increment() }
        try await controller.configure(for: .broadcast)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertEqual(hookCalls.value, 1)

        engine.isRunning = false                              // what the engine does before it posts the notification
        center.post(name: Notification.Name.AVAudioEngineConfigurationChange, object: nil)
        await waitFor("the engine restart") { engine.startCount == 2 }
        XCTAssertEqual(engine.startCount, 2)
        XCTAssertTrue(engine.isRunning)
        await waitFor("the guarded play after the restart") { hookCalls.value == 2 }
        XCTAssertEqual(hookCalls.value, 2, "the player node is re-played on the restarted engine (§6.7)")
    }

    /// Microphone mode keeps the existing owner: the tap must be re-seated on the new hardware format before the
    /// engine starts (§6.1), which `MicrophoneCapture` does, so the controller leaves the notification alone.
    func testMicrophoneEngineConfigurationChangeIsLeftToTheCapture() async throws {
        let seam = RecordingAudioSessionSeam()
        let center = NotificationCenter()
        let controller = AudioSessionController(session: seam, center: center)
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)

        engine.isRunning = false
        center.post(name: Notification.Name.AVAudioEngineConfigurationChange, object: nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(engine.startCount, 1, "the tap owner restarts it, after the rebuild")
    }

    /// The same rule as for interruptions: with no run wanting the engine, a configuration change starts nothing;
    /// and a torn-down engine's notification never reaches the controller at all.
    func testConfigurationChangeWithoutARunOrAfterATeardownStartsNothing() async throws {
        let seam = RecordingAudioSessionSeam()
        let center = NotificationCenter()
        let controller = AudioSessionController(session: seam, center: center)
        try await controller.configure(for: .broadcast)
        let first = try XCTUnwrap(seam.lastEngine)
        center.post(name: Notification.Name.AVAudioEngineConfigurationChange, object: nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(first.startCount, 0, "idle: nothing to restart")

        try await controller.startEngine()
        try await controller.configure(for: .microphone)      // a mode switch tears the broadcast engine down
        let second = try XCTUnwrap(seam.lastEngine)
        XCTAssertFalse(first === second)
        center.post(name: Notification.Name.AVAudioEngineConfigurationChange, object: nil)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(first.startCount, 1, "the old engine is not started again")
        XCTAssertEqual(second.startCount, 0)
    }

    func testRouteChangesReachTheTapHandlerAndTheEventStreamWithoutSessionCalls() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        let reasons = RouteReasonRecorder()
        await controller.setRouteChangeHandler { reasons.record($0) }
        let before = seam.calls.count
        var iterator = controller.events.makeAsyncIterator()

        await controller.handle(.routeChanged(reason: .categoryChange))
        let first = await iterator.next()
        XCTAssertEqual(first, .routeChanged(.categoryChange))

        await controller.handle(.routeChanged(reason: .oldDeviceUnavailable))
        let second = await iterator.next()
        XCTAssertEqual(second, .routeChanged(.oldDeviceUnavailable))

        // The controller forwards every reason verbatim; MicrophoneCapture decides which one rebuilds the tap (§6.1).
        XCTAssertEqual(reasons.all, [.categoryChange, .oldDeviceUnavailable])
        XCTAssertEqual(seam.calls.count, before, "a route change touches neither the session nor the engine")

        await controller.setRouteChangeHandler(nil)
        await controller.handle(.routeChanged(reason: .newDeviceAvailable))
        _ = await iterator.next()
        XCTAssertEqual(reasons.all.count, 2, "a cleared handler is never called again")
    }

    /// §6.1: "if the input becomes unavailable the pipeline continues with silence and the status line shows
    /// 'No microphone input'". `MicrophoneCapture` (Task 30) reaches the Live screen through this door.
    func testPublishCaptureStatusReachesTheEventStreamAndClearsAgain() async {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        var iterator = controller.events.makeAsyncIterator()

        await controller.publishCaptureStatus("No microphone input")
        let reported = await iterator.next()
        XCTAssertEqual(reported, .captureStatus("No microphone input"))

        await controller.publishCaptureStatus(nil)
        let cleared = await iterator.next()
        XCTAssertEqual(cleared, .captureStatus(nil))
        XCTAssertEqual(seam.calls, [], "publishing a status touches neither the session nor the engine")
    }

    func testInterruptionNotificationParsing() {
        let began = Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                 userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertEqual(InterruptionObserver.event(from: began), .began)

        let ended = Notification(name: AVAudioSession.interruptionNotification, object: nil, userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ])
        XCTAssertEqual(InterruptionObserver.event(from: ended), .ended(shouldResume: true))

        let endedNoResume = Notification(name: AVAudioSession.interruptionNotification, object: nil,
                                         userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        XCTAssertEqual(InterruptionObserver.event(from: endedNoResume), .ended(shouldResume: false))

        let route = Notification(name: AVAudioSession.routeChangeNotification, object: nil,
                                 userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertEqual(InterruptionObserver.event(from: route), .routeChanged(reason: .oldDeviceUnavailable))

        let reset = Notification(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        XCTAssertEqual(InterruptionObserver.event(from: reset), .mediaServicesReset)
    }
}

/// Lock-guarded counter for hooks that fire off the test's actor.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Lock-guarded recorder for the route-change hook, which the controller calls from its own actor.
final class RouteReasonRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [AVAudioSession.RouteChangeReason] = []
    func record(_ reason: AVAudioSession.RouteChangeReason) { lock.lock(); reasons.append(reason); lock.unlock() }
    var all: [AVAudioSession.RouteChangeReason] { lock.lock(); defer { lock.unlock() }; return reasons }
}
