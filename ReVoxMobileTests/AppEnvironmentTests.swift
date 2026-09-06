import XCTest
import UIKit
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testTestingEnvironmentWiresEveryComponent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)

        XCTAssertTrue(environment.configuration.appGroup.hasPrefix("group."))
        XCTAssertEqual(environment.settings.settings, Settings())
        XCTAssertEqual(environment.layout.root.path, root.appendingPathComponent("Models").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: environment.layout.root.path))
        XCTAssertEqual(environment.models.rows.count, 5)
        XCTAssertEqual(environment.models.vadRow.state.phase, .idle)
        XCTAssertEqual(environment.live.state, .idle)
        XCTAssertEqual(environment.live.modelStatusText, "small · ready", "status before the readiness check ran")
        XCTAssertFalse(environment.mute.isMuted)
        XCTAssertEqual(environment.settingsModel.latencyMode, .balanced)
        XCTAssertEqual(environment.speakerStatus.text, SpeakerStatus.notDownloadedText)
        XCTAssertEqual(environment.voiceVolume.current, 1)
        XCTAssertEqual(environment.live.voiceStatusText, SpeakerStatus.notDownloadedText)
        XCTAssertTrue(environment.speakerAssembly.voiceVolume === environment.voiceVolume)
        XCTAssertEqual(environment.voices.offeredVoices, ["alba", "azelma", "javert"])
        XCTAssertFalse(environment.voices.isPocketTTSInstalled)
        // M11 §5: the Voices screen asks the same box the Models screen and Live's supplier do; nothing is running here.
        XCTAssertTrue(environment.voices.canDownload)
        XCTAssertEqual(environment.broadcast.attachState, .noRing)
        XCTAssertFalse(environment.broadcastCapture.isRunning)
        XCTAssertNotNil(environment.broadcast.onBroadcastLive, "the foreground auto-start is wired")
        XCTAssertEqual(environment.live.broadcastStatusText, nil, "default source is the microphone")
    }

    /// M11 §2: the word popover's services are one environment value built over the app's own speaker.
    func testWordLookupIsBuiltOverTheAppsWordSpeaker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertTrue(environment.wordLookup.speaker === environment.wordSpeaker, "one speaker for every popover")
        XCTAssertFalse(environment.wordSpeaker.isSpeaking)
        XCTAssertFalse(environment.wordSpeaker.isMicrophoneRunning, "idle: the Say button is live")
        XCTAssertFalse(environment.wordLookup.hasVoice("zz"), "the production lookup asks the system voices; no voice for an unknown code")
    }

    /// M11 §2: a word said through the speaker while the microphone is running would be heard and translated, so
    /// the Say button is disabled exactly then — not during an Other-apps run (the ring carries their audio, not
    /// the speaker) and not while idle.
    func testTheMicrophoneRuleBehindTheSayButton() {
        XCTAssertTrue(AppEnvironment.isMicrophoneRunning(state: .running, captureMode: .microphone))
        XCTAssertTrue(AppEnvironment.isMicrophoneRunning(state: .preparing, captureMode: .microphone), "the session is already open while preparing")
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .running, captureMode: .broadcast))
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .idle, captureMode: .microphone))
        XCTAssertFalse(AppEnvironment.isMicrophoneRunning(state: .error, captureMode: .microphone))
    }

    func testDidBecomeActiveForwardsToTheModelManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        environment.applicationDidBecomeActive()   // no paused downloads: a no-op that must not trap
        XCTAssertEqual(environment.modelManager.pausedKinds, [])
    }

    func testLaunchPrunesExportsOlderThanADay() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let old = exports.appendingPathComponent("2023-11-13_10-00-00.txt")
        try Data("old".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-2 * TranscriptExporter.maxAge)], ofItemAtPath: old.path)
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertEqual(environment.exporter.directory.standardizedFileURL, exports.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    // MARK: Model files changed → the cached pipeline is released (M7 Task 89)

    func testModelFilesChangedReleasesTheCachedLivePipeline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertNotNil(environment.modelManager.onModelFilesChanged, "the environment wires the delete hook")
        environment.modelManager.onModelFilesChanged?()
        await waitUntil("released") { environment.live.releasedPipelineCount == 1 }
    }

    // MARK: Degradation coordinator (M7 Task 94)

    func testEnvironmentOwnsAndStartsTheDegradationCoordinator() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        XCTAssertEqual(environment.degradation.state, DegradationState())
        XCTAssertTrue(environment.degradation.appliedEffects.isEmpty)

        // A step-down needs something smaller than the user's model (small) on disk; the environment starts empty.
        try FakeInstallSteps.fabricateWhisper(.tiny, in: environment.layout)
        try FakeInstallSteps.fabricateWhisper(.base, in: environment.layout)
        try FakeInstallSteps.fabricateWhisper(.small, in: environment.layout)
        environment.modelManager.refreshInstalledStates()
        XCTAssertEqual(environment.modelManager.installedWhisper, [.tiny, .base, .small])

        // `AppEnvironment.testing(root:)` builds `DeviceSignals()` on `NotificationCenter.default`, so the real
        // signal stream is drivable here: this fails if `degradation.start()` is dropped from the initializer.
        // The speaker is still `.systemNotDownloaded` (pocket-tts is not installed), so `usesPocketTTS` is false and
        // the first warning goes straight to the model row: [.useModel(.base, restartRunning: true), .banner(…)].
        // The banner is the last of the two effects, so waiting for it means both have been applied.
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        await waitUntil("the coordinator drained the signal") {
            environment.live.banner == .degraded(DegradationPolicy.memoryModelText(.base))
        }
        XCTAssertEqual(environment.degradation.state.memoryWarnings, 1)
        XCTAssertEqual(environment.degradation.state.reducedModel, .base)
        XCTAssertEqual(environment.live.activeModel, .base, "the useModel action reached the Live view model")
        XCTAssertEqual(environment.settings.settings.model, "small", "the user's choice is untouched")

        // This fails if `assembler.whisperRecovery.set(degradation.recoveryEventHandler())` is dropped.
        environment.assembler.whisperRecovery.send(.gaveUp("transcribe failed twice"))
        await waitUntil("the recovery sink reaches the coordinator") {
            environment.live.banner == .degraded(DegradationPolicy.memoryModelText(.tiny))
        }
        XCTAssertEqual(environment.degradation.state.reducedModel, .tiny)
        XCTAssertEqual(environment.live.activeModel, .tiny)
    }
}
