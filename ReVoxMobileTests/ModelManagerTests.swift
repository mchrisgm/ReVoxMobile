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

    /// The retry is issued on the same main-actor turn that first observes `.failed`, which is exactly the
    /// window in which the task slot used to still be occupied — the second `install` then returned early and
    /// this case failed with one download instead of two (run 33868423907). The manager now withholds the
    /// failure phase until the slot is free, so the retry here is always accepted.
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

    /// Release S3: the finished-install callback fires once per Whisper install, after the flags were refreshed,
    /// and never for the VAD install that follows, a failure or a cancel.
    @MainActor
    func testWhisperInstallReportsItselfOnceWithTheFlagsRefreshed() async {
        let manager = makeManager()
        var reported: [WhisperModelID] = []
        var flaggedInstalled: [Bool] = []
        var rowInstalled: [Bool] = []
        manager.onWhisperInstalled = { id in
            reported.append(id)
            flaggedInstalled.append(manager.installedWhisper.contains(id))
            rowInstalled.append(manager.state(for: .whisper(id)).phase == .installed)
        }
        manager.install(.whisper(.tiny))
        await waitUntil("vad installed", details: { "vad \(manager.state(for: .vad).phase), reported \(reported)" }) { manager.state(for: .vad).phase == .installed }
        XCTAssertEqual(reported, [.tiny], "the VAD that follows is not a Whisper install")
        XCTAssertEqual(flaggedInstalled, [true])
        XCTAssertEqual(rowInstalled, [true])

        fakeSteps.failVariantOnce = true
        manager.install(.whisper(.base))
        await waitUntil("failed row") { if case .failed = manager.state(for: .whisper(.base)).phase { return true } else { return false } }
        XCTAssertEqual(reported, [.tiny], "a failure is not reported")

        fakeSteps.holdDownloads = true
        manager.install(.whisper(.small))
        await waitUntil { manager.state(for: .whisper(.small)).phase.isActive }
        manager.cancel(.whisper(.small))
        await waitUntil { manager.state(for: .whisper(.small)).phase == .idle }
        XCTAssertEqual(reported, [.tiny], "a cancel is not reported")
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
        // An isolated record store: the initializer's default is `UserDefaults.standard`, which every test in the
        // bundle would otherwise share, and the file sets recorded here are keyed by kind, not by layout.
        let record = InstalledFileRecord(defaults: UserDefaults(suiteName: "ReVoxFileRecord-\(UUID().uuidString)")!)
        return ModelManager(layout: layout, installer: installer, isPipelineRunning: { false },
                            availableBytes: { 50_000_000_000 }, host: host, fileRecord: record)
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
        // The row reports `.installed` from the installer's last progress report, which lands before the manager
        // finishes the task and starts the automatic VAD install: that install is awaited, never assumed.
        await waitUntil("the automatic VAD install began", details: { "begun \(host.begun.map(\.name))" }) { host.begun.count == 3 }
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
        // Same ordering: `.installed` arrives with the last progress report, and the task is ended just after.
        await waitUntil("every background task ended", details: { "begun \(host.begun.count), ended \(host.ended.count)" }) {
            host.ended.count == host.begun.count
        }
        XCTAssertFalse(host.isIdleTimerDisabled)
    }

    // MARK: pocket-tts installed check (Task 45, §6.9)

    private func fabricatePocketTTS(missing: String? = nil) throws {
        let folder = layout.pocketTTSLanguageFolder
        for bundle in ModelLayout.pocketTTSBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(ModelLayout.compiledMarker))
        }
        let constants = folder.appendingPathComponent(ModelLayout.pocketTTSConstantsFolder)
        for file in ModelLayout.pocketTTSConstantFiles where file != missing {
            try touch(constants.appendingPathComponent(file))
        }
        for voice in ModelCatalog.pocketTTS.offeredVoices where ModelLayout.pocketTTSVoiceFile(voice) != missing {
            try touch(constants.appendingPathComponent(ModelLayout.pocketTTSVoiceFile(voice)))
        }
    }

    func testPocketTTSInstalledWhenEveryRequiredFileIsPresent() throws {
        XCTAssertFalse(layout.isPocketTTSInstalled())
        try fabricatePocketTTS()
        XCTAssertTrue(layout.isPocketTTSInstalled())
        XCTAssertEqual(ModelLayout.pocketTTSBundles, ["cond_prefill_ane.mlmodelc", "flowlm_step_ane.mlmodelc", "flow_decoder_fused.mlmodelc", "mimi_decoder.mlmodelc"])
        XCTAssertEqual(ModelLayout.pocketTTSConstantsFolder, "constants_bin")
        XCTAssertEqual(ModelLayout.pocketTTSConstantFiles, ["text_embed_table.bin", "tokenizer.model", "bos_emb.bin", "bos_before_voice.bin"])
        XCTAssertEqual(ModelLayout.pocketTTSVoiceFile("alba"), "alba.safetensors")
        XCTAssertEqual(ModelCatalog.pocketTTS.offeredVoices, ["alba", "azelma", "javert"])
    }

    func testPocketTTSNotReadyWhenVoiceOrBosMissing() throws {
        try fabricatePocketTTS(missing: "bos_before_voice.bin")
        XCTAssertFalse(layout.isPocketTTSInstalled(), "bos_before_voice.bin is the runtime backfill guard (§6.5)")

        try FileManager.default.removeItem(at: layout.pocketTTSLanguageFolder)
        try fabricatePocketTTS(missing: ModelLayout.pocketTTSVoiceFile("javert"))
        XCTAssertFalse(layout.isPocketTTSInstalled(), "every offered voice file is required")

        try FileManager.default.removeItem(at: layout.pocketTTSLanguageFolder)
        try fabricatePocketTTS()
        try touch(layout.pocketTTSLanguageFolder.appendingPathComponent("mimi_decoder.mlmodelc/weights/weight.bin.partial"))
        XCTAssertFalse(layout.isPocketTTSInstalled(), "no partial file anywhere beneath the language folder")
    }


    // MARK: pocket-tts row (Task 46, §6.9, §8.4)

    @MainActor
    func testInstallPocketTTSUpdatesTheRowAndReadiness() async {
        let manager = makeManager()
        XCTAssertEqual(manager.state(for: .pocketTTS).phase, .idle)
        XCTAssertEqual(manager.state(for: .pocketTTS).bytesExpected, ModelCatalog.download(for: .pocketTTS).expectedBytes)
        XCTAssertFalse(manager.pocketTTSInstalled)

        manager.install(.pocketTTS)
        await waitUntil("pocket-tts installed") { manager.state(for: .pocketTTS).phase == .installed }
        XCTAssertTrue(manager.pocketTTSInstalled)
        XCTAssertEqual(manager.state(for: .pocketTTS).fraction, 1)
        XCTAssertEqual(fakeSteps.pocketTTSDownloads, 1)
        XCTAssertEqual(fakeSteps.vadDownloads, 0, "pocket-tts never pulls the VAD bundle")
        XCTAssertFalse(manager.hasActiveDownload)
        let ready = await manager.isPocketTTSReady()
        XCTAssertTrue(ready)
    }

    @MainActor
    func testPocketTTSRowIsDeterminateWhileDownloading() async {
        let manager = makeManager()
        fakeSteps.holdDownloads = true
        manager.install(.pocketTTS)
        await waitUntil { manager.state(for: .pocketTTS).phase == .listing }
        XCTAssertNotNil(manager.state(for: .pocketTTS).fraction)
        XCTAssertTrue(manager.hasActiveDownload)
        fakeSteps.holdDownloads = false
        await waitUntil { manager.state(for: .pocketTTS).phase == .installed }
    }

    @MainActor
    func testCancelPocketTTSReturnsToIdle() async {
        let manager = makeManager()
        fakeSteps.holdDownloads = true
        manager.install(.pocketTTS)
        await waitUntil { manager.state(for: .pocketTTS).phase.isActive }
        manager.cancel(.pocketTTS)
        await waitUntil { manager.state(for: .pocketTTS).phase == .idle }
        XCTAssertFalse(manager.pocketTTSInstalled)
        XCTAssertFalse(layout.isPocketTTSInstalled())
        XCTAssertEqual(fakeSteps.offlineModeHistory.last, true)
    }

    @MainActor
    func testFailedPocketTTSInstallShowsFailedAndRetryInstalls() async {
        let manager = makeManager()
        fakeSteps.failPocketTTSOnce = true
        manager.install(.pocketTTS)
        await waitUntil { if case .failed = manager.state(for: .pocketTTS).phase { return true } else { return false } }
        manager.install(.pocketTTS)
        await waitUntil { manager.state(for: .pocketTTS).phase == .installed }
        XCTAssertEqual(fakeSteps.pocketTTSDownloads, 2)
    }

    @MainActor
    func testDeletePocketTTSRefusedWhileRunningAndClearsWhenIdle() throws {
        let running = makeManager(pipelineRunning: true)
        XCTAssertThrowsError(try running.delete(.pocketTTS, activeModel: .small)) { error in
            XCTAssertEqual(error as? ModelManagerError, .pipelineRunning)
        }

        let idle = makeManager()
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        idle.refreshInstalledStates()
        XCTAssertTrue(idle.pocketTTSInstalled)
        XCTAssertEqual(idle.state(for: .pocketTTS).phase, .installed)
        try idle.delete(.pocketTTS, activeModel: .small)
        XCTAssertEqual(fakeSteps.pocketTTSDeletes, 1)
        XCTAssertFalse(idle.pocketTTSInstalled)
        XCTAssertEqual(idle.state(for: .pocketTTS).phase, .idle)
        XCTAssertFalse(layout.isPocketTTSInstalled())
    }

    @MainActor
    func testPocketTTSInstallRefusedWithoutSpace() async {
        let manager = makeManager(availableBytes: 300_000_000)
        manager.install(.pocketTTS)
        await waitUntil { if case .failed = manager.state(for: .pocketTTS).phase { return true } else { return false } }
        XCTAssertEqual(manager.state(for: .pocketTTS).phase, .failed("Not enough space: needs about 0.9 GB, 0.3 GB free"))
        XCTAssertEqual(fakeSteps.pocketTTSDownloads, 0)
    }


    // MARK: Storage accounting (M7 Task 87)

    @MainActor
    func testStorageRefreshesAfterInstallAndDelete() async throws {
        let host = FakeInstallHost()
        let manager = makeManager(host: host)
        XCTAssertEqual(manager.storage.totalBytes, 0)
        XCTAssertEqual(manager.storage.freeBytes, 50_000_000_000)
        manager.install(.whisper(.tiny))
        await waitUntil("tiny and the automatic VAD installed") { manager.state(for: .vad).phase == .installed }
        XCTAssertNotNil(manager.storage.bytes(for: .whisper(.tiny)))
        XCTAssertNotNil(manager.storage.bytes(for: .vad))
        XCTAssertGreaterThan(manager.storage.totalBytes, 0)
        try manager.delete(.whisper(.tiny), activeModel: .small)
        XCTAssertNil(manager.storage.bytes(for: .whisper(.tiny)))
        XCTAssertNotNil(manager.storage.bytes(for: .vad))
        manager.refreshStorage()
        let expected = ModelStorage.usage(layout: layout, availableBytes: nil).bytes(for: .vad)
        XCTAssertEqual(manager.storage.bytes(for: .vad), expected)
    }

    // MARK: Delete announces that model files changed (M7 Task 89)

    @MainActor
    func testDeleteNotifiesModelFilesChangedAndARefusalDoesNot() async throws {
        let manager = makeManager(host: FakeInstallHost())
        let notifications = LockedBox<Int>(0)
        manager.onModelFilesChanged = { notifications.mutate { $0 += 1 } }
        manager.install(.whisper(.tiny))
        await waitUntil("tiny installed") { manager.state(for: .whisper(.tiny)).phase == .installed }
        XCTAssertEqual(notifications.value, 0, "an install never invalidates a loaded model")

        try manager.delete(.whisper(.tiny), activeModel: .small)
        XCTAssertEqual(notifications.value, 1)

        let running = makeManager(pipelineRunning: true)
        let refused = LockedBox<Int>(0)
        running.onModelFilesChanged = { refused.mutate { $0 += 1 } }
        XCTAssertThrowsError(try running.delete(.vad, activeModel: .small)) { error in
            XCTAssertEqual(error as? ModelManagerError, .pipelineRunning)
        }
        XCTAssertEqual(refused.value, 0, "a refused delete removed nothing, so nothing changed")
    }

    // MARK: Upstream-change flag for the unpinned downloads (M7 Task 90)

    @MainActor
    func testChangedVADFilesAreFlaggedAndClearedByAReinstall() async throws {
        let manager = makeManager(host: FakeInstallHost())
        manager.install(.vad)
        await waitUntil("vad installed") { manager.state(for: .vad).phase == .installed }
        XCTAssertNil(manager.upstreamChangeText(for: .vad), "the record was written by the install")
        XCTAssertTrue(manager.upstreamChanged.isEmpty)

        let stray = layout.vadRepoDirectory.appendingPathComponent("silero-vad-unified-v6.0.0.mlmodelc/upstream-new.bin")
        try Data(count: 128).write(to: stray)
        manager.refreshInstalledStates()
        XCTAssertEqual(manager.upstreamChangeText(for: .vad), ModelManager.upstreamChangedText)
        XCTAssertEqual(manager.upstreamChanged, [.vad])
        XCTAssertNil(manager.upstreamChangeText(for: .pocketTTS), "pocket-tts is not installed, so nothing is compared")

        manager.install(.vad)
        await waitUntil("vad re-installed") { manager.state(for: .vad).phase == .installed && manager.upstreamChanged.isEmpty }
        XCTAssertNil(manager.upstreamChangeText(for: .vad), "a re-download re-records the file set and clears the flag")

        try manager.delete(.vad, activeModel: .small)
        XCTAssertNil(manager.upstreamChangeText(for: .vad))
    }

    /// A row that reads Installed must mean the install is finished and `tasks[kind]` is free, because
    /// `delete(_:activeModel:)` returns early — in silence — while a task is still live. TestFlight run
    /// 33896798825 failed three M7 tests on exactly that window: the progress pump published `.installed`
    /// before `finishTask` freed the slot, so a delete taken at that moment did nothing and neither the
    /// storage figure nor the upstream flag had been refreshed yet.
    @MainActor
    func testARowThatReadsInstalledIsFinishedEnoughToDelete() async throws {
        let manager = makeManager(host: FakeInstallHost())
        let notifications = LockedBox<Int>(0)
        manager.onModelFilesChanged = { notifications.mutate { $0 += 1 } }
        manager.install(.whisper(.tiny))
        await waitUntil("tiny installed") { manager.state(for: .whisper(.tiny)).phase == .installed }

        XCTAssertNotNil(manager.storage.bytes(for: .whisper(.tiny)),
                        "the storage figure is refreshed with the row, not a tick later")
        try manager.delete(.whisper(.tiny), activeModel: .small)
        XCTAssertEqual(notifications.value, 1, "the delete was accepted, not silently refused by a live task slot")
        XCTAssertEqual(manager.state(for: .whisper(.tiny)).phase, .idle)
    }
}
