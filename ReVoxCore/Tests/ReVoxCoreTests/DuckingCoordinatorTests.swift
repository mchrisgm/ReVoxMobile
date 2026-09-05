import XCTest
@testable import ReVoxCore

/// `tests/pipeline/test_ducking.py` plus the iOS hold and the async-restore re-entrancy, with a manual-resume sleep.
final class DuckingCoordinatorTests: XCTestCase {
    private func makeCoordinator(enabled: Bool = true, holdRestore: Bool = false) -> (DuckingCoordinator, FakeDucker, FakeSleep) {
        let ducker = FakeDucker(holdRestore: holdRestore)
        let sleep = FakeSleep()
        let coordinator = DuckingCoordinator(ducker: ducker, enabled: enabled, sleep: sleep.sleep)
        return (coordinator, ducker, sleep)
    }

    func testDefaultHoldIs250ms() async {
        XCTAssertEqual(DuckingCoordinator.defaultHoldNanoseconds, 250_000_000)
        let (coordinator, _, sleep) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        let requested = await eventually { sleep.requested == [250_000_000] }
        XCTAssertTrue(requested)
    }

    func testDuckTwiceIsNoOp() async {
        let (coordinator, ducker, _) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(true)
        let ducked = await ducker.ducked
        XCTAssertEqual(ducked, 1)
        let isDucked = await coordinator.isDucked
        XCTAssertTrue(isDucked)
    }

    func testRestoreNowForwardsEveryCall() async {
        let (coordinator, ducker, _) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.restoreNow()
        let duckedAfterFirst = await coordinator.isDucked
        XCTAssertFalse(duckedAfterFirst)
        await coordinator.restoreNow()
        let restored = await ducker.restored
        XCTAssertEqual(restored, 2)                           // idempotence lives inside the Ducker
    }

    func testDisabledNeverCallsDucker() async {
        let (coordinator, ducker, sleep) = makeCoordinator(enabled: false)
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        await coordinator.restoreNow()
        let ducked = await ducker.ducked
        let restored = await ducker.restored
        XCTAssertEqual(ducked, 0)
        XCTAssertEqual(restored, 0)
        XCTAssertTrue(sleep.requested.isEmpty)
    }

    func testHoldDelaysRestore() async {
        let (coordinator, ducker, sleep) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        let pending = await eventually { sleep.pendingCount == 1 }
        XCTAssertTrue(pending)
        let restoredBefore = await ducker.restored
        XCTAssertEqual(restoredBefore, 0)                     // nothing until the hold elapses
        let stillDucked = await coordinator.isDucked
        XCTAssertTrue(stillDucked)
        sleep.resumeAll()
        let restored = await eventually { await ducker.restored == 1 }
        XCTAssertTrue(restored)
        let isDucked = await coordinator.isDucked
        XCTAssertFalse(isDucked)
    }

    func testRetriggerInsideHoldKeepsDucked() async {
        let (coordinator, ducker, sleep) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        let pending = await eventually { sleep.pendingCount == 1 }
        XCTAssertTrue(pending)
        await coordinator.speakingChanged(true)               // cancels the hold
        let cancelled = await eventually { sleep.pendingCount == 0 }
        XCTAssertTrue(cancelled)
        sleep.resumeAll()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let restored = await ducker.restored
        XCTAssertEqual(restored, 0)
        let ducked = await ducker.ducked
        XCTAssertEqual(ducked, 1)                             // no second duck either: still ducked
        let isDucked = await coordinator.isDucked
        XCTAssertTrue(isDucked)
    }

    func testSetEnabledFalseWhileDuckedRestores() async {
        let (coordinator, ducker, _) = makeCoordinator()
        await coordinator.speakingChanged(true)
        await coordinator.setEnabled(false)
        let restored = await ducker.restored
        XCTAssertEqual(restored, 1)
        await coordinator.restoreNow()
        await coordinator.speakingChanged(true)
        let ducked = await ducker.ducked
        let restoredAfter = await ducker.restored
        XCTAssertEqual(ducked, 1)
        XCTAssertEqual(restoredAfter, 1)                      // disabled: no further calls
    }

