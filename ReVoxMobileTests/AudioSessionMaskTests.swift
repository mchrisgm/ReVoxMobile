import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// The ducking cycles of §6.8 over the recording seam (§10.2). A held step blocks the controller's cycle queue,
/// not the actor, so `duck()` / `restore()` issued meanwhile exercise the mid-cycle reconciliation rule.
final class AudioSessionMaskTests: XCTestCase {
    struct Rig {
        let controller: AudioSessionController
        let seam: RecordingAudioSessionSeam
        let engine: FakeEngineSeam
        let plays: Counter
    }

    /// `offEdge` defaults to the deactivation cycle rather than to the shipped default, so every case written
    /// against that cycle keeps exercising it as the fallback it now is. The shipped default has its own case.
    func makeRig(onEdge: DuckingOnEdge = .optionsOnly, offEdge: DuckingOffEdge = .deactivationCycle) async throws -> Rig {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        await controller.setDuckingOnEdge(onEdge)
        await controller.setDuckingOffEdge(offEdge)
        let plays = Counter()
        await controller.setPlayHook { plays.increment() }
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        seam.clearCalls()
        return Rig(controller: controller, seam: seam, engine: engine, plays: plays)
    }

    var resident: SessionMask { AudioSessionController.microphoneMask }
    var duckedResident: SessionMask { AudioSessionController.microphoneMask.adding(.duckOthers) }

    func testDuckOnAndOffMasksDifferOnlyByDuckOthers() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        XCTAssertEqual(rig.seam.calls, ["setCategory"], "A-on: one options-only setCategory on the active session")
        XCTAssertEqual(rig.seam.masks.last, duckedResident)
        XCTAssertEqual(duckedResident.options.subtracting(.duckOthers), resident.options)
        XCTAssertEqual(duckedResident.category, resident.category)
        XCTAssertEqual(duckedResident.mode, resident.mode)
        XCTAssertTrue(duckedResident.options.contains(.mixWithOthers), ".mixWithOthers stays explicit in both masks")
        var ducked = await rig.controller.isDucked
        XCTAssertTrue(ducked)
        XCTAssertEqual(rig.engine.pauseCount, 0, "the options-only on-edge does not touch the engine")

