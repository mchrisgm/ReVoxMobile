import XCTest
import SwiftUI
import ReVoxCore
@testable import ReVoxMobile

/// Hosts each screen in a `UIHostingController` and lays it out once: SwiftUI has no unit-test renderer, so this
/// proves the views build against their view models and do not trap on first layout.
@MainActor
final class ScreenHostingTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var store: SettingsStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxScreens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func makeModelsViewModel(pipelineRunning: Bool = false) -> ModelsViewModel {
        let steps = FakeInstallSteps()
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout),
                                       verifiedLoads: VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxScreens-\(UUID().uuidString)")!))
        let manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { pipelineRunning }, availableBytes: { 50_000_000_000 }, host: FakeInstallHost())
        return ModelsViewModel(manager: manager, settings: store, deviceInfo: DeviceInfo(physicalMemoryBytes: 6 * 1_073_741_824), isPipelineRunning: { pipelineRunning })
    }

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    func testModelsViewHostsWithEveryRowState() {
        host(NavigationStack { ModelsView(model: makeModelsViewModel()) })
        host(NavigationStack { ModelsView(model: makeModelsViewModel(pipelineRunning: true)) })
        for phase in [ModelDownloadPhase.idle, .listing, .downloading(completedFiles: 1, totalFiles: 6), .compiling("x"), .verifying, .installed, .paused, .failed("boom")] {
            let row = ModelRow(id: .small, name: "small", sizeText: "≈ 487 MB", isRecommended: true, isSuitable: true, warning: nil, note: nil,
                               state: ModelDownloadState(phase: phase, fraction: 0.4, bytesExpected: 1), isSelected: false)
            host(List { ModelRowView(row: row, onDownload: {}, onCancel: {}, onSelect: {}) })
        }
    }

    func testSettingsViewHosts() {
        let settingsModel = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel()) })
        settingsModel.latencyMode = .fast
        settingsModel.language = "es"
        settingsModel.ducking = false
        settingsModel.voiceVolume = 0.3
        host(NavigationStack { SettingsView(model: settingsModel, models: makeModelsViewModel()) })
    }

    func testLiveViewHostsInEveryState() async {
        let mute = PlaybackMute()
        let pipeline = FakeLivePipeline()
        let live = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in true },
                                 supplier: { _, _ in pipeline })
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel()) })   // empty state
        await live.start()
        await waitUntil { live.state == .running }
        pipeline.emit(.entry(TranscriptEntry(timestamp: Date(), language: "es", original: "", english: "hola")))
        pipeline.emit(.lag)
        await waitUntil { live.rows.count == 2 }
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel()) })   // running with rows and the badge
        pipeline.emit(.error("boom"))
        await waitUntil { live.state == .error }
        host(NavigationStack { LiveView(model: live, models: makeModelsViewModel()) })   // error banner

        let denied = LiveViewModel(settings: store, mute: mute, permission: .fixed(.denied), modelReady: { _ in true }, supplier: { _, _ in pipeline })
        await denied.start()
        host(NavigationStack { LiveView(model: denied, models: makeModelsViewModel()) })  // permission banner

        let noModel = LiveViewModel(settings: store, mute: mute, permission: .fixed(.granted), modelReady: { _ in false }, supplier: { _, _ in pipeline })
        await noModel.start()
        host(NavigationStack { LiveView(model: noModel, models: makeModelsViewModel()) })  // download prompt
        XCTAssertEqual(LiveView.availableSources, [.microphone])
    }

    func testRootViewHostsAllThreeTabs() throws {
        let environment = try AppEnvironment.testing(root: root.appendingPathComponent("env", isDirectory: true))
        host(RootView(environment: environment))
    }
}
