import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class ModelManagerTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReVoxModelLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: fabricated layouts

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    private func fabricateWhisper(_ id: WhisperModelID, tokenizer: Bool = true, coremldata: Bool = true) throws {
        let descriptor = ModelCatalog.whisper(id)
        let folder = layout.whisperFolder(descriptor)
        for bundle in ModelLayout.whisperBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(coremldata ? "coremldata.bin" : "model.mil"))
        }
        try touch(folder.appendingPathComponent("config.json"))
        if tokenizer {
            for file in ModelLayout.tokenizerFiles {
                try touch(layout.tokenizerFolder(descriptor).appendingPathComponent(file))
            }
        }
    }

    func testLayoutPathsFollowTheLibraries() {
        let small = ModelCatalog.whisper(.small)
        XCTAssertEqual(layout.whisperFolder(small).path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-small").path)
        XCTAssertEqual(layout.tokenizerFolder(small).path, root.appendingPathComponent("models/openai/whisper-small").path)
        XCTAssertEqual(layout.whisperSidecarCache(small).path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/openai_whisper-small").path)
        XCTAssertEqual(layout.vadRepoDirectory.path, root.appendingPathComponent("fluid/Models/silero-vad").path)
        XCTAssertEqual(layout.vadBundle.lastPathComponent, ModelCatalog.vad.subdirectory)
        XCTAssertEqual(layout.pocketTTSLanguageFolder.path, root.appendingPathComponent("fluid/Models/pocket-tts/v2.1/english").path)
    }

    func testWhisperInstalledWhenAllRequiredFilesPresent() throws {
        try fabricateWhisper(.small)
        XCTAssertTrue(layout.isWhisperInstalled(.small))
        XCTAssertEqual(layout.installedWhisperModels(), [.small])
    }

    func testWhisperNotInstalledWhenTokenizerMissing() throws {
        try fabricateWhisper(.base, tokenizer: false)
        XCTAssertFalse(layout.isWhisperInstalled(.base))
    }

    func testWhisperNotInstalledWhenCoremldataMissing() throws {
        try fabricateWhisper(.tiny, coremldata: false)
        XCTAssertFalse(layout.isWhisperInstalled(.tiny))
    }

    func testVADInstalledRequiresCoremldataAndNoPartials() throws {
        XCTAssertFalse(layout.isVADInstalled())
        try touch(layout.vadBundle.appendingPathComponent("coremldata.bin"))
        try touch(layout.vadBundle.appendingPathComponent("weights/weight.bin"))
        XCTAssertTrue(layout.isVADInstalled())
        try touch(layout.vadBundle.appendingPathComponent("weights/weight.bin.partial"))
        XCTAssertFalse(layout.isVADInstalled())
    }

    func testInstalledWhisperModelsKeepCatalogOrder() throws {
        try fabricateWhisper(.medium)
        try fabricateWhisper(.tiny)
        XCTAssertEqual(layout.installedWhisperModels(), [.tiny, .medium])
    }

    // MARK: ModelDownloadState bridging

    func testWhisperVariantProgressFillsTheFirst98Percent() {
        let progress = Progress(totalUnitCount: 4)
        progress.completedUnitCount = 2
        let state = ModelDownloadState.whisperVariant(progress, bytesExpected: 486_500_000)
        XCTAssertEqual(state.phase, .downloading(completedFiles: nil, totalFiles: nil))
        XCTAssertEqual(state.fraction!, 0.49, accuracy: 0.0001)
        XCTAssertEqual(state.bytesExpected, 486_500_000)
    }

    func testTokenizerProgressFillsTheLastTwoPercent() {
        let progress = Progress(totalUnitCount: 3)
        progress.completedUnitCount = 3
        let state = ModelDownloadState.whisperTokenizer(progress, bytesExpected: 1)
        XCTAssertEqual(state.fraction!, 1.0, accuracy: 0.0001)
        progress.completedUnitCount = 0
        XCTAssertEqual(ModelDownloadState.whisperTokenizer(progress, bytesExpected: 1).fraction!, 0.98, accuracy: 0.0001)
    }

    func testFluidAudioPhasesBridge() {
        let listing = ModelDownloadState.fluidAudio(fractionCompleted: 0, phase: .listing, bytesExpected: 950_000)
        XCTAssertEqual(listing.phase, .listing)
        XCTAssertEqual(listing.fraction, 0)
        let downloading = ModelDownloadState.fluidAudio(fractionCompleted: 0.4, phase: .downloading(completedFiles: 2, totalFiles: 6), bytesExpected: 950_000)
        XCTAssertEqual(downloading.phase, .downloading(completedFiles: 2, totalFiles: 6))
        XCTAssertEqual(downloading.fraction, 0.4)
        let compiling = ModelDownloadState.fluidAudio(fractionCompleted: 0.9, phase: .compiling("silero-vad-unified-v6.0.0.mlmodelc"), bytesExpected: 950_000)
        XCTAssertEqual(compiling.phase, .compiling("silero-vad-unified-v6.0.0.mlmodelc"))
    }

    func testIdleStateHasNoFraction() {
        let idle = ModelDownloadState.idle(bytesExpected: 76_600_000)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertNil(idle.fraction)
    }

    func testPartialScanFindsNestedPartials() throws {
        let folder = root.appendingPathComponent("scan", isDirectory: true)
        try touch(folder.appendingPathComponent("a/b/c.bin"))
        XCTAssertFalse(ModelLayout.containsPartialFiles(under: folder))
        try touch(folder.appendingPathComponent("a/b/d.bin.partial"))
        XCTAssertTrue(ModelLayout.containsPartialFiles(under: folder))
    }

    // MARK: The simulator's filesystem, isolated (run 33777714285)

    /// The VAD folder is creatable on its own.
    func testVADDirectoryIsCreatableInAFreshRoot() throws {
        try FileManager.default.createDirectory(at: layout.vadBundle, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.vadBundle.path))
    }

    /// And after a Whisper tree exists beside it. `models` (WhisperKit) and `Models` (FluidAudio) differ only
    /// by case, so this is where a case-insensitive volume would show itself.
    func testVADDirectoryIsCreatableAfterAWhisperTreeExists() throws {
        try fabricateWhisper(.tiny)
        let lower = layout.root.appendingPathComponent("models").path
        let upper = layout.root.appendingPathComponent(ModelLayout.fluidFolderName).path
        let state = "models=\(FileManager.default.fileExists(atPath: lower)) fluid=\(FileManager.default.fileExists(atPath: upper))"
        do {
            try FileManager.default.createDirectory(at: layout.vadBundle, withIntermediateDirectories: true)
        } catch {
            XCTFail("createDirectory(at:) after a whisper tree: \(error); \(state)")
        }
        do {
            try FakeInstallSteps.makeDirectory(layout.vadBundle)
        } catch {
            XCTFail("component-by-component after a whisper tree: \(error); \(state)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.vadBundle.path), state)
    }

    // MARK: ModelManager (Task 25)

    private var fakeSteps: FakeInstallSteps!
    private var defaults: UserDefaults!

    @MainActor
    private func makeManager(pipelineRunning: Bool = false, availableBytes: Int64? = 50_000_000_000) -> ModelManager {
        fakeSteps = FakeInstallSteps()
        defaults = UserDefaults(suiteName: "ReVoxModelManagerTests-\(UUID().uuidString)")
        let installer = ModelInstaller(layout: layout, steps: fakeSteps.steps(layout: layout), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        return ModelManager(layout: layout, installer: installer, isPipelineRunning: { pipelineRunning }, availableBytes: { availableBytes })
    }

    @MainActor
    func testInstallWhisperInstallsTheVADBundleWithIt() async {
        let manager = makeManager()
        XCTAssertEqual(manager.state(for: .whisper(.tiny)).phase, .idle)
        manager.install(.whisper(.tiny))
        await waitUntil("tiny installed") { manager.state(for: .whisper(.tiny)).phase == .installed }
        await waitUntil("vad installed", details: { "vad \(manager.state(for: .vad).phase), whisper \(manager.state(for: .whisper(.tiny)).phase), vadDownloads \(self.fakeSteps.vadDownloads), paused \(manager.pausedKinds)" }) { manager.state(for: .vad).phase == .installed }
        XCTAssertEqual(fakeSteps.variantDownloads, ["openai_whisper-tiny"])
        XCTAssertEqual(fakeSteps.vadDownloads, 1)
        XCTAssertEqual(manager.installedWhisper, [.tiny])
        XCTAssertTrue(manager.vadInstalled)
        XCTAssertFalse(manager.hasActiveDownload)
        let ready = await manager.isWhisperReady(.tiny)
        XCTAssertTrue(ready)
    }

    @MainActor
    func testSecondWhisperInstallDoesNotRedownloadTheVAD() async {
        let manager = makeManager()
        manager.install(.whisper(.tiny))
        await waitUntil("vad installed", details: { "vad \(manager.state(for: .vad).phase), vadDownloads \(self.fakeSteps.vadDownloads), paused \(manager.pausedKinds)" }) { manager.state(for: .vad).phase == .installed }
        manager.install(.whisper(.base))
        await waitUntil { manager.state(for: .whisper(.base)).phase == .installed }
        XCTAssertEqual(fakeSteps.vadDownloads, 1)
    }

    @MainActor
    func testCancelReturnsTheRowToIdleAndKeepsOfflineModeRestored() async {
        let manager = makeManager()
        fakeSteps.holdDownloads = true
        manager.install(.whisper(.small))
        await waitUntil { manager.state(for: .whisper(.small)).phase == .downloading(completedFiles: nil, totalFiles: nil) }
        XCTAssertTrue(manager.hasActiveDownload)
        manager.cancel(.whisper(.small))
        await waitUntil { manager.state(for: .whisper(.small)).phase == .idle }
        XCTAssertFalse(manager.hasActiveDownload)
        XCTAssertEqual(fakeSteps.offlineModeHistory.last, true)
        XCTAssertFalse(layout.isWhisperInstalled(.small))
    }

    @MainActor
    func testFailedInstallShowsFailedAndRetryInstallsAgain() async {
        let manager = makeManager()
        fakeSteps.failVariantOnce = true
        manager.install(.whisper(.base))
        await waitUntil { if case .failed = manager.state(for: .whisper(.base)).phase { return true } else { return false } }
        manager.install(.whisper(.base))
        await waitUntil { manager.state(for: .whisper(.base)).phase == .installed }
        XCTAssertEqual(fakeSteps.variantDownloads, ["openai_whisper-base", "openai_whisper-base"])
    }

    @MainActor
    func testDeleteRefusedWhileRunning() throws {
        let manager = makeManager(pipelineRunning: true)
        XCTAssertThrowsError(try manager.delete(.whisper(.small), activeModel: .small)) { error in
            XCTAssertEqual(error as? ModelManagerError, .pipelineRunning)
        }
    }

    @MainActor
    func testDeleteActiveModelSwitchesToTheSmallestInstalledModelOrNone() async throws {
        let manager = makeManager()
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        try FakeInstallSteps.fabricateWhisper(.base, in: layout)
        manager.refreshInstalledStates()
        XCTAssertEqual(manager.installedWhisper, [.base, .small])

        var switchedTo: [WhisperModelID?] = []
        manager.onActiveModelDeleted = { switchedTo.append($0) }
        try manager.delete(.whisper(.small), activeModel: .small)
        XCTAssertEqual(switchedTo, [.base])
        XCTAssertEqual(manager.state(for: .whisper(.small)).phase, .idle)
        XCTAssertFalse(layout.isWhisperInstalled(.small))

        try manager.delete(.whisper(.base), activeModel: .base)
        XCTAssertEqual(switchedTo, [.base, nil])
        XCTAssertEqual(manager.installedWhisper, [])
    }

    @MainActor
    func testDeleteInactiveModelDoesNotTouchTheActiveOne() async throws {
        let manager = makeManager()
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        manager.refreshInstalledStates()
        var switched = 0
        manager.onActiveModelDeleted = { _ in switched += 1 }
        try manager.delete(.whisper(.tiny), activeModel: .small)
        XCTAssertEqual(switched, 0)
        XCTAssertEqual(manager.installedWhisper, [.small])
    }

    @MainActor
    func testDeleteVADClearsCacheThroughTheSeam() throws {
        let manager = makeManager()
        try FakeInstallSteps.fabricateVAD(in: layout)
        manager.refreshInstalledStates()
        XCTAssertTrue(manager.vadInstalled)
        try manager.delete(.vad, activeModel: .small)
        XCTAssertEqual(fakeSteps.vadDeletes, 1)
        XCTAssertFalse(manager.vadInstalled)
    }

    @MainActor
    func testFreeSpaceRule() {
        let small: Int64 = 486_500_000
        // refuse: available < expected * 1.25 + 200 MB
        XCTAssertEqual(ModelManager.freeSpaceVerdict(expectedBytes: small, availableBytes: 500_000_000),
                       .refuse(message: "Not enough space: needs about 0.8 GB, 0.5 GB free"))
        // low remaining: room to install but less than 1 GB would remain
        XCTAssertEqual(ModelManager.freeSpaceVerdict(expectedBytes: small, availableBytes: 1_200_000_000),
                       .lowRemaining(remainingBytes: 713_500_000))
        XCTAssertEqual(ModelManager.freeSpaceVerdict(expectedBytes: small, availableBytes: 5_000_000_000), .ok)
        // unknown capacity never blocks an install
        XCTAssertEqual(ModelManager.freeSpaceVerdict(expectedBytes: small, availableBytes: nil), .ok)
        XCTAssertEqual(ModelManager.gigabytesText(1_528_000_000), "1.5 GB")
    }

    @MainActor
    func testInstallRefusedWithoutSpaceNeverTouchesTheSeam() async {
        let manager = makeManager(availableBytes: 100_000_000)
        manager.install(.whisper(.medium))
        await waitUntil { if case .failed = manager.state(for: .whisper(.medium)).phase { return true } else { return false } }
        XCTAssertEqual(manager.state(for: .whisper(.medium)).phase, .failed("Not enough space: needs about 2.1 GB, 0.1 GB free"))
        XCTAssertEqual(fakeSteps.variantDownloads, [])
    }

    // MARK: Backgrounding (Task 26)

    @MainActor
    private func makeManager(host: FakeInstallHost) -> ModelManager {
        fakeSteps = FakeInstallSteps()
        defaults = UserDefaults(suiteName: "ReVoxModelManagerTests-\(UUID().uuidString)")
        let installer = ModelInstaller(layout: layout, steps: fakeSteps.steps(layout: layout), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        return ModelManager(layout: layout, installer: installer, isPipelineRunning: { false }, availableBytes: { 50_000_000_000 }, host: host)
    }

    @MainActor
    func testExpirationPausesDownloadAndForegroundResumes() async {
        let host = FakeInstallHost()
        let manager = makeManager(host: host)
        fakeSteps.holdDownloads = true
        manager.install(.whisper(.tiny))
        await waitUntil { manager.state(for: .whisper(.tiny)).phase == .downloading(completedFiles: nil, totalFiles: nil) }
        XCTAssertEqual(host.begun.count, 1)
        XCTAssertEqual(host.begun.first?.name, "ReVox model install whisper.tiny")

        host.expireAll()
        await waitUntil("paused") { manager.state(for: .whisper(.tiny)).phase == .paused }
        XCTAssertEqual(manager.pausedKinds, [.whisper(.tiny)])
        XCTAssertEqual(host.ended, [1])
        XCTAssertFalse(manager.hasActiveDownload)

        fakeSteps.holdDownloads = false
        manager.applicationDidBecomeActive()
        await waitUntil("resumed and installed") { manager.state(for: .whisper(.tiny)).phase == .installed }
        XCTAssertEqual(manager.pausedKinds, [])
        XCTAssertEqual(fakeSteps.variantDownloads, ["openai_whisper-tiny", "openai_whisper-tiny"])
        XCTAssertEqual(host.begun.count, 3, "tiny twice plus the automatic VAD install")
    }

    @MainActor
    func testUserCancelAfterPauseDoesNotResume() async {
        let host = FakeInstallHost()
        let manager = makeManager(host: host)
        fakeSteps.holdDownloads = true
        manager.install(.whisper(.tiny))
        await waitUntil { manager.state(for: .whisper(.tiny)).phase == .downloading(completedFiles: nil, totalFiles: nil) }
        host.expireAll()
        await waitUntil { manager.state(for: .whisper(.tiny)).phase == .paused }
        manager.cancel(.whisper(.tiny))
        XCTAssertEqual(manager.state(for: .whisper(.tiny)).phase, .idle)
        manager.applicationDidBecomeActive()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fakeSteps.variantDownloads, ["openai_whisper-tiny"])
    }

    @MainActor
    func testIdleTimerDisabledOnlyWhileADownloadIsActive() async {
        let host = FakeInstallHost()
        let manager = makeManager(host: host)
        XCTAssertFalse(host.isIdleTimerDisabled)
        fakeSteps.holdDownloads = true
        manager.install(.whisper(.tiny))
        await waitUntil { host.isIdleTimerDisabled }
        fakeSteps.holdDownloads = false
        await waitUntil("vad installed", details: { "vad \(manager.state(for: .vad).phase), whisper \(manager.state(for: .whisper(.tiny)).phase), vadDownloads \(self.fakeSteps.vadDownloads), paused \(manager.pausedKinds)" }) { manager.state(for: .vad).phase == .installed }
        XCTAssertFalse(host.isIdleTimerDisabled)
        XCTAssertEqual(host.ended.count, host.begun.count, "every background task is ended")
    }
}
