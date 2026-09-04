import XCTest
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
        XCTAssertEqual(environment.voices.offeredVoices, ["alba", "azelma", "cosette", "javert"])
        XCTAssertFalse(environment.voices.isPocketTTSInstalled)
        XCTAssertEqual(environment.broadcast.attachState, .noRing)
        XCTAssertFalse(environment.broadcastCapture.isRunning)
        XCTAssertNotNil(environment.broadcast.onBroadcastLive, "the foreground auto-start is wired")
        XCTAssertEqual(environment.live.broadcastStatusText, nil, "default source is the microphone")
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
}
