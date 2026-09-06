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
    /// The manager behind the last `makeModel()`, for the tests that drive it directly (release S3).
    private var manager: ModelManager!
    private var pipelineRunning = false
    private var benchmarkRunning = false

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxModelsVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        steps = FakeInstallSteps()
        host = FakeInstallHost()
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        pipelineRunning = false
        benchmarkRunning = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(memoryGiB: UInt64 = 6, availableBytes: Int64? = 50_000_000_000,
                           fileRecord: InstalledFileRecord = InstalledFileRecord(defaults: UserDefaults(suiteName: "ReVoxFileRecord-\(UUID().uuidString)")!),
                           benchmarks: BenchmarkStore? = nil) -> ModelsViewModel {
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout),
                                       verifiedLoads: VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxModelsVM-\(UUID().uuidString)")!))
        let manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { [unowned self] in self.pipelineRunning },
                                   availableBytes: { availableBytes }, host: host, fileRecord: fileRecord)
        self.manager = manager
        return ModelsViewModel(manager: manager, settings: store, deviceInfo: DeviceInfo(physicalMemoryBytes: memoryGiB * 1_073_741_824),
                               isPipelineRunning: { [unowned self] in self.pipelineRunning },
                               benchmarks: benchmarks, isBenchmarkRunning: { [unowned self] in self.benchmarkRunning })
    }

    /// M11: a store over a temporary folder of its own, seeded with one run for this test's "iPhone". Its own
    /// folder: a store reads every run in its folder at init, so two stores in one test sharing a folder would
    /// see each other's runs (CI run 123: the "older library" store found the "other phone" store's current run).
    private func benchmarkStore(_ run: BenchmarkRun?, device: String = "iPhone17,1") throws -> BenchmarkStore {
        let store = BenchmarkStore(directory: root.appendingPathComponent("Benchmarks-\(UUID().uuidString)", isDirectory: true),
                                   host: BenchmarkHost(device: device, iOSVersion: "26.0.1", memoryTierGB: 8))
        if let run { try store.save(run) }
        return store
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

    // MARK: Release S3: a first download becomes the selection

    /// Fails against the old view model: the selection stayed at the default small, which was never downloaded,
    /// so Live kept reading "No model installed" beside the only model on the iPhone.
    func testAFinishedDownloadIsSelectedWhenTheSelectedModelIsNotInstalled() async {
        let model = makeModel(memoryGiB: 3)                 // recommends base; the selection still defaults to small
        XCTAssertEqual(model.rows.filter(\.isRecommended).map(\.id), [.base])
        XCTAssertEqual(model.selectedModel, .small)
        XCTAssertEqual(model.rows[2].state.phase, .idle, "small is selected but not on disk")
        model.download(.base)
        await waitUntil("base installed") { model.rows[1].state.phase == .installed }
        XCTAssertEqual(store.settings.model, "base")
        XCTAssertEqual(model.selectedModel, .base)
        XCTAssertTrue(model.rows[1].isSelected)
        XCTAssertFalse(model.rows[2].isSelected)
    }

    /// The guard half of the rule; it passes against the old code too and keeps the rule from growing.
    func testAFinishedDownloadNeverOverridesAnInstalledSelection() async throws {
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let model = makeModel()
        XCTAssertEqual(model.selectedModel, .small)
        XCTAssertEqual(model.rows[2].state.phase, .installed)
        model.download(.tiny)
        await waitUntil("tiny installed") { model.rows[0].state.phase == .installed }
        XCTAssertEqual(store.settings.model, "small", "small is installed and selected, so tiny is not adopted")
        XCTAssertFalse(model.rows[0].isSelected)
        XCTAssertTrue(model.rows[2].isSelected)
    }

    /// After the last model was deleted the setting keeps naming it (Live shows the prompt); the next download
    /// is then the only model on disk and becomes the selection.
    func testTheNextDownloadAfterTheLastDeleteBecomesTheSelection() async throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        let model = makeModel()
        model.select(.tiny)
        try model.delete(.tiny)
        XCTAssertEqual(store.settings.model, "tiny", "nothing installed: the setting stays")
        model.download(.base)
        await waitUntil("base installed") { model.rows[1].state.phase == .installed }
        XCTAssertEqual(store.settings.model, "base")
    }

    func testWhisperInstalledAppliesTheRuleDirectly() throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        let model = makeModel()
        model.whisperInstalled(.base)
        XCTAssertEqual(store.settings.model, "base", "the default small is not installed, so base is adopted")
        model.whisperInstalled(.tiny)
        XCTAssertEqual(store.settings.model, "base", "base is installed and selected: left alone")
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

    // MARK: Upstream-change caption (M7 Task 90)

    func testVADRowShowsTheUpstreamChangeCaptionOnlyWhenFlagged() throws {
        try FakeInstallSteps.fabricateVAD(in: layout)
        let model = makeModel()
        XCTAssertNil(model.vadRow.noticeText, "nothing was recorded for a hand-fabricated layout, so nothing is compared")

        let record = InstalledFileRecord(defaults: UserDefaults(suiteName: "ReVoxVADNotice-\(UUID().uuidString)")!)
        record.record(.vad, files: ["stale-file": 1])
        let flagged = makeModel(fileRecord: record)
        XCTAssertEqual(flagged.vadRow.noticeText, ModelManager.upstreamChangedText)
    }

    /// M10: verifying a download is a full WhisperKit load, so a download is refused while a session runs (§9).
    func testDownloadRefusedWhileRunningAndAllowedWhenIdle() async {
        let model = makeModel()
        pipelineRunning = true
        XCTAssertFalse(model.canDownload)
        model.download(.tiny)
        XCTAssertEqual(model.downloadRefusedAlert, "Stop translation to download models")
        XCTAssertNil(model.lowStorageAlert)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(steps.variantDownloads, [])
        XCTAssertEqual(model.rows[0].state.phase, .idle)

        pipelineRunning = false
        model.downloadRefusedAlert = nil
        XCTAssertTrue(model.canDownload)
        model.download(.tiny)
        XCTAssertNil(model.downloadRefusedAlert)
        await waitUntil { model.rows[0].state.phase == .installed }
    }

    // MARK: M11: the measured recommendation

    func testMeasuredRecommendationMovesTheCapsuleAndNotesTheDate() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let run = BenchmarkRun.sample()   // tiny WER 0.25, small WER 0.125, both keep up; medium skipped
        let model = makeModel(memoryGiB: 8, benchmarks: try benchmarkStore(run))
        XCTAssertEqual(model.rows.filter(\.isRecommended).map(\.id), [.small])
        XCTAssertEqual(model.measuredRecommendation, .small)
        XCTAssertEqual(model.rows[2].measuredNote, ModelsViewModel.measuredNoteText(date: run.date))
        XCTAssertNil(model.rows[0].measuredNote, "only the recommended row carries the note")
        XCTAssertEqual(model.benchmarkFooterText, ModelsViewModel.measuredFooterText(date: run.date))
        XCTAssertEqual(model.rows[3].warning, DeviceRecommendation.heatWarning, "warnings stay memory-derived")
        XCTAssertEqual(model.rows.filter { !$0.isSuitable }.count, 0)
    }

    func testMeasuredRecommendationNeedsTheModelToBeInstalled() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)   // small is measured but not on disk
        let run = BenchmarkRun.sample()
        let model = makeModel(memoryGiB: 8, benchmarks: try benchmarkStore(run))
        XCTAssertEqual(model.rows.filter(\.isRecommended).map(\.id), [.tiny])
        XCTAssertEqual(model.measuredResults.map(\.model), [.tiny])
        XCTAssertEqual(model.rows[0].measuredNote, ModelsViewModel.measuredNoteText(date: run.date))
        XCTAssertNil(model.rows[2].measuredNote)
    }

    func testStaleLibraryVersionAndOtherHardwareAreIgnored() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let otherPhone = makeModel(memoryGiB: 8, benchmarks: try benchmarkStore(.sample(), device: "iPhone14,5"))
        XCTAssertEqual(otherPhone.rows.filter(\.isRecommended).map(\.id), [.small], "the memory tier's small, not a measured pick")
        XCTAssertNil(otherPhone.measuredRecommendation)
        XCTAssertNil(otherPhone.rows[2].measuredNote)
        XCTAssertEqual(otherPhone.benchmarkFooterText, "Recommended by memory size. Run the benchmark to measure this iPhone.")

        let olderLibrary = makeModel(memoryGiB: 8, benchmarks: try benchmarkStore(.sample(whisperKitVersion: "0.9.0")))
        XCTAssertNil(olderLibrary.measuredRecommendation)
        XCTAssertEqual(olderLibrary.benchmarkFooterText, ModelsViewModel.notMeasuredFooterText)
    }

    func testNothingQualifyingFallsBackToMemoryWithoutANote() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        let slow = BenchmarkRun(date: Date(timeIntervalSince1970: 1_700_000_000), device: "iPhone17,1", iOSVersion: "26.0.1", memoryTierGB: 4,
                                whisperKitVersion: LibraryVersions.whisperKit, sentence: BenchmarkSentences.spanish,
                                results: [ModelBenchmarkResult(model: .tiny, loadSeconds: 1, firstSeconds: 3, steadySeconds: 3, audioSeconds: 2,
                                                               wordErrorRate: 0, residentBeforeMB: 100, peakDeltaMB: 50, thermalState: "fair")])
        let model = makeModel(memoryGiB: 4, benchmarks: try benchmarkStore(slow))
        XCTAssertEqual(model.rows.filter(\.isRecommended).map(\.id), [.small], "the 4 GB tier's small")
        XCTAssertNil(model.measuredRecommendation)
        XCTAssertNil(model.rows[0].measuredNote)
        XCTAssertEqual(model.benchmarkFooterText, ModelsViewModel.notMeasuredFooterText)
    }

    func testNoteTexts() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ModelsViewModel.measuredNoteText(date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: utc), "Measured on this iPhone on 14 November 2023")
        XCTAssertEqual(ModelsViewModel.measuredFooterText(date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: utc), "Recommendation measured on this iPhone on 14 November 2023")
        XCTAssertEqual(ModelsViewModel.notMeasuredFooterText, "Recommended by memory size. Run the benchmark to measure this iPhone.")
        XCTAssertEqual(ModelsViewModel.finishBenchmarkText, "Finish or cancel the benchmark first")
    }

    /// M11: a download's verifying load, or a delete, beside the model being timed is what §9 forbids.
    func testDownloadAndDeleteAreRefusedWhileABenchmarkRuns() async throws {
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        let model = makeModel()
        benchmarkRunning = true
        XCTAssertFalse(model.canDownload)
        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.footerText, "Finish or cancel the benchmark first")
        model.download(.tiny)
        XCTAssertEqual(model.downloadRefusedAlert, "Finish or cancel the benchmark first")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(steps.variantDownloads, [])
        model.deleteConfirmed(.base)
        XCTAssertEqual(model.deleteFailureAlert, "Finish or cancel the benchmark first")
        XCTAssertEqual(model.rows[1].state.phase, .installed, "the files stay")

        benchmarkRunning = false
        model.downloadRefusedAlert = nil
        XCTAssertTrue(model.canDownload)
        XCTAssertNil(model.footerText)
        model.deleteConfirmed(.base)
        XCTAssertNil(model.deleteFailureAlert)
        XCTAssertEqual(model.rows[1].state.phase, .idle)
    }
}
