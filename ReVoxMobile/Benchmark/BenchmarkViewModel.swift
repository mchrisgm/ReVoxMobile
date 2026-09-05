import Foundation
import Observation
import ReVoxCore

enum BenchmarkRunState: Equatable, Sendable {
    case idle
    case running(String)
    case stopping
}

/// One row of the Results section: the model, its verdict and the four measurements as text.
struct BenchmarkRow: Identifiable, Equatable {
    let id: WhisperModelID
    let name: String
    let summary: String
    let symbol: String
    /// The verdict line for a measured model; nil for a skipped one (its `summary` says why).
    let detail: String?
    let spokenText: String
}

/// The Benchmark screen's state and gating (M11 §5): Settings › Models › Benchmark this iPhone.
@MainActor
@Observable
final class BenchmarkViewModel {
    static let title = "Benchmark"
    static let linkTitle = "Benchmark this iPhone"
    static let linkHint = "Times every installed model on this iPhone"
    static let introText = "ReVox reads a short sentence aloud with the iPhone's own voice, silently, and times each installed model translating it. Nothing leaves the phone."
    static let exampleText = "A model 3× faster than real time finishes a 4-second phrase in about 1.3 seconds. Below 2× the transcript falls behind in a quick conversation."
    static let runButtonTitle = "Run benchmark"
    static let runButtonHint = "Times every installed model translating one sentence; up to a minute per model"
    static let cancelTitle = "Cancel"
    static let cancelHint = "Stops after the current step and keeps the results so far"
    static let shareTitle = "Share results"
    static let shareHint = "Shares the results as text"
    static let stopToBenchmarkText = "Stop translation to run the benchmark"
    static let waitForDownloadText = "Wait for the download to finish first"
    static let noReadyModelsText = "Download a Whisper model first"
    static let keepOpenText = "Keep ReVox open and the screen on; a large model can take a minute"
    static let synthesisingText = "Reading the sentence with the iPhone's voice"
    static let stoppingText = "Stopping after the current step…"
    static let resultsHeader = "Results"
    static let noResultsText = "Not measured yet. Until then the Models screen recommends by memory size."
    static let stoppedBeforeAnyText = "Stopped before any model was measured."
    static let refusedAlertTitle = "Can't run now"
    static let failedAlertTitle = "Benchmark failed"
    static let backgroundTaskName = "ReVox model benchmark"

    private let store: BenchmarkStore
    private let manager: ModelManager
    private let isPipelineRunning: @MainActor () -> Bool
    private let releasePipeline: @MainActor () async -> Void
    private let runner: BenchmarkRunner
    private let host: any InstallHost
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Int?
    private let timeZone: TimeZone

    private(set) var state: BenchmarkRunState = .idle
    var refusedAlert: String?
    var failureAlert: String?
    var notice: String?

    init(store: BenchmarkStore, manager: ModelManager, isPipelineRunning: @escaping @MainActor () -> Bool,
         releasePipeline: @escaping @MainActor () async -> Void, runner: BenchmarkRunner, host: any InstallHost,
         timeZone: TimeZone = .current) {
        self.store = store
        self.manager = manager
        self.isPipelineRunning = isPipelineRunning
        self.releasePipeline = releasePipeline
        self.runner = runner
        self.host = host
        self.timeZone = timeZone
    }

    // MARK: Gating

    var isRunning: Bool { state != .idle }

    /// Why the Run button would be refused, in the order the reasons are checked; nil when it can run.
    var whyNotText: String? {
        if isPipelineRunning() { return Self.stopToBenchmarkText }
        if manager.hasActiveDownload { return Self.waitForDownloadText }
        if manager.installedWhisper.isEmpty { return Self.noReadyModelsText }
        return nil
    }

    var canRun: Bool { !isRunning && whyNotText == nil }

    // MARK: Results

    var latest: BenchmarkRun? { store.latest }

    var rows: [BenchmarkRow] { latest.map(Self.rows(for:)) ?? [] }

    var shareText: String? { latest.map(BenchmarkReport.markdown) }

    var resultsFooterText: String? {
        latest.map { Self.footerText(run: $0, languageName: LanguageCatalog.displayName($0.sentence.language, whenNil: ""), timeZone: timeZone) }
    }

    var lastRunText: String? { latest.map { Self.lastRunText(run: $0, timeZone: timeZone) } }

    static func rows(for run: BenchmarkRun) -> [BenchmarkRow] {
        run.results.map { result in
            BenchmarkRow(id: result.model, name: result.model.displayName, summary: BenchmarkVerdict.summaryText(result),
                         symbol: BenchmarkVerdict.summarySymbol(result), detail: result.isSkipped ? nil : BenchmarkVerdict.line(result),
                         spokenText: BenchmarkVerdict.spokenText(result))
        }
    }

    // MARK: Actions

