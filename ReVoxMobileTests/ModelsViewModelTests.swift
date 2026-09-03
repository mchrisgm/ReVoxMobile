import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class ModelsViewModelTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var steps: FakeInstallSteps!
    private var host: FakeInstallHost!
    private var store: SettingsStore!
    private var pipelineRunning = false

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxModelsVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        steps = FakeInstallSteps()
        host = FakeInstallHost()
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        pipelineRunning = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(memoryGiB: UInt64 = 6, availableBytes: Int64? = 50_000_000_000) -> ModelsViewModel {
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout),
                                       verifiedLoads: VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxModelsVM-\(UUID().uuidString)")!))
        let manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { [unowned self] in self.pipelineRunning },
                                   availableBytes: { availableBytes }, host: host)
        return ModelsViewModel(manager: manager, settings: store, deviceInfo: DeviceInfo(physicalMemoryBytes: memoryGiB * 1_073_741_824),
                               isPipelineRunning: { [unowned self] in self.pipelineRunning })
    }

    func testRowsFollowCatalogOrderWithRecommendationAndSuitability() {
        let sixGiB = makeModel(memoryGiB: 6)
        XCTAssertEqual(sixGiB.rows.map(\.id), [.tiny, .base, .small, .medium, .largeV3])
        XCTAssertEqual(sixGiB.rows.map(\.name), ["tiny", "base", "small", "medium", "large-v3"])
        XCTAssertEqual(sixGiB.rows.filter(\.isRecommended).map(\.id), [.small])
        XCTAssertEqual(sixGiB.rows.filter { !$0.isSuitable }.map(\.id), [.largeV3])
        XCTAssertNil(sixGiB.rows[3].warning, "no heat warning below 8 GB")
        XCTAssertEqual(sixGiB.rows[4].note, "Compressed weights Argmax ships for iPhone")
        XCTAssertEqual(sixGiB.rows[2].sizeText, "≈ 487 MB")
        XCTAssertEqual(sixGiB.rows[2].isSelected, true, "default model small is selected")

        let eightGiB = makeModel(memoryGiB: 8)
        XCTAssertEqual(eightGiB.rows.filter { !$0.isSuitable }.count, 0)
        XCTAssertEqual(eightGiB.rows[3].warning, DeviceRecommendation.heatWarning)
        XCTAssertEqual(eightGiB.rows[4].warning, DeviceRecommendation.heatWarning)

        let threeGiB = makeModel(memoryGiB: 3)
        XCTAssertEqual(threeGiB.rows.filter(\.isRecommended).map(\.id), [.base])
    }

    func testSizeText() {
        XCTAssertEqual(ModelsViewModel.sizeText(76_600_000), "≈ 77 MB")
        XCTAssertEqual(ModelsViewModel.sizeText(486_500_000), "≈ 487 MB")
        XCTAssertEqual(ModelsViewModel.sizeText(948_000_000), "≈ 948 MB")
        XCTAssertEqual(ModelsViewModel.sizeText(1_528_000_000), "≈ 1.5 GB")
        XCTAssertEqual(ModelsViewModel.sizeText(950_000), "≈ 1 MB")
        XCTAssertEqual(ModelsViewModel.confirmDeleteTitle(.small), "Delete small (≈ 487 MB)?")
        XCTAssertEqual(ModelsViewModel.confirmDeleteMessage, "You can download it again later.")
    }

    func testVADRowAndPhaseTexts() {
        let model = makeModel()
        XCTAssertEqual(model.vadRow.name, "Voice detector")
        XCTAssertEqual(model.vadRow.sizeText, "≈ 1 MB")
        XCTAssertEqual(model.vadRow.state.phase, .idle)
        XCTAssertEqual(ModelsViewModel.phaseText(.idle), "Not downloaded")
        XCTAssertEqual(ModelsViewModel.phaseText(.downloading(completedFiles: 2, totalFiles: 6)), "Downloading 2 of 6 files")
        XCTAssertEqual(ModelsViewModel.phaseText(.downloading(completedFiles: nil, totalFiles: nil)), "Downloading")
        XCTAssertEqual(ModelsViewModel.phaseText(.compiling("x")), "Preparing x")
        XCTAssertEqual(ModelsViewModel.phaseText(.verifying), "Verifying")
        XCTAssertEqual(ModelsViewModel.phaseText(.paused), "Paused")
        XCTAssertEqual(ModelsViewModel.phaseText(.failed("boom")), "Failed: boom")
        XCTAssertEqual(ModelsViewModel.phaseText(.installed), "Installed")
    }

    func testDownloadUpdatesTheRowAndTheFooterThenInstalls() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download(.tiny)
        await waitUntil { model.rows[0].state.phase == .downloading(completedFiles: nil, totalFiles: nil) }
        XCTAssertEqual(model.footerText, ModelsViewModel.keepOpenText)
        XCTAssertNotNil(model.rows[0].state.fraction, "determinate from the first callback")
        steps.holdDownloads = false
        await waitUntil { model.rows[0].state.phase == .installed && model.vadRow.state.phase == .installed }
        XCTAssertNil(model.footerText)
    }

    func testCancelReturnsToNotDownloaded() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download(.base)
        await waitUntil { model.rows[1].state.phase.isActive }
        model.cancel(.base)
        await waitUntil { model.rows[1].state.phase == .idle }
    }

    func testSelectInstalledModelUpdatesSettingsAndOnlyInstalledModelsSelect() throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        let model = makeModel()
        model.select(.base)
        XCTAssertEqual(store.settings.model, "base")
        XCTAssertEqual(model.selectedModel, .base)
        model.select(.medium)
        XCTAssertEqual(store.settings.model, "base", "not installed → ignored")
    }

    func testDeleteHiddenWhileRunningAndFooterExplains() throws {
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let model = makeModel()
        XCTAssertTrue(model.canDelete)
        pipelineRunning = true
        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.footerText, ModelsViewModel.stopToDeleteText)
        XCTAssertThrowsError(try model.delete(.small))
    }

    func testDeletingTheSelectedModelSwitchesToTheSmallestInstalledOne() throws {
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        let model = makeModel()
        try model.delete(.small)
        XCTAssertEqual(store.settings.model, "tiny")
        XCTAssertEqual(model.rows[2].state.phase, .idle)
        try model.delete(.tiny)
        XCTAssertEqual(store.settings.model, "tiny", "no installed model left: the setting stays and Live shows the prompt")
    }

    func testLowStorageRefusalProducesAnAlertAndNoDownload() async {
        let model = makeModel(availableBytes: 100_000_000)
        model.download(.medium)
        XCTAssertEqual(model.lowStorageAlert, "Not enough space: needs about 2.1 GB, 0.1 GB free")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(steps.variantDownloads, [])
        XCTAssertEqual(model.rows[3].state.phase, .idle)
    }

    func testLowRemainingSpaceWarnsButDownloads() async {
        let model = makeModel(availableBytes: 1_000_000_000)
        model.download(.tiny)
        XCTAssertNil(model.lowStorageAlert)
        XCTAssertEqual(model.lowStorageWarning, "Only 0.9 GB will remain after this download")
        await waitUntil { model.rows[0].state.phase == .installed }
    }

    func testBackgroundExpirationPausesAndForegroundResumes() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download(.tiny)
        await waitUntil { model.rows[0].state.phase.isActive }
        host.expireAll()
        await waitUntil("paused row") { model.rows[0].state.phase == .paused }
        XCTAssertEqual(model.footerText, ModelsViewModel.keepOpenText)
        steps.holdDownloads = false
        model.applicationDidBecomeActive()
        await waitUntil("resumed") { model.rows[0].state.phase == .installed }
    }
}
