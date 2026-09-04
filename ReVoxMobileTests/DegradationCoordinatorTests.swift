import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class DegradationCoordinatorTests: XCTestCase {
    private func makeCoordinator(selected: WhisperModelID = .small,
                                 installed: [WhisperModelID] = [.tiny, .base, .small],
                                 usesPocketTTS: Bool = true,
                                 log: LockedBox<[String]>) -> (DegradationCoordinator, AsyncStream<DeviceSignal>.Continuation) {
        let (stream, continuation) = AsyncStream<DeviceSignal>.makeStream(bufferingPolicy: .unbounded)
        let coordinator = DegradationCoordinator(
            signals: stream,
            selectedModel: { selected },
            installedModels: { installed },
            usesPocketTTS: { usesPocketTTS },
            actions: DegradationActions(
                unloadPocketTTS: { log.mutate { $0.append("unloadPocketTTS") } },
                useModel: { model, restartRunning in log.mutate { $0.append("useModel(\(model.rawValue), restart: \(restartRunning))") } },
                pause: { log.mutate { $0.append("pause") } },
                resume: { log.mutate { $0.append("resume") } },
                showBanner: { text in log.mutate { $0.append("banner(\(text))") } }
            )
        )
        return (coordinator, continuation)
    }

    func testStreamedSignalsAreAppliedInOrder() async {
        let log = LockedBox<[String]>([])
        let (coordinator, continuation) = makeCoordinator(log: log)
        coordinator.start()

        continuation.yield(.memoryWarning)
        await waitUntil("pocket-tts dropped") { log.value.count == 2 }
        continuation.yield(.thermalState(.critical))
        await waitUntil("paused") { log.value.count == 4 }
        continuation.yield(.thermalState(.nominal))
        await waitUntil("resumed") { log.value.count == 6 }
        coordinator.stop()

        XCTAssertEqual(log.value, [
            "unloadPocketTTS",
            "banner(Memory low: switched to the system voice)",
            "pause",
            "banner(iPhone is hot: translation paused)",
            "resume",
            "banner(iPhone cooled down: translation resumed)",
        ])
        XCTAssertTrue(coordinator.state.pocketTTSDropped)
        XCTAssertFalse(coordinator.state.isPausedForHeat)
        XCTAssertEqual(coordinator.appliedEffects.count, 6)
    }

    func testMemoryWarningWithTheSystemVoiceShrinksTheModel() async {
        let log = LockedBox<[String]>([])
        let (coordinator, _) = makeCoordinator(usesPocketTTS: false, log: log)
        await coordinator.handle(.memoryWarning)
        XCTAssertEqual(log.value, ["useModel(base, restart: true)", "banner(Memory low: switched to base)"])
        XCTAssertEqual(coordinator.state.reducedModel, .base)
    }

    func testSeriousHeatChangesTheModelForTheNextSessionOnly() async {
        let log = LockedBox<[String]>([])
        let (coordinator, _) = makeCoordinator(log: log)
        await coordinator.handle(.thermalState(.serious))
        XCTAssertEqual(log.value, ["useModel(base, restart: false)", "banner(iPhone is hot: translation reduced)"],
                       "§9 prefers the smaller model for new sessions; the running one is not torn down on a hot device")
    }

    /// The speaker status is read live, so the closure answers false the moment the speaker actually unloaded
    /// (the assembly's own observer is gone — this coordinator owns the warning now). The §9 ordering must still be
    /// pocket-tts first, model second.
    func testTheLiveSpeakerStatusStillGivesTheSpecOrdering() async {
        let log = LockedBox<[String]>([])
        let usesPocketTTS = LockedBox<Bool>(true)
        let (stream, _) = AsyncStream<DeviceSignal>.makeStream(bufferingPolicy: .unbounded)
        let coordinator = DegradationCoordinator(
            signals: stream,
            selectedModel: { .small },
            installedModels: { [.tiny, .base, .small] },
            usesPocketTTS: { usesPocketTTS.value },
            actions: DegradationActions(
                unloadPocketTTS: {
                    usesPocketTTS.mutate { $0 = false }   // what EffectiveSpeaker.unloadPocketTTS() does to the status
                    log.mutate { $0.append("unloadPocketTTS") }
                },
                useModel: { model, restartRunning in log.mutate { $0.append("useModel(\(model.rawValue), restart: \(restartRunning))") } },
                pause: { log.mutate { $0.append("pause") } },
                resume: { log.mutate { $0.append("resume") } },
                showBanner: { text in log.mutate { $0.append("banner(\(text))") } }
            )
        )

        await coordinator.handle(.memoryWarning)
        await coordinator.handle(.memoryWarning)
        XCTAssertEqual(log.value, [
            "unloadPocketTTS",
            "banner(Memory low: switched to the system voice)",
            "useModel(base, restart: true)",
            "banner(Memory low: switched to base)",
        ])
        XCTAssertTrue(coordinator.state.pocketTTSDropped)
        XCTAssertEqual(coordinator.state.reducedModel, .base)
    }

    func testOnlyASpentWhisperRetryAfterAMemoryWarningShrinksTheModel() async {
        let log = LockedBox<[String]>([])
        let (coordinator, _) = makeCoordinator(usesPocketTTS: false, log: log)
        await coordinator.whisperFailed()
        XCTAssertTrue(log.value.isEmpty, "no memory warning yet: a Whisper failure is the translator's retry, not a degradation")

        await coordinator.handle(.memoryWarning)
        XCTAssertEqual(coordinator.state.reducedModel, .base)

        let handler = coordinator.recoveryEventHandler()
        handler(.reloaded)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.state.reducedModel, .base, "a successful reload is not an eviction")

        handler(.gaveUp("transcribe failed twice"))
        await waitUntil("stepped down again") { coordinator.state.reducedModel == .tiny }
        XCTAssertEqual(Array(log.value.suffix(2)), ["useModel(tiny, restart: true)", "banner(Memory low: switched to tiny)"])
    }

    func testASignalWithNoEffectsTouchesNothing() async {
        let log = LockedBox<[String]>([])
        let (coordinator, _) = makeCoordinator(selected: .tiny, installed: [.tiny], usesPocketTTS: false, log: log)
        await coordinator.handle(.memoryWarning)
        await coordinator.handle(.lowPowerMode(true))
        XCTAssertTrue(log.value.isEmpty)
        XCTAssertTrue(coordinator.appliedEffects.isEmpty)
        XCTAssertEqual(coordinator.state.memoryWarnings, 1)
    }
}