    /// The Models pattern (enabled button, refusal in an alert): `start()` refuses with `whyNotText`. The state flips
    /// to running before the first `await`, so a second tap and the Models screen's download gate see it at once.
    func start() {
        guard !isRunning else { return }
        if let reason = whyNotText {
            refusedAlert = reason
            return
        }
        notice = nil
        state = .running(Self.synthesisingText)
        let installed = manager.installedWhisper
        task = Task { [weak self] in
            guard let self else { return }
            await self.perform(installed: installed)
        }
    }

    /// Stops after the current step; the results so far are kept.
    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        state = .stopping
    }

    private func perform(installed: [WhisperModelID]) async {
        defer { endRun() }
        var ready: [WhisperModelID] = []
        for id in installed {
            let isReady = await manager.isWhisperReady(id)
            if isReady { ready.append(id) }
        }
        guard !ready.isEmpty else {
            refusedAlert = Self.noReadyModelsText
            return
        }
        // Live may have started during the readiness awaits; a second WhisperKit beside its model is what §9 forbids.
        guard !isPipelineRunning() else {
            refusedAlert = Self.stopToBenchmarkText
            return
        }
        await releasePipeline()
        backgroundTask = host.beginBackgroundTask(name: Self.backgroundTaskName) { [weak self] in
            self?.backgroundTimeExpired()
        }
        host.isIdleTimerDisabled = true
        do {
            let outcome = try await runner.run(models: ready) { [weak self] progress in
                Task { @MainActor in self?.apply(progress) }
            }
            finish(outcome, total: ready.count)
        } catch {
            failureAlert = UserFacingErrorText.describe(error)
        }
    }

    private func apply(_ progress: BenchmarkProgress) {
        guard case .running = state else { return }   // "Stopping…" stays until the run returns
        state = .running(Self.statusText(progress))
    }

    private func finish(_ outcome: BenchmarkOutcome, total: Int) {
        guard outcome.measuredCount > 0 else {
            if outcome.cancelledCount == outcome.results.count {
                notice = Self.stoppedBeforeAnyText
            } else {
                failureAlert = BenchmarkError.nothingMeasured(outcome.results.first?.skippedReason ?? "").description
            }
            return
        }
        let run = BenchmarkRun(date: Date(), device: store.host.device, iOSVersion: store.host.iOSVersion,
                               memoryTierGB: store.host.memoryTierGB, whisperKitVersion: store.whisperKitVersion,
                               sentence: outcome.sentence, results: outcome.results)
        do {
            try store.save(run)
        } catch {
            failureAlert = UserFacingErrorText.describe(error)
        }
        if outcome.cancelledCount > 0 {
            notice = Self.stoppedEarlyText(measured: outcome.measuredCount, of: total)
        }
    }

    /// iOS ran out of background time: a WhisperKit load cannot be interrupted, so the task is cancelled (the runner
    /// marks the rest cancelled at its next check) and the background task is ended now, before iOS ends the process.
    private func backgroundTimeExpired() {
        task?.cancel()
        if let identifier = backgroundTask {
            host.endBackgroundTask(identifier)
            backgroundTask = nil
        }
        if isRunning { state = .stopping }
    }

    private func endRun() {
        if let identifier = backgroundTask {
            host.endBackgroundTask(identifier)
            backgroundTask = nil
        }
        host.isIdleTimerDisabled = manager.hasActiveDownload
        task = nil
        state = .idle
    }

    // MARK: Text

    static func testingText(_ id: WhisperModelID, _ message: String) -> String { "Testing \(id.displayName): \(message)" }
    static func translatingText(_ id: WhisperModelID, pass: Int) -> String { "Testing \(id.displayName): translating, pass \(pass) of \(BenchmarkRunner.passes)" }
    static func doneText(_ id: WhisperModelID) -> String { "Testing \(id.displayName): done" }
    static func skippedText(_ id: WhisperModelID, _ reason: String) -> String { "Testing \(id.displayName): skipped, \(reason)" }

    static func statusText(_ progress: BenchmarkProgress) -> String {
        switch progress {
        case .synthesising: return synthesisingText
        case .loading(let id, let message): return testingText(id, message)
        case .translating(let id, let pass): return translatingText(id, pass: pass)
        case .finished(let id): return doneText(id)
        case .skipped(let id, let reason): return skippedText(id, reason)
        }
    }

    static func stoppedEarlyText(measured: Int, of total: Int) -> String {
        "Stopped after \(measured) of \(total) models; the results so far are kept."
    }

    static func footerText(run: BenchmarkRun, languageName: String, timeZone: TimeZone = .current) -> String {
        "Measured on this iPhone on \(BenchmarkVerdict.dateText(run.date, timeZone: timeZone)) with the \(languageName) sentence. Accuracy is against one short sentence read by the iPhone's own voice: a guide, not a score."
    }

    /// "Last run: 14 November 2023 · iPhone17,1 · iOS 26.0.1" — the date and device of the last run.
    static func lastRunText(run: BenchmarkRun, timeZone: TimeZone = .current) -> String {
        "Last run: \(BenchmarkVerdict.dateText(run.date, timeZone: timeZone)) · \(run.device) · iOS \(run.iOSVersion)"
    }
}
