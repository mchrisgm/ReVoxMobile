import XCTest
import SwiftUI
import ReVoxCore
@testable import ReVoxMobile

/// M11 §5: the Benchmark screen lays out in every state, the Models screen hosts its entry row and the measured
/// note, and `AppEnvironment` wires the store, the screen and the Live gate.
@MainActor
final class BenchmarkHostingTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var settings: SettingsStore!
    private var host: FakeInstallHost!
    private var verifiedLoads: VerifiedLoadRecord!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxBenchmarkHost-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        settings = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        host = FakeInstallHost()
        verifiedLoads = VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxBenchmarkHost-\(UUID().uuidString)")!)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func manager(pipelineRunning: Bool = false) -> ModelManager {
        let installer = ModelInstaller(layout: layout, steps: FakeInstallSteps().steps(layout: layout), verifiedLoads: verifiedLoads)
        return ModelManager(layout: layout, installer: installer, isPipelineRunning: { pipelineRunning },
                            availableBytes: { 50_000_000_000 }, host: host)
    }

    private func store(run: BenchmarkRun? = nil) throws -> BenchmarkStore {
        let store = BenchmarkStore(directory: root.appendingPathComponent("Benchmarks", isDirectory: true),
                                   host: BenchmarkHost(device: "iPhone17,1", iOSVersion: "26.0.1", memoryTierGB: 8))
        if let run { try store.save(run) }
        return store
    }

    private func benchmark(run: BenchmarkRun? = nil, pipelineRunning: Bool = false, seams: FakeBenchmarkSeams = FakeBenchmarkSeams()) throws -> BenchmarkViewModel {
        BenchmarkViewModel(store: try store(run: run), manager: manager(pipelineRunning: pipelineRunning),
                           isPipelineRunning: { pipelineRunning }, releasePipeline: {},
                           runner: BenchmarkRunner(seams: seams.seams), host: host)
    }

    private func hostView<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    func testBenchmarkViewHostsInEveryState() async throws {
        let idle = try benchmark()                                   // no results: "Download a Whisper model first"
        hostView(NavigationStack { BenchmarkView(model: idle) })
        let withResults = try benchmark(run: .sample())              // two measured rows and a skipped one
        hostView(NavigationStack { BenchmarkView(model: withResults) })
        let refused = try benchmark(pipelineRunning: true)           // the refusal footer
        hostView(NavigationStack { BenchmarkView(model: refused) })
        hostView(NavigationStack { BenchmarkView(model: withResults) }.environment(\.dynamicTypeSize, .accessibility5))

        // Files plus the verified-load record: `isWhisperReady` needs both, and without the record the run refused
        // itself before the first seam was touched (M11 review), so the "running" hosting never saw a run.
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        verifiedLoads.record(.whisper(.tiny))
        let seams = FakeBenchmarkSeams()
        seams.holdTranslate(of: .tiny)
        let running = try benchmark(seams: seams)
        running.start()
        XCTAssertEqual(running.state, .running(BenchmarkViewModel.synthesisingText))
        hostView(NavigationStack { BenchmarkView(model: running) })                               // progress row + Cancel
        await waitFor("tiny's translate") { seams.events.value.contains("translate tiny") }
        XCTAssertNil(running.refusedAlert, "the run really started")
        running.cancel()
        hostView(NavigationStack { BenchmarkView(model: running) })                               // "Stopping…"
        seams.releaseTranslate(of: .tiny)
        await waitUntil("run finished", timeout: 5) { running.state == .idle }
        XCTAssertTrue(seams.events.value.contains("load tiny"))

        for row in BenchmarkViewModel.rows(for: .sample()) {
            hostView(List { BenchmarkRowView(row: row) })
        }
    }

    func testModelsViewHostsTheBenchmarkRowAndTheMeasuredNote() throws {
        try FakeInstallSteps.fabricateWhisper(.tiny, in: layout)
        try FakeInstallSteps.fabricateWhisper(.small, in: layout)
        let store = try store(run: .sample())
        let models = ModelsViewModel(manager: manager(), settings: settings, deviceInfo: DeviceInfo(physicalMemoryBytes: 8 * 1_073_741_824),
                                     isPipelineRunning: { false }, benchmarks: store)
        models.benchmark = try benchmark()
        XCTAssertEqual(models.rows.filter(\.isRecommended).map(\.id), [.small])
        XCTAssertEqual(models.rows[2].measuredNote, "Measured on this iPhone on \(BenchmarkVerdict.dateText(Date(timeIntervalSince1970: 1_700_000_000)))")
        hostView(NavigationStack { ModelsView(model: models) })

        let measuredRow = ModelRow(id: .small, name: "small", sizeText: "487 MB", isRecommended: true, isSuitable: true, warning: nil, note: nil,
                                   state: ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: 1), isSelected: true,
                                   measuredNote: "Measured on this iPhone on 14 November 2023")
        hostView(List { ModelRowView(row: measuredRow, onDownload: {}, onCancel: {}, onSelect: {}) })
        XCTAssertEqual(ModelRowView.accessibilityText(for: measuredRow),
                       "Model small. 487 MB. Installed. Recommended. Measured on this iPhone on 14 November 2023")

        let plain = ModelRow(id: .base, name: "base", sizeText: "145 MB", isRecommended: false, isSuitable: true, warning: nil, note: nil,
                             state: ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: 1), isSelected: false)
        XCTAssertNil(plain.measuredNote, "the default keeps every earlier construction site and sentence unchanged")
        XCTAssertEqual(ModelRowView.accessibilityText(for: plain), "Model base. 145 MB. Installed")
    }

    // MARK: AppEnvironment wiring (benchmark only)

    func testTestingEnvironmentWiresTheStoreTheScreenAndTheModelsEntry() throws {
        let environment = try AppEnvironment.testing(root: root.appendingPathComponent("env", isDirectory: true))
        XCTAssertEqual(environment.benchmarks.directory.lastPathComponent, "Benchmarks")
        XCTAssertEqual(environment.benchmarks.directory.deletingLastPathComponent().lastPathComponent, "env")
        XCTAssertNil(environment.benchmarks.latest)
        XCTAssertFalse(environment.benchmark.canRun)
        XCTAssertEqual(environment.benchmark.whyNotText, "Download a Whisper model first")
        XCTAssertTrue(environment.models.benchmark === environment.benchmark, "the Models screen pushes the app's one Benchmark screen")
        XCTAssertEqual(environment.models.benchmarkFooterText, ModelsViewModel.notMeasuredFooterText)
        XCTAssertTrue(environment.models.canDownload)
    }

    func testLiveStartIsRefusedWhileABenchmarkRuns() async throws {
        let built = LockedBox(0)
        let inner: PipelineSupplier = { _, _ in
            built.mutate { $0 += 1 }
            return FakeLivePipeline()
        }
        let running = LockedBox(true)
        let gated = AppEnvironment.gated(inner, isBenchmarkRunning: { running.value })
        do {
            _ = try await gated(Settings(), { _ in })
            XCTFail("expected liveBlocked")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .liveBlocked)
            XCTAssertEqual(UserFacingErrorText.describe(error), "Finish or cancel the benchmark in Settings › Models before starting")
        }
        XCTAssertEqual(built.value, 0, "no pipeline was built beside the benchmark")
        running.mutate { $0 = false }
        _ = try await gated(Settings(), { _ in })
        XCTAssertEqual(built.value, 1)
    }
}
