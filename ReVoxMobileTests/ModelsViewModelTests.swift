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
        await waitUntil("tiny and vad installed", details: { "tiny \(model.rows[0].state.phase), vad \(model.vadRow.state.phase)" }) { model.rows[0].state.phase == .installed && model.vadRow.state.phase == .installed }
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

    // MARK: Error surfaces (§8.8, M6)

    func testUserInitiatedFailureRaisesTheAlertOnce() async {
        let model = makeModel()
        steps.failVariantOnce = true
        model.download(.base)
        await waitUntil("failed row") { if case .failed = model.rows[1].state.phase { return true } else { return false } }
        guard case .failed(let message) = model.rows[1].state.phase else { return XCTFail("expected a failed row") }
        model.reconcileFailures()
        XCTAssertEqual(model.downloadFailureAlert, ModelsViewModel.downloadFailureText(name: "base", message: message))
        XCTAssertEqual(model.downloadFailureAlert, "Couldn't download base: \(message)")
        model.downloadFailureAlert = nil
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert, "the same failure never alerts twice; the row keeps Failed + Retry")
    }

    func testAutoResumeFailureStaysOnTheRowWithoutAnAlert() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download(.tiny)
        await waitUntil { model.rows[0].state.phase.isActive }
        host.expireAll()
        await waitUntil("paused row") { model.rows[0].state.phase == .paused }
        model.reconcileFailures()
        steps.failVariantOnce = true
        steps.holdDownloads = false
        model.applicationDidBecomeActive()   // the §6.9 auto-resume, not a user action
        await waitUntil("failed row") { if case .failed = model.rows[0].state.phase { return true } else { return false } }
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert)
        model.download(.tiny)                // Retry is a user action again
        await waitUntil { model.rows[0].state.phase == .installed }
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert, "a success clears the awaiting flag without an alert")
    }

    func testLowStorageRefusalAlertsBeforeAnythingStarts() {
        let model = makeModel(availableBytes: 100_000_000)
        model.download(.medium)
        XCTAssertEqual(model.lowStorageAlert, "Not enough space: needs about 2.1 GB, 0.1 GB free")
        XCTAssertEqual(model.rows[3].state.phase, .idle, "nothing was installed")
        XCTAssertEqual(steps.variantDownloads, [])
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert, "a refusal is not a download failure")
    }

    // MARK: Storage accounting (M7 Task 88)

    func testInstalledRowsShowMeasuredSizesAndTheFooterShowsTotalAndFree() throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        let weights = layout.whisperFolder(ModelCatalog.whisper(.base)).appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin")
        try FileManager.default.createDirectory(at: weights.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 3_000_000).write(to: weights)
        let model = makeModel(availableBytes: 12_300_000_000)
        XCTAssertEqual(model.rows[1].state.phase, .installed)
        XCTAssertFalse(model.rows[1].sizeText.hasPrefix("≈"), "installed rows show the measured size, not the catalog estimate")
        XCTAssertTrue(model.rows[1].sizeText.hasSuffix(" MB"))
        XCTAssertEqual(model.rows[2].sizeText, "≈ 487 MB", "rows that are not installed keep the catalog estimate")
        XCTAssertEqual(model.vadRow.sizeText, "≈ 1 MB", "the VAD is not installed in this layout")
        XCTAssertTrue(model.storageFooterText.hasPrefix("ReVox models: "))
        XCTAssertTrue(model.storageFooterText.hasSuffix(" · Free: 12.3 GB"))
        XCTAssertEqual(ModelsViewModel.measuredSizeText(3_000_000), "3 MB")
        XCTAssertEqual(ModelsViewModel.measuredSizeText(1_528_000_000), "1.5 GB")
        XCTAssertEqual(ModelsViewModel.measuredSizeText(512), "under 1 MB")
        XCTAssertEqual(ModelsViewModel.rowSizeText(catalogBytes: 486_500_000, state: .idle(bytesExpected: 486_500_000), measuredBytes: 10), "≈ 487 MB")
        let installed = ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: 486_500_000)
        XCTAssertEqual(ModelsViewModel.rowSizeText(catalogBytes: 486_500_000, state: installed, measuredBytes: 480_000_000), "480 MB")
    }

    func testFooterWithoutModelsOrFreeSpaceQuery() {
        let model = makeModel(availableBytes: nil)
        XCTAssertEqual(model.storageFooterText, ModelsViewModel.noModelsText)
        XCTAssertEqual(ModelsViewModel.noModelsText, "No models on this iPhone")
        XCTAssertEqual(ModelsViewModel.storageFooterText(for: ModelStorageUsage(bytesByKind: [.vad: 900_000], freeBytes: nil)), "ReVox models: under 1 MB")
        XCTAssertEqual(ModelsViewModel.storageFooterText(for: ModelStorageUsage(bytesByKind: [.vad: 900_000], freeBytes: 2_000_000_000)), "ReVox models: under 1 MB · Free: 2.0 GB")
    }

    // MARK: Delete only while idle (M7 Task 89)

    func testDeleteRefusedWhileRunningUsesItsOwnAlertAndKeepsTheFiles() throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        let model = makeModel()
        let folder = layout.whisperFolder(ModelCatalog.whisper(.base))
        pipelineRunning = true
        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.footerText, ModelsViewModel.stopToDeleteText)

        model.deleteConfirmed(.base)
        XCTAssertEqual(model.deleteFailureAlert, "Stop translation to delete models")
        XCTAssertNil(model.lowStorageAlert, "a refusal never lands in the Not enough space alert")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        pipelineRunning = false
        model.deleteConfirmed(.base)
        XCTAssertNil(model.deleteFailureAlert)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(model.rows[1].state.phase, .idle)
    }
}
