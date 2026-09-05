import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// M11 §5: the Benchmark screen's gating, the run's state machine, the saved run and what the Models screen reads.
@MainActor
final class BenchmarkViewModelTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var steps: FakeInstallSteps!
    private var host: FakeInstallHost!
    private var verifiedLoads: VerifiedLoadRecord!
    private var manager: ModelManager!
    private var store: BenchmarkStore!
    private var settings: SettingsStore!
    private var fake: FakeBenchmarkSeams!
    private var pipelineRunning = false
    private var releases = 0

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxBenchmarkVM-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        steps = FakeInstallSteps()
        host = FakeInstallHost()
        verifiedLoads = VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxBenchmarkVM-\(UUID().uuidString)")!)
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout), verifiedLoads: verifiedLoads)
        manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { [unowned self] in self.pipelineRunning },
                               availableBytes: { 50_000_000_000 }, host: host)
        store = BenchmarkStore(directory: root.appendingPathComponent("Benchmarks", isDirectory: true),
                               host: BenchmarkHost(device: "iPhone17,1", iOSVersion: "26.0.1", memoryTierGB: 8))
        settings = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        fake = FakeBenchmarkSeams()
        pipelineRunning = false
        releases = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel() -> BenchmarkViewModel {
        BenchmarkViewModel(store: store, manager: manager,
                           isPipelineRunning: { [unowned self] in self.pipelineRunning },
                           releasePipeline: { [unowned self] in self.releases += 1 },
                           runner: BenchmarkRunner(seams: fake.seams), host: host,
                           timeZone: TimeZone(identifier: "UTC")!)
    }

    /// Files on disk plus the verified-load record: what `ModelManager.isWhisperReady` needs.
    private func installReady(_ ids: [WhisperModelID]) throws {
        for id in ids {
            try FakeInstallSteps.fabricateWhisper(id, in: layout)
            verifiedLoads.record(.whisper(id))
        }
        manager.refreshInstalledStates()
    }

    // MARK: Gating

    func testRefusedWhileRunningWithTheReasonInFooterAndAlert() async throws {
        try installReady([.tiny])
        let model = makeModel()
        pipelineRunning = true
        XCTAssertFalse(model.canRun)
        XCTAssertEqual(model.whyNotText, "Stop translation to run the benchmark")
        model.start()
        XCTAssertEqual(model.refusedAlert, "Stop translation to run the benchmark")
        XCTAssertEqual(model.state, .idle)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(fake.events.value, [], "nothing was loaded")
        XCTAssertEqual(releases, 0)
    }

    func testRefusedWhileADownloadIsActive() async throws {
        let model = makeModel()
        steps.holdDownloads = true
        manager.install(.whisper(.tiny))
        await waitUntil { self.manager.hasActiveDownload }
        XCTAssertEqual(model.whyNotText, "Wait for the download to finish first")
        XCTAssertFalse(model.canRun)
        model.start()
        XCTAssertEqual(model.refusedAlert, "Wait for the download to finish first")
        steps.holdDownloads = false
        await waitUntil("install finished") { !self.manager.hasActiveDownload }
    }

    func testRefusedWithNoReadyModel() async throws {
        let model = makeModel()
        XCTAssertEqual(model.whyNotText, "Download a Whisper model first")
        model.start()
        XCTAssertEqual(model.refusedAlert, "Download a Whisper model first")

        // Installed files without a verified load: refused after the readiness check, and the state returns to idle.
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        manager.refreshInstalledStates()
        model.refusedAlert = nil
        XCTAssertNil(model.whyNotText)
        model.start()
        XCTAssertTrue(model.isRunning, "the state flips before the first await")
        await waitUntil("back to idle") { model.state == .idle }
        XCTAssertEqual(model.refusedAlert, "Download a Whisper model first")
        XCTAssertEqual(fake.events.value, [])
    }

    func testLiveStartingDuringTheReadinessCheckIsRefused() async throws {
        try installReady([.tiny])
        let model = makeModel()
        model.start()
        pipelineRunning = true   // Live got there first, between the readiness awaits
        await waitUntil("back to idle") { model.state == .idle }
        XCTAssertEqual(model.refusedAlert, "Stop translation to run the benchmark")
        XCTAssertEqual(fake.events.value, [])
    }

    // MARK: The run

    func testStartReleasesThePipelineRunsSavesAndFeedsTheModelsScreen() async throws {
        try installReady([.tiny, .small])
        fake.setText("Good morning, where is the bus station?", for: .tiny)
        let model = makeModel()
        XCTAssertTrue(model.canRun)
        XCTAssertNil(model.latest)
        XCTAssertEqual(model.rows, [])
        XCTAssertNil(model.shareText)

        model.start()
        XCTAssertEqual(model.state, .running(BenchmarkViewModel.synthesisingText))
        XCTAssertFalse(model.canRun, "a second tap is refused while running")
        await waitUntil("run finished", timeout: 5) { model.state == .idle }

        XCTAssertEqual(releases, 1, "the cached Live pipeline was released first")
        XCTAssertNil(model.failureAlert)
        XCTAssertNil(model.refusedAlert)
        XCTAssertNil(model.notice)
        XCTAssertEqual(store.runs.count, 1)
        let run = try XCTUnwrap(model.latest)
        XCTAssertEqual(run.device, "iPhone17,1")
        XCTAssertEqual(run.whisperKitVersion, LibraryVersions.whisperKit)
        XCTAssertEqual(run.sentence, BenchmarkSentences.spanish)
        XCTAssertEqual(run.results.map(\.model), [.tiny, .small])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(BenchmarkStore.fileName(for: run)).path))
        XCTAssertEqual(model.rows.count, 2)
        XCTAssertEqual(model.rows[1].summary, "Keeps up")
        XCTAssertEqual(model.shareText, BenchmarkReport.markdown(run))
        XCTAssertEqual(model.resultsFooterText, BenchmarkViewModel.footerText(run: run, languageName: "Spanish", timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertEqual(model.lastRunText, "Last run: \(BenchmarkVerdict.dateText(run.date, timeZone: TimeZone(identifier: "UTC")!)) · iPhone17,1 · iOS 26.0.1")

        // The Models screen over the same store: small (every word right) wins over tiny (one word wrong).
        let models = ModelsViewModel(manager: manager, settings: settings, deviceInfo: DeviceInfo(physicalMemoryBytes: 8 * 1_073_741_824),
                                     isPipelineRunning: { false }, benchmarks: store, isBenchmarkRunning: { model.isRunning })
        XCTAssertEqual(models.rows.filter(\.isRecommended).map(\.id), [.small])
        XCTAssertEqual(models.rows[2].measuredNote, ModelsViewModel.measuredNoteText(date: run.date))
        XCTAssertNil(models.rows[0].measuredNote)
        XCTAssertTrue(models.benchmarkFooterText.hasPrefix("Recommendation measured on this iPhone on "))
    }

    func testStatusTextsWhileRunningAndTheBackgroundTaskBracketTheRun() async throws {
        try installReady([.tiny])
        fake.hold = true
        let model = makeModel()
        model.start()
        await waitUntil("stimulus started") { self.host.begun.count == 1 }
        XCTAssertEqual(model.state, .running("Reading the sentence with the iPhone's voice"))
        XCTAssertEqual(host.begun.first?.name, "ReVox model benchmark")
        XCTAssertTrue(host.isIdleTimerDisabled)
        fake.hold = false
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(host.ended, [1])
        XCTAssertFalse(host.isIdleTimerDisabled)
        XCTAssertEqual(host.idleTimerHistory, [true, false])
    }

    func testCancelKeepsPartialResultsAndSaysSo() async throws {
        try installReady([.tiny, .small])
        fake.holdTranslate(of: .small)
        let model = makeModel()
        model.start()
        await waitFor("small's translate") { self.fake.events.value.contains("translate small") }
        model.cancel()
        XCTAssertEqual(model.state, .stopping)
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(model.notice, "Stopped after 1 of 2 models; the results so far are kept.")
        XCTAssertEqual(store.runs.count, 1)
        XCTAssertEqual(model.rows.map(\.summary), ["Keeps up", "Skipped: cancelled"])
        XCTAssertNil(model.failureAlert)
    }

    func testCancelBeforeAnyResultIsANoticeNotAFailure() async throws {
        try installReady([.tiny])
        fake.holdTranslate(of: .tiny)
        let model = makeModel()
        model.start()
        await waitFor("tiny's translate") { self.fake.events.value.contains("translate tiny") }
        model.cancel()
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(model.notice, "Stopped before any model was measured.")
        XCTAssertNil(model.failureAlert)
        XCTAssertEqual(store.runs.count, 0, "nothing measured, nothing saved")
    }

    func testBackgroundExpiryEndsTheTaskAtOnceAndStopsTheRun() async throws {
        try installReady([.tiny, .small])
        fake.holdTranslate(of: .tiny)
        let model = makeModel()
        model.start()
        await waitFor("tiny's translate") { self.fake.events.value.contains("translate tiny") }
        host.expireAll()
        XCTAssertEqual(host.ended, [1], "the background task is ended before iOS ends the process")
        XCTAssertEqual(model.state, .stopping)
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(host.ended, [1], "not ended twice")
        XCTAssertEqual(model.notice, "Stopped before any model was measured.")
    }

    func testNothingMeasuredRaisesTheFailureAlert() async throws {
        try installReady([.tiny, .small])
        fake.setThermal([.critical, .critical])
        let model = makeModel()
        model.start()
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(model.failureAlert, "Nothing measured: iPhone too hot")
        XCTAssertEqual(store.runs.count, 0)
        XCTAssertNil(model.notice)
    }

    func testNoSpeechRaisesTheFailureAlert() async throws {
        try installReady([.tiny])
        var seams = fake.seams
        seams.makeStimulus = { throw BenchmarkError.noSpeech }
        let model = BenchmarkViewModel(store: store, manager: manager, isPipelineRunning: { false }, releasePipeline: {},
                                       runner: BenchmarkRunner(seams: seams), host: host)
        model.start()
        await waitUntil("run finished", timeout: 5) { model.state == .idle }
        XCTAssertEqual(model.failureAlert, "The iPhone's voice produced no audio for the sentence. Check Settings › Accessibility › Spoken Content › Voices and try again.")
        XCTAssertEqual(store.runs.count, 0)
        XCTAssertEqual(host.ended, [1], "the background task is still ended")
    }

    // MARK: Pure text

    func testRowsForRun() {
        let rows = BenchmarkViewModel.rows(for: .sample())
        XCTAssertEqual(rows.map(\.name), ["tiny", "small", "medium"])
        XCTAssertEqual(rows[1].summary, "Keeps up")
        XCTAssertEqual(rows[1].symbol, "checkmark.circle")
        XCTAssertEqual(rows[1].detail, "4.2× faster than real time · loads in 3 s · 88 % of words right · uses 240 MB")
        XCTAssertEqual(rows[1].spokenText, "small. Keeps up. 4.2 times faster than real time. loads in 3 seconds. 88 % of words right. uses 240 megabytes")
        XCTAssertEqual(rows[2].summary, "Skipped: iPhone too hot")
        XCTAssertEqual(rows[2].symbol, "minus.circle")
        XCTAssertNil(rows[2].detail)
        XCTAssertEqual(rows[2].spokenText, "medium. Skipped: iPhone too hot")
    }

    func testFooterAndLastRunText() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(BenchmarkViewModel.footerText(run: .sample(), languageName: "Spanish", timeZone: utc),
                       "Measured on this iPhone on 14 November 2023 with the Spanish sentence. Accuracy is against one short sentence read by the iPhone's own voice: a guide, not a score.")
        XCTAssertEqual(BenchmarkViewModel.lastRunText(run: .sample(), timeZone: utc), "Last run: 14 November 2023 · iPhone17,1 · iOS 26.0.1")
        XCTAssertEqual(BenchmarkViewModel.stoppedEarlyText(measured: 1, of: 3), "Stopped after 1 of 3 models; the results so far are kept.")
    }

    func testStatusTextPerProgress() {
        XCTAssertEqual(BenchmarkViewModel.statusText(.synthesising), "Reading the sentence with the iPhone's voice")
        XCTAssertEqual(BenchmarkViewModel.statusText(.loading(.small, WhisperKitTranslator.preparingMessage)), "Testing small: Preparing model…")
        XCTAssertEqual(BenchmarkViewModel.statusText(.translating(.small, pass: 2)), "Testing small: translating, pass 2 of 2")
        XCTAssertEqual(BenchmarkViewModel.statusText(.finished(.small)), "Testing small: done")
        XCTAssertEqual(BenchmarkViewModel.statusText(.skipped(.medium, BenchmarkSkipReason.tooHot)), "Testing medium: skipped, iPhone too hot")
    }

    func testTheScreenStrings() {
        XCTAssertEqual(BenchmarkViewModel.title, "Benchmark")
        XCTAssertEqual(BenchmarkViewModel.linkTitle, "Benchmark this iPhone")
        XCTAssertEqual(BenchmarkViewModel.runButtonTitle, "Run benchmark")
        XCTAssertEqual(BenchmarkViewModel.shareTitle, "Share results")
        XCTAssertEqual(BenchmarkViewModel.cancelTitle, "Cancel")
        XCTAssertEqual(BenchmarkViewModel.keepOpenText, "Keep ReVox open and the screen on; a large model can take a minute")
        XCTAssertEqual(BenchmarkViewModel.noResultsText, "Not measured yet. Until then the Models screen recommends by memory size.")
        XCTAssertEqual(BenchmarkViewModel.refusedAlertTitle, "Can't run now")
        XCTAssertEqual(BenchmarkViewModel.failedAlertTitle, "Benchmark failed")
        XCTAssertEqual(BenchmarkError.busy.description, "Finish or cancel the benchmark first")
        XCTAssertEqual(BenchmarkError.liveBlocked.description, "Finish or cancel the benchmark in Settings › Models before starting")
        XCTAssertEqual(BenchmarkError.nothingMeasured("cancelled").description, "Nothing measured: cancelled")
    }
}