        rig.seam.clearCalls()
        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)"], "B-off: the deactivation cycle")
        XCTAssertEqual(rig.seam.masks.last, resident)
        XCTAssertEqual(rig.engine.pauseCount, 1)
        XCTAssertEqual(rig.engine.startCount, 2)
        XCTAssertTrue(rig.engine.isRunning)
        XCTAssertEqual(rig.plays.value, 2, "the guarded play after the cycle's engine start")
        ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertFalse(inProgress)
    }

    func testRestoreWhenNotDuckedIsNoOp() async throws {
        let rig = try await makeRig()
        await rig.controller.restore()
        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, [])
        XCTAssertEqual(rig.engine.pauseCount, 0)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
    }

    func testDuckTwiceAppliesOnce() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        await rig.controller.duck()
        XCTAssertEqual(rig.seam.calls, ["setCategory"])
    }

    func testDuckBeforeConfigurationOnlyRecordsTheRequest() async {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        await controller.duck()
        var pending = await controller.pendingDuck
        XCTAssertTrue(pending)
        await controller.restore()
        pending = await controller.pendingDuck
        XCTAssertFalse(pending)
        XCTAssertEqual(seam.calls, [], "no session exists to duck")
    }

    func testDuckingEdgesAreReportedAsSessionEvents() async throws {
        let rig = try await makeRig()
        var iterator = rig.controller.events.makeAsyncIterator()
        await rig.controller.duck()
        let on = await iterator.next()
        XCTAssertEqual(on, .duckingChanged(true))
        await rig.controller.duck()
        await rig.controller.restore()
        let off = await iterator.next()
        XCTAssertEqual(off, .duckingChanged(false))
    }

    func testDuckDuringCycleAppliesAtReactivation() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        rig.seam.clearCalls()
        rig.seam.holdNext("setActive(false, notify)")
        let restoreTask = Task { await rig.controller.restore() }
        await rig.seam.waitUntilHeld()

        await rig.controller.duck()   // returns immediately: the cycle is in progress
        let pending = await rig.controller.pendingDuck
        XCTAssertTrue(pending)
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertTrue(inProgress)

        rig.seam.resume()
        await restoreTask.value
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)"])
        XCTAssertEqual(rig.seam.masks.last, duckedResident, "the duck rides on the activation")
        let ducked = await rig.controller.isDucked
        XCTAssertTrue(ducked)
        XCTAssertTrue(rig.engine.isRunning)
        let passes = await rig.controller.extraPassCount
        XCTAssertEqual(passes, 0)
    }

    func testRestoreDuringCycleClearsPendingDuck() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        rig.seam.clearCalls()
        rig.seam.holdNext("setActive(false, notify)")
        let restoreTask = Task { await rig.controller.restore() }
        await rig.seam.waitUntilHeld()
        await rig.controller.duck()
        await rig.controller.restore()
        rig.seam.resume()
        await restoreTask.value
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)"], "the resident mask, no extra session call")
        XCTAssertEqual(rig.seam.masks.last, resident)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        let pending = await rig.controller.pendingDuck
        XCTAssertFalse(pending)
    }

    func testDuckAfterReactivationStepAppliesAtCycleEnd() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        rig.seam.clearCalls()
        rig.engine.holdNextStart()
        let restoreTask = Task { await rig.controller.restore() }
        await rig.engine.waitUntilStartHeld()
        await rig.controller.duck()
        rig.engine.resumeStart()
        await restoreTask.value
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)", "setCategory"],
                       "one options-only setCategory after the guarded play")
        XCTAssertEqual(rig.seam.masks[rig.seam.masks.count - 2], resident)
        XCTAssertEqual(rig.seam.masks.last, duckedResident)
        XCTAssertEqual(rig.plays.value, 2)
        let ducked = await rig.controller.isDucked
        XCTAssertTrue(ducked)
        let passes = await rig.controller.extraPassCount
        XCTAssertEqual(passes, 1)
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertFalse(inProgress)
    }

    /// §6.8: outside a cycle `isDucked == appliedDuck == pendingDuck`. A media-services reset re-applies the resident
    /// mask outside a cycle, so it must clear the published value and the pill too — not just `appliedDuck`.
    func testMediaServicesResetClearsTheWholeDuckingState() async throws {
        let rig = try await makeRig()
        var iterator = rig.controller.events.makeAsyncIterator()
        await rig.controller.duck()
        let on = await iterator.next()
        XCTAssertEqual(on, .duckingChanged(true))

        await rig.controller.handle(.mediaServicesReset)
        let off = await iterator.next()
        XCTAssertEqual(off, .duckingChanged(false), "the Live pill never strands on \"Ducking\" while .duckOthers is off")
        let ducked = await rig.controller.isDucked
        let applied = await rig.controller.appliedDuck
        let pending = await rig.controller.pendingDuck
        XCTAssertFalse(ducked)
        XCTAssertFalse(applied)
        XCTAssertFalse(pending)

        rig.seam.clearCalls()
        await rig.controller.duck()
        XCTAssertEqual(rig.seam.calls, ["setCategory"], "the next speaking-true edge re-ducks the rebuilt session")
        XCTAssertEqual(rig.seam.masks.last, duckedResident)
    }

    // MARK: B-on fallback, the never-inactive invariant and the reconciliation twins (§6.8, §10.2)

    func testFullCycleOnEdgeRunsTheCycleWithoutNotify() async throws {
        let rig = try await makeRig(onEdge: .fullCycle)
        await rig.controller.duck()
        XCTAssertEqual(rig.seam.calls, ["setActive(false)", "setCategory", "setActive(true)"], "B-on: deactivate without notifyOthersOnDeactivation")
        XCTAssertEqual(rig.seam.masks.last, duckedResident)
        XCTAssertEqual(rig.engine.pauseCount, 1)
        XCTAssertEqual(rig.engine.startCount, 2)
        XCTAssertEqual(rig.plays.value, 2, "the held first clip starts after the cycle's engine start")
        var ducked = await rig.controller.isDucked
        XCTAssertTrue(ducked)

        rig.seam.clearCalls()
        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)"])
        XCTAssertEqual(rig.seam.masks.last, resident)
        ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        XCTAssertTrue(rig.engine.isRunning)
    }

    func testRestoreDuringOptionsOnlyOnEdgeReRunsOffEdge() async throws {
        let rig = try await makeRig()
        rig.seam.holdNext("setCategory")
        let duckTask = Task { await rig.controller.duck() }
        await rig.seam.waitUntilHeld()
        await rig.controller.restore()   // mute while the on-edge is in flight
        rig.seam.resume()
        await duckTask.value
        XCTAssertEqual(rig.seam.calls, ["setCategory", "setActive(false, notify)", "setCategory", "setActive(true)"],
                       "exactly one deactivation cycle after the options-only on-edge")
        XCTAssertEqual(rig.seam.masks.first, duckedResident)
        XCTAssertEqual(rig.seam.masks.last, resident)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        XCTAssertTrue(rig.engine.isRunning)
        let passes = await rig.controller.extraPassCount
        XCTAssertEqual(passes, 1)
    }

    func testRestoreDuringOnEdgeCycleReRunsOffEdge() async throws {
        let rig = try await makeRig(onEdge: .fullCycle)
        rig.engine.holdNextStart()
        let duckTask = Task { await rig.controller.duck() }
        await rig.engine.waitUntilStartHeld()   // setCategory(resident + .duckOthers) already applied
        await rig.controller.restore()
        rig.engine.resumeStart()
        await duckTask.value
        XCTAssertEqual(rig.seam.calls, ["setActive(false)", "setCategory", "setActive(true)",
                                        "setActive(false, notify)", "setCategory", "setActive(true)"])
        XCTAssertEqual(rig.seam.masks, [duckedResident, resident])
        XCTAssertEqual(rig.plays.value, 3, "a guarded play after each engine start")
        XCTAssertEqual(rig.engine.pauseCount, 2)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        XCTAssertTrue(rig.engine.isRunning)
        let passes = await rig.controller.extraPassCount
        XCTAssertEqual(passes, 1, "no third pass")
    }

    func testRestoreAfterReactivationStepReRunsOffEdge() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        rig.seam.clearCalls()
        rig.seam.holdNext("setActive(false, notify)")
        let restoreTask = Task { await rig.controller.restore() }
        await rig.seam.waitUntilHeld()
        await rig.controller.duck()               // returns immediately
        rig.engine.holdNextStart()
        rig.seam.resume()
        await rig.engine.waitUntilStartHeld()      // reactivated with .duckOthers; engine.start() suspended
        await rig.controller.restore()            // restoreNow() from mute or stop
        rig.engine.resumeStart()
        await restoreTask.value
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)",
                                        "setActive(false, notify)", "setCategory", "setActive(true)"])
        XCTAssertEqual(rig.seam.masks, [duckedResident, resident])
        XCTAssertEqual(rig.plays.value, 3, "a guarded play after each engine start")
        XCTAssertEqual(rig.engine.pauseCount, 2)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        XCTAssertTrue(rig.engine.isRunning)
        let passes = await rig.controller.extraPassCount
        XCTAssertEqual(passes, 1, "no third pass")
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertFalse(inProgress)
    }

    func testThrowingStepRecoversTheSessionAndClearsDucking() async throws {
        let rig = try await makeRig()
        var iterator = rig.controller.events.makeAsyncIterator()
        await rig.controller.duck()
        let on = await iterator.next()
        XCTAssertEqual(on, .duckingChanged(true))
        rig.seam.clearCalls()
        rig.seam.failNext("setActive(true)", with: NSError(domain: "AVAudioSession", code: 561017449, userInfo: [NSLocalizedDescriptionKey: "isBusy"]))
        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)", "setCategory", "setActive(true)"],
                       "the failed reactivation is followed by resident mask + activate")
        XCTAssertEqual(rig.seam.masks.last, resident)
        XCTAssertTrue(rig.engine.isRunning, "the engine was restarted by the recovery")
        XCTAssertEqual(rig.plays.value, 2)
        let ducked = await rig.controller.isDucked
        let pending = await rig.controller.pendingDuck
        let applied = await rig.controller.appliedDuck
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertFalse(ducked)
        XCTAssertFalse(pending)
        XCTAssertFalse(applied)
        XCTAssertFalse(inProgress)
        let off = await iterator.next()
        XCTAssertEqual(off, .duckingChanged(false))
    }

    func testFailedOnEdgeRecoversAndTheNextEdgeReDucks() async throws {
        let rig = try await makeRig()
        rig.seam.failNext("setCategory", with: NSError(domain: "AVAudioSession", code: -50, userInfo: nil))
        await rig.controller.duck()
        XCTAssertEqual(rig.seam.calls, ["setCategory", "setCategory", "setActive(true)"], "recovery re-applies the resident mask and activates")
        XCTAssertEqual(rig.seam.masks.last, resident)
        XCTAssertEqual(rig.engine.startCount, 1, "the engine was still running: no restart")
        var ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        let pending = await rig.controller.pendingDuck
        XCTAssertFalse(pending, "the lost duck costs one un-ducked phrase")

        rig.seam.clearCalls()
        await rig.controller.duck()   // the next speaking-true edge re-issues the duck
        XCTAssertEqual(rig.seam.calls, ["setCategory"])
        XCTAssertEqual(rig.seam.masks.last, duckedResident)
        ducked = await rig.controller.isDucked
        XCTAssertTrue(ducked)
    }

    // MARK: the A-off measurement candidate and the two defaults (§6.8 decision table)

    func testOptionsOnlyOffEdgeIsOneSetCategoryWithTheResidentMask() async throws {
        XCTAssertEqual(AudioSessionController.defaultOnEdge, .optionsOnly, "R8's prescribed on-edge")
        XCTAssertEqual(AudioSessionController.defaultOffEdge, .optionsOnly, "no engine pause on the off-edge: it costs captured speech")
        let rig = try await makeRig(offEdge: .optionsOnly)
        await rig.controller.duck()
        rig.seam.clearCalls()
        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, ["setCategory"], "A-off: the options-only \"off\" mask on the active session")
        XCTAssertEqual(rig.seam.masks.last, resident)
        XCTAssertEqual(rig.engine.pauseCount, 0, "no deactivation, no engine pause")
        XCTAssertEqual(rig.plays.value, 1, "no extra guarded play")
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked)
        let inProgress = await rig.controller.cycleInProgress
        XCTAssertFalse(inProgress)

        // A duck that arrives during the options-only off-edge is reconciled with one more options-only on-edge.
        rig.seam.clearCalls()
        await rig.controller.duck()
        rig.seam.holdNext("setCategory")
        let restoreTask = Task { await rig.controller.restore() }
        await rig.seam.waitUntilHeld()
        await rig.controller.duck()
        rig.seam.resume()
        await restoreTask.value
        XCTAssertEqual(rig.seam.calls, ["setCategory", "setCategory", "setCategory"])
        XCTAssertEqual(rig.seam.masks, [duckedResident, resident, duckedResident])
        let reDucked = await rig.controller.isDucked
        XCTAssertTrue(reDucked)
    }

    /// `TranslationPipeline.stop()` stops the player (and the engine) before forwarding the coordinator's last
    /// `restoreNow()`, so the off-edge cycle of a Stop-while-ducked runs against a stopped engine. It must
    /// un-duck without bringing the engine back: otherwise the engine keeps rendering and the microphone
    /// indicator stays lit after the user pressed Stop.
    func testOffEdgeCycleDoesNotRestartAnEngineTheCallerStopped() async throws {
        let rig = try await makeRig()
        await rig.controller.duck()
        rig.seam.clearCalls()
        let startsBefore = rig.engine.startCount
        let playsBefore = rig.plays.value

        await rig.controller.stopEngine()          // what AudioPlayer.stop() does, before the final restore
        XCTAssertFalse(rig.engine.isRunning)

        await rig.controller.restore()
        XCTAssertEqual(rig.seam.calls, ["setActive(false, notify)", "setCategory", "setActive(true)"],
                       "the session still un-ducks and is left active (the never-inactive invariant)")
        XCTAssertEqual(rig.seam.masks.last, resident)
        XCTAssertEqual(rig.engine.startCount, startsBefore, "the stopped engine is not restarted")
        XCTAssertEqual(rig.plays.value, playsBefore, "and nothing is played into it")
        XCTAssertFalse(rig.engine.isRunning)
        let ducked = await rig.controller.isDucked
        XCTAssertFalse(ducked, "the duck is genuinely released")
    }

    /// The shipped defaults, end to end: a whole duck-and-restore with neither edge touching the engine. This is
    /// the case that keeps the microphone alive — a paused engine's input tap delivers nothing, so an off-edge
    /// that pauses costs captured speech after every phrase.
    func testShippedDefaultsNeverPauseTheEngineOnEitherEdge() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let plays = Counter()
        await controller.setPlayHook { plays.increment() }
        try await controller.configure(for: .microphone)
        try await controller.startEngine()
        let engine = try XCTUnwrap(seam.lastEngine)
        seam.clearCalls()

        let onEdge = await controller.onEdge
        let offEdge = await controller.offEdge
        XCTAssertEqual(onEdge, .optionsOnly, "the controller starts on the shipped defaults")
        XCTAssertEqual(offEdge, .optionsOnly)

        await controller.duck()
        XCTAssertEqual(seam.calls, ["setCategory"])
        XCTAssertEqual(seam.masks.last, duckedResident)
        var ducked = await controller.isDucked
        XCTAssertTrue(ducked)

        seam.clearCalls()
        await controller.restore()
        XCTAssertEqual(seam.calls, ["setCategory"], "the duck ends by dropping the option, not by deactivating")
        XCTAssertEqual(seam.masks.last, resident)
        ducked = await controller.isDucked
        XCTAssertFalse(ducked)

        XCTAssertEqual(engine.pauseCount, 0, "the microphone tap never stops")
        XCTAssertEqual(engine.startCount, 1, "and the engine is never restarted")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(plays.value, 1, "the single guarded play from startEngine, none from a cycle")
    }
}
