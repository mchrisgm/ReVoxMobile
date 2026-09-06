import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class VoicesViewModelTests: XCTestCase {
    /// Records every sample request; can hold the call open or make it fail.
    private final class SampleRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedSelections: [SpeakerSelection] = []
        private var recordedTexts: [String] = []
        private var holding = false
        var fail = false

        var selections: [SpeakerSelection] { lock.lock(); defer { lock.unlock() }; return recordedSelections }
        var texts: [String] { lock.lock(); defer { lock.unlock() }; return recordedTexts }
        var hold: Bool {
            get { lock.lock(); defer { lock.unlock() }; return holding }
            set { lock.lock(); holding = newValue; lock.unlock() }
        }

        var player: SamplePlayer {
            SamplePlayer(play: { [self] selection, text in
                lock.lock(); recordedSelections.append(selection); recordedTexts.append(text); let shouldFail = fail; lock.unlock()
                while hold {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                if shouldFail { throw SpeakerError.synthesisFailed("sample refused") }
            })
        }
    }

    private var root: URL!
    private var layout: ModelLayout!
    private var steps: FakeInstallSteps!
    private var host: FakeInstallHost!
    private var store: SettingsStore!
    private var defaults: UserDefaults!
    private var relay: SpeakerStatusRelay!
    private var sample: SampleRecorder!
    private var manager: ModelManager!
    private var pipelineRunning = false
    private var benchmarkRunning = false

    private static let fabricatedVoices = [
        SystemVoiceOption(id: "com.example.default", name: "Fred", language: "en-US", quality: .default),
        SystemVoiceOption(id: "com.example.premium", name: "Ava", language: "en-US", quality: .premium),
        SystemVoiceOption(id: "com.example.enhanced", name: "Daniel", language: "en-GB", quality: .enhanced),
    ]

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxVoicesVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        steps = FakeInstallSteps()
        host = FakeInstallHost()
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        defaults = UserDefaults(suiteName: "ReVoxVoicesVM-\(UUID().uuidString)")
        relay = SpeakerStatusRelay()
        sample = SampleRecorder()
        pipelineRunning = false
        benchmarkRunning = false
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(memoryGiB: UInt64 = 6, availableBytes: Int64? = 50_000_000_000,
                           fileRecord: InstalledFileRecord = InstalledFileRecord(defaults: UserDefaults(suiteName: "ReVoxFileRecord-\(UUID().uuidString)")!)) -> VoicesViewModel {
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        let manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { [unowned self] in self.pipelineRunning },
                                   availableBytes: { availableBytes }, host: host, fileRecord: fileRecord)
        self.manager = manager
        let store = self.store!
        return VoicesViewModel(
            manager: manager,
            settings: store,
            deviceInfo: DeviceInfo(physicalMemoryBytes: memoryGiB * 1_073_741_824),
            speakerStatus: relay,
            samplePlayer: sample.player,
            selection: { SpeakerSelection.choose(settings: store.settings, pocketTTSReady: await manager.isPocketTTSReady()) },   // the R11 rule of SpeakerAssembly.selection()
            systemVoices: { Self.fabricatedVoices },
            isPipelineRunning: { [unowned self] in self.pipelineRunning },
            isBenchmarkRunning: { [unowned self] in self.benchmarkRunning }
        )
    }

    func testDownloadInstallsAndExposesTheOfferedVoices() async {
        let model = makeModel()
        XCTAssertEqual(model.pocketTTSState.phase, .idle)
        XCTAssertFalse(model.isPocketTTSInstalled)
        XCTAssertEqual(model.offeredVoices, ["alba", "azelma", "javert"])
        XCTAssertEqual(VoicesViewModel.pocketTTSSizeText, "≈ 527 MB")

        model.download()
        XCTAssertNil(model.lowStorageAlert)
        await waitUntil("installed") { model.pocketTTSState.phase == .installed }
        XCTAssertTrue(model.isPocketTTSInstalled)
        XCTAssertEqual(steps.pocketTTSDownloads, 1)
        XCTAssertNil(model.footerText)
    }

    func testDownloadRowIsDeterminateAndCancelReturnsToIdle() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download()
        await waitUntil { model.pocketTTSState.phase.isActive }
        XCTAssertNotNil(model.pocketTTSState.fraction)
        XCTAssertEqual(model.footerText, ModelsViewModel.keepOpenText)
        model.cancel()
        await waitUntil { model.pocketTTSState.phase == .idle }
        XCTAssertFalse(model.isPocketTTSInstalled)
    }

    func testFailedDownloadShowsFailedAndRetryDownloadsAgain() async {
        let model = makeModel()
        steps.failPocketTTSOnce = true
        model.download()
        await waitUntil { if case .failed = model.pocketTTSState.phase { return true } else { return false } }
        model.download()
        await waitUntil { model.pocketTTSState.phase == .installed }
        XCTAssertEqual(steps.pocketTTSDownloads, 2)
    }

    func testLowStorageRefusalShowsTheAlertAndDownloadsNothing() async {
        let model = makeModel(availableBytes: 300_000_000)
        model.download()
        XCTAssertEqual(model.lowStorageAlert, "Not enough space: needs about 0.9 GB, 0.3 GB free")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(steps.pocketTTSDownloads, 0)
        XCTAssertEqual(model.pocketTTSState.phase, .idle)
    }

    func testDeleteRefusedWhileRunningAndClearsWhenIdle() throws {
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        let model = makeModel()
        manager.refreshInstalledStates()
        XCTAssertTrue(model.isPocketTTSInstalled)
        XCTAssertTrue(model.canDelete)

        pipelineRunning = true
        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.footerText, VoicesViewModel.stopToDeleteText)
        XCTAssertThrowsError(try model.delete()) { error in
            XCTAssertEqual(error as? ModelManagerError, .pipelineRunning)
        }

        pipelineRunning = false
        try model.delete()
        XCTAssertEqual(steps.pocketTTSDeletes, 1)
        XCTAssertFalse(model.isPocketTTSInstalled)
        XCTAssertEqual(model.pocketTTSState.phase, .idle)
        XCTAssertEqual(store.settings.voice, "alba", "the voice setting is kept; the system voice speaks until the next download (§8.4)")
    }

    func testSelectingVoicesWritesSettingsAndTheCheckmarks() {
        let model = makeModel()
        XCTAssertEqual(model.selectedPocketVoice, "alba", "R11 default")
        XCTAssertNil(model.selectedSystemVoiceIdentifier)
        XCTAssertFalse(model.isSystemVoiceSelected)

        model.selectPocketVoice("javert")
        XCTAssertEqual(store.settings.voice, "javert")
        XCTAssertEqual(model.selectedPocketVoice, "javert")
        model.selectPocketVoice("michael")
        XCTAssertEqual(store.settings.voice, "javert", "only offered voices are selectable")
        model.selectPocketVoice("cosette")
        XCTAssertEqual(store.settings.voice, "javert", "cosette left the offered list before 1.0.0 (CC BY-NC clip)")

        model.selectSystemVoice(Self.fabricatedVoices[1])
        XCTAssertEqual(store.settings.voice, "system")
        XCTAssertEqual(store.settings.systemVoiceIdentifier, "com.example.premium")
        XCTAssertNil(model.selectedPocketVoice)
        XCTAssertEqual(model.selectedSystemVoiceIdentifier, "com.example.premium")
        XCTAssertTrue(model.isSystemVoiceSelected)
        let reread = SettingsStore(fileURL: store.fileURL)
        XCTAssertEqual(reread.settings.voice, "system")
        XCTAssertEqual(reread.settings.systemVoiceIdentifier, "com.example.premium")

        model.selectPocketVoice("javert")
        XCTAssertEqual(store.settings.voice, "javert")
        XCTAssertEqual(store.settings.systemVoiceIdentifier, "com.example.premium", "the system voice stays recorded as the fallback")
    }

    func testAdvisoryOnlyBelowTheSixGigabyteTier() {
        let fourGiB = makeModel(memoryGiB: 4)
        XCTAssertEqual(fourGiB.advisoryText, DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: 4))
        XCTAssertNotNil(fourGiB.advisoryText)
        XCTAssertNil(makeModel(memoryGiB: 6).advisoryText)
        XCTAssertNil(makeModel(memoryGiB: 8).advisoryText)
    }

    func testPlaySampleUsesTheSelectionAndIsIdleOnly() async throws {
        let model = makeModel()
        sample.hold = true
        let task = Task { await model.playSample() }
        await waitUntil("playing") { model.isPlayingSample }
        XCTAssertFalse(model.canPlaySample)
        sample.hold = false
        await task.value
        XCTAssertFalse(model.isPlayingSample)
        XCTAssertTrue(model.canPlaySample)
        XCTAssertNil(model.sampleError)
        XCTAssertEqual(sample.selections, [.systemNotDownloaded(identifier: nil)], "alba is selected but pocket-tts is not ready")
        XCTAssertEqual(sample.texts, ["This is ReVox."])

        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        VerifiedLoadRecord(defaults: defaults).record(.pocketTTS)
        manager.refreshInstalledStates()
        await model.playSample()
        XCTAssertEqual(sample.selections.last, .pocketTTS(voice: "alba", fallbackIdentifier: nil))

        pipelineRunning = true
        XCTAssertFalse(model.canPlaySample)
        await model.playSample()
        XCTAssertEqual(sample.texts.count, 2, "idle only")
    }

    /// M10: a disabled Play sample says why. While translation runs the caption names it; while a sample plays the
    /// spinner is the reason, so there is no caption to double it.
    func testSampleUnavailableReasonNamesTheRunningTranslation() async {
        let model = makeModel()
        XCTAssertNil(model.sampleUnavailableReason)
        pipelineRunning = true
        XCTAssertFalse(model.canPlaySample)
        XCTAssertEqual(model.sampleUnavailableReason, VoicesViewModel.stopToPlaySampleText)
        XCTAssertEqual(VoicesViewModel.stopToPlaySampleText, "Stop translation to play a sample")
        pipelineRunning = false
        sample.hold = true
        let task = Task { await model.playSample() }
        await waitUntil("playing") { model.isPlayingSample }
        XCTAssertFalse(model.canPlaySample)
        XCTAssertNil(model.sampleUnavailableReason, "the spinner is the reason while a sample plays")
        sample.hold = false
        await task.value
    }

    func testSampleFailureIsReportedAndClearsOnTheNextSample() async {
        let model = makeModel()
        sample.fail = true
        await model.playSample()
        XCTAssertEqual(model.sampleError, "Speech synthesis failed: sample refused")
        sample.fail = false
        await model.playSample()
        XCTAssertNil(model.sampleError)
    }

    func testFallbackStatusShowsRetryAndRetryReplaysTheSample() async {
        let model = makeModel()
        XCTAssertEqual(model.statusText, SpeakerStatus.notDownloadedText)
        XCTAssertFalse(model.showsRetry)
        relay.status = .fallback(.loadFailed("no ANE"))
        XCTAssertTrue(model.showsRetry)
        XCTAssertEqual(model.statusText, SpeakerStatus.failedToLoadText)
        await model.retryPocketTTS()
        XCTAssertEqual(sample.texts, ["This is ReVox."], "retry re-prepares the speaker through the sample path")
        relay.status = .pocketTTS(voice: "alba")
        XCTAssertFalse(model.showsRetry)
        XCTAssertEqual(model.statusText, "alba (pocket-tts)")
    }

    func testSystemVoiceOptionsAreEnglishOnlyAndSortedByQuality() {
        let sorted = SystemVoiceOption.sorted(Self.fabricatedVoices)
        XCTAssertEqual(sorted.map(\.id), ["com.example.premium", "com.example.enhanced", "com.example.default"])
        XCTAssertEqual(sorted.map(\.qualityLabel), ["Premium", "Enhanced", "Default"])
        let model = makeModel()
        XCTAssertEqual(model.systemVoices.map(\.name), ["Ava", "Daniel", "Fred"], "the view model orders the injected source, it does not trust it")
        model.refreshSystemVoices()
        XCTAssertEqual(model.systemVoices.map(\.name), ["Ava", "Daniel", "Fred"], "and refresh orders it the same way")

        // The two filters of §6.6 against the simulator's real voice list, computed independently of `english(from:)`:
        // deleting either clause from the implementation breaks one of these assertions.
        let raw = AVSpeechSynthesisVoice.speechVoices()
        let installed = SystemVoiceOption.english(from: raw)
        XCTAssertFalse(installed.isEmpty, "the simulator ships English voices")
        XCTAssertEqual(Set(installed.map(\.id)),
                       Set(raw.filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }.map(\.identifier)))
        XCTAssertLessThan(installed.count, raw.count, "non-English voices are dropped")
        XCTAssertFalse(installed.contains { !$0.language.hasPrefix("en") })
        XCTAssertFalse(raw.contains { $0.voiceTraits.contains(.isNoveltyVoice) && installed.map(\.id).contains($0.identifier) })
        XCTAssertEqual(installed, SystemVoiceOption.sorted(installed))
    }

    /// M10: the download row names the voices from the catalog, so a catalog change can never leave a stale list.
    func testTheDownloadRowNamesTheCatalogVoices() {
        XCTAssertEqual(VoicesViewModel.voiceListText(["alba", "azelma", "javert"]), "Voices alba, azelma and javert.")
        XCTAssertEqual(VoicesViewModel.voiceListText(["alba", "javert"]), "Voices alba and javert.")
        XCTAssertEqual(VoicesViewModel.voiceListText(["alba"]), "Voice alba.")
        XCTAssertEqual(VoicesViewModel.voiceListText([]), "No voices.")
        XCTAssertEqual(VoicesViewModel.downloadRowDescription,
                       "Voices alba, azelma and javert. Downloaded on demand; the system voice is used until then.")
        XCTAssertTrue(VoicesViewModel.downloadRowDescription.hasPrefix(VoicesViewModel.voiceListText(ModelCatalog.pocketTTS.offeredVoices)))
    }

    func testTexts() {
        XCTAssertEqual(VoicesViewModel.sampleText, "This is ReVox.")
        XCTAssertEqual(VoicesViewModel.engineFooterText, "ReVox uses the system voice until pocket-tts is downloaded, and falls back to it automatically if pocket-tts fails.")
        XCTAssertEqual(VoicesViewModel.stopToDeleteText, "Stop translation to delete voices")
        XCTAssertEqual(VoicesViewModel.confirmDeleteTitle, "Delete pocket-tts (≈ 527 MB)?")
        XCTAssertEqual(VoicesViewModel.confirmDeleteMessage, "ReVox will use the system voice until you download it again.")
        XCTAssertEqual(VoicesViewModel.pocketTTSName, "pocket-tts")
        XCTAssertEqual(VoicesViewModel.systemVoiceValue, "system")
    }

    // MARK: Error surfaces (§8.8, M6)

    func testUserInitiatedPocketTTSFailureRaisesTheAlertOnce() async {
        let model = makeModel()
        steps.failPocketTTSOnce = true
        model.download()
        await waitUntil("failed state") { if case .failed = model.pocketTTSState.phase { return true } else { return false } }
        guard case .failed(let message) = model.pocketTTSState.phase else { return XCTFail("expected a failed state") }
        model.reconcileFailures()
        XCTAssertEqual(model.downloadFailureAlert, ModelsViewModel.downloadFailureText(name: VoicesViewModel.pocketTTSName, message: message))
        model.downloadFailureAlert = nil
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert)
    }

    func testCancelledDownloadNeverAlerts() async {
        let model = makeModel()
        steps.holdDownloads = true
        model.download()
        await waitUntil { model.pocketTTSState.phase.isActive }
        model.cancel()
        steps.holdDownloads = false
        await waitUntil("not active") { !model.pocketTTSState.phase.isActive }
        model.reconcileFailures()
        XCTAssertNil(model.downloadFailureAlert)
    }

    // MARK: Storage accounting (M7 Task 88)

    func testInstalledPocketTTSShowsTheMeasuredSizeAndTheStorageFooter() throws {
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        let big = layout.pocketTTSLanguageFolder.appendingPathComponent(ModelLayout.pocketTTSBundles[0]).appendingPathComponent("weights/weight.bin")
        try FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 5_000_000).write(to: big)
        let model = makeModel(availableBytes: 9_000_000_000)
        XCTAssertTrue(model.isPocketTTSInstalled)
        XCTAssertEqual(model.pocketTTSSizeLine, "5 MB")
        XCTAssertTrue(model.storageFooterText.hasSuffix(" · Free: 9.0 GB"))
        XCTAssertEqual(VoicesViewModel.pocketTTSSizeText, "≈ 527 MB", "the catalog estimate is still used before the download")
        let fresh = makeModel(availableBytes: 9_000_000_000)
        XCTAssertEqual(fresh.pocketTTSSizeLine, "5 MB")
    }

    // MARK: Delete only while idle (M7 Task 89)

    func testPocketTTSDeleteRefusedWhileRunningUsesItsOwnAlert() throws {
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        let model = makeModel()
        pipelineRunning = true
        XCTAssertFalse(model.canDelete)
        model.deleteConfirmed()
        XCTAssertEqual(model.deleteFailureAlert, "Stop translation to delete voices",
                       "M10: the alert says what the footer of the same screen says, not the manager's Models wording")
        XCTAssertEqual(model.deleteFailureAlert, VoicesViewModel.stopToDeleteText)
        XCTAssertNil(model.lowStorageAlert)
        XCTAssertTrue(model.isPocketTTSInstalled)

        pipelineRunning = false
        model.deleteConfirmed()
        XCTAssertNil(model.deleteFailureAlert)
        XCTAssertFalse(model.isPocketTTSInstalled)
    }

    /// Only the running-pipeline refusal is reworded for this screen; any other error still prints itself.
    func testDeleteFailureTextRewordsOnlyTheRunningRefusal() {
        XCTAssertEqual(VoicesViewModel.deleteFailureText(ModelManagerError.pipelineRunning), "Stop translation to delete voices")
        XCTAssertEqual(VoicesViewModel.deleteFailureText(ModelManagerError.notEnoughSpace("no room")), "no room")
        XCTAssertEqual(VoicesViewModel.deleteFailureText(SpeakerError.noVoice), String(describing: SpeakerError.noVoice))
    }

    // MARK: Upstream-change caption (M7 Task 90)

    func testPocketTTSNoticeAppearsWhenTheRecordedFileSetNoLongerMatches() throws {
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        let record = InstalledFileRecord(defaults: UserDefaults(suiteName: "ReVoxVoiceNotice-\(UUID().uuidString)")!)
        XCTAssertNil(makeModel().pocketTTSNoticeText)
        record.record(.pocketTTS, files: ["v2.1/english/constants_bin/gone.bin": 4])
        XCTAssertEqual(makeModel(fileRecord: record).pocketTTSNoticeText, ModelManager.upstreamChangedText)
    }

    /// M10: verifying pocket-tts loads it, so the download is refused while a session runs (§9).
    func testDownloadRefusedWhileRunningAndAllowedWhenIdle() async {
        let model = makeModel()
        pipelineRunning = true
        XCTAssertFalse(model.canDownload)
        model.download()
        XCTAssertEqual(model.downloadRefusedAlert, "Stop translation to download voices")
        XCTAssertNil(model.lowStorageAlert)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(steps.pocketTTSDownloads, 0)
        XCTAssertEqual(model.pocketTTSState.phase, .idle)

        pipelineRunning = false
        model.downloadRefusedAlert = nil
        XCTAssertTrue(model.canDownload)
        model.download()
        XCTAssertNil(model.downloadRefusedAlert)
        await waitUntil { model.pocketTTSState.phase == .installed }
    }

    /// M11 §5: a pocket-tts download or delete is a model load or unload beside the one the benchmark is timing,
    /// so both are refused while it runs, in the Models screen's words ("Finish or cancel the benchmark first").
    func testDownloadAndDeleteAreRefusedWhileABenchmarkRuns() throws {
        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        let model = makeModel()
        manager.refreshInstalledStates()
        XCTAssertTrue(model.canDownload)
        XCTAssertTrue(model.canDelete)
        XCTAssertNil(model.footerText)

        benchmarkRunning = true
        XCTAssertFalse(model.canDownload)
        XCTAssertFalse(model.canDelete)
        XCTAssertEqual(model.footerText, ModelsViewModel.finishBenchmarkText)

        model.download()
        XCTAssertEqual(model.downloadRefusedAlert, ModelsViewModel.finishBenchmarkText)
        XCTAssertNil(model.lowStorageAlert)
        XCTAssertEqual(steps.pocketTTSDownloads, 0)
        XCTAssertEqual(model.pocketTTSState.phase, .installed)

        XCTAssertThrowsError(try model.delete()) { error in
            XCTAssertEqual(error as? BenchmarkError, .busy)
        }
        model.deleteConfirmed()
        XCTAssertEqual(model.deleteFailureAlert, ModelsViewModel.finishBenchmarkText)
        XCTAssertEqual(steps.pocketTTSDeletes, 0)
        XCTAssertTrue(model.isPocketTTSInstalled)

        benchmarkRunning = false
        model.downloadRefusedAlert = nil
        XCTAssertTrue(model.canDownload)
        XCTAssertTrue(model.canDelete)
        XCTAssertNil(model.footerText)
        try model.delete()
        XCTAssertEqual(steps.pocketTTSDeletes, 1, "the same delete goes through once the benchmark is over")
    }
}