    func testTrueDuringRestoreReDucks() async {
        let (coordinator, ducker, sleep) = makeCoordinator(holdRestore: true)
        await coordinator.speakingChanged(true)
        let ducked = await ducker.ducked
        XCTAssertEqual(ducked, 1)

        await coordinator.speakingChanged(false)
        let pending = await eventually { sleep.pendingCount == 1 }
        XCTAssertTrue(pending)
        sleep.resumeAll()
        let restoreSuspended = await eventually { await ducker.suspendedCount == 1 }
        XCTAssertTrue(restoreSuspended)                       // restore() entered and suspended
        let duckedWhileRestoring = await coordinator.isDucked
        XCTAssertFalse(duckedWhileRestoring)                  // written before the await

        await coordinator.speakingChanged(true)               // clip N+1 while restore(N) is in flight
        let secondDuck = await ducker.ducked
        XCTAssertEqual(secondDuck, 2)
        let reDucked = await coordinator.isDucked
        XCTAssertTrue(reDucked)

        await ducker.resumeRestore()
        let firstRestoreDone = await eventually { await ducker.restored == 1 }
        XCTAssertTrue(firstRestoreDone)
        let staysDucked = await coordinator.isDucked
        XCTAssertTrue(staysDucked)                            // the coordinator does not touch isDucked when restore() returns

        await coordinator.speakingChanged(false)
        let secondHold = await eventually { sleep.pendingCount == 1 }
        XCTAssertTrue(secondHold)
        sleep.resumeAll()
        let secondRestore = await eventually { await ducker.suspendedCount == 1 }
        XCTAssertTrue(secondRestore)
        await ducker.resumeRestore()
        let allDone = await eventually { await ducker.restored == 2 }
        XCTAssertTrue(allDone)
        let order = await ducker.order
        XCTAssertEqual(order, ["duck", "restore", "duck", "restore"])
    }

    func testRestoreNowDuringSuspendedRestoreForwardsAgain() async {
        let (coordinator, ducker, sleep) = makeCoordinator(holdRestore: true)
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        _ = await eventually { sleep.pendingCount == 1 }
        sleep.resumeAll()
        let suspended = await eventually { await ducker.suspendedCount == 1 }
        XCTAssertTrue(suspended)

        let restoreNowTask = Task { await coordinator.restoreNow() }   // suspends inside the fake too
        let twoSuspended = await eventually { await ducker.suspendedCount == 2 }
        XCTAssertTrue(twoSuspended)
        let entered = await ducker.restoreEntered
        XCTAssertEqual(entered, 2)                            // forwarded a second time
        await ducker.resumeRestore()
        await restoreNowTask.value
        let restored = await eventually { await ducker.restored == 2 }
        XCTAssertTrue(restored)
        let isDucked = await coordinator.isDucked
        XCTAssertFalse(isDucked)
    }

    func testReEnablingDucksOnTheNextSpeakingEdge() async {
        let (coordinator, ducker, _) = makeCoordinator()
        await coordinator.setEnabled(false)
        await coordinator.speakingChanged(true)
        let duckedWhileOff = await ducker.ducked
        XCTAssertEqual(duckedWhileOff, 0)
        await coordinator.setEnabled(true)
        await coordinator.speakingChanged(true)
        let ducked = await ducker.ducked
        XCTAssertEqual(ducked, 1)
        let isDucked = await coordinator.isDucked
        XCTAssertTrue(isDucked)
    }

    func testAFalseEdgeWithoutADuckStartsNoHold() async {
        let (coordinator, ducker, sleep) = makeCoordinator()
        await coordinator.speakingChanged(false)
        XCTAssertTrue(sleep.requested.isEmpty)
        let restored = await ducker.restored
        XCTAssertEqual(restored, 0)
        let isDucked = await coordinator.isDucked
        XCTAssertFalse(isDucked)
    }

    func testACustomHoldIsWhatIsSlept() async {
        let ducker = FakeDucker()
        let sleep = FakeSleep()
        let coordinator = DuckingCoordinator(ducker: ducker, enabled: true, hold: 1_000, sleep: sleep.sleep)
        await coordinator.speakingChanged(true)
        await coordinator.speakingChanged(false)
        // The fake records the duration before it registers the continuation, so wait for the sleeper to be
        // pending before resuming, or `resumeAll()` can run between the two and the hold never elapses (this test
        // failed once in six local runs when it waited on `requested` alone).
        let pending = await eventually { sleep.pendingCount == 1 }
        XCTAssertTrue(pending)
        XCTAssertEqual(sleep.requested, [1_000])
        sleep.resumeAll()
        let restored = await eventually { await ducker.restored == 1 }
        XCTAssertTrue(restored)
    }
}
