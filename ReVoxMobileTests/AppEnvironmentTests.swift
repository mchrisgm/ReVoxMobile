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
    }

    func testDidBecomeActiveForwardsToTheModelManager() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAppEnv-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = try AppEnvironment.testing(root: root)
        environment.applicationDidBecomeActive()   // no paused downloads: a no-op that must not trap
        XCTAssertEqual(environment.modelManager.pausedKinds, [])
    }
}
