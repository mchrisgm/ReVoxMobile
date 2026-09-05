import Foundation
import Observation
import ReVoxCore

@MainActor
@Observable
final class ModelsViewModel {
    static let keepOpenText = "Keep ReVox open while downloading"
    static let stopToDeleteText = "Stop translation to delete models"
    /// M10: verifying a download is a full WhisperKit load; two models resident beside a running session is what
    /// the §9 memory rows exist to prevent, so a download waits for the session to stop.
    static let stopToDownloadText = "Stop translation to download models"
    static let notRecommendedText = "Not recommended for this iPhone"
    static let confirmDeleteMessage = "You can download it again later."
    static let vadName = "Voice detector"
    static let noModelsText = "No models on this iPhone"
    /// M11: a download or delete is a full model load or unload beside the one the benchmark is timing.
    static let finishBenchmarkText = "Finish or cancel the benchmark first"
    static let notMeasuredFooterText = "Recommended by memory size. Run the benchmark to measure this iPhone."

    private let manager: ModelManager
    private let settings: SettingsStore
    private let deviceInfo: DeviceInfo
    private let benchmarks: BenchmarkStore?
    private let isPipelineRunning: @MainActor () -> Bool
    private let isBenchmarkRunning: @MainActor () -> Bool
    /// M11: the Benchmark screen the Models screen pushes; `AppEnvironment` sets it once both exist.
    var benchmark: BenchmarkViewModel?
    var lowStorageAlert: String?
    /// A delete the manager refused — the pipeline started while the confirmation dialog was open (§6.9).
    var deleteFailureAlert: String?
    var lowStorageWarning: String?
    /// Set only when a failure follows the user's own Download / Resume / Retry (§8.8); the row state is the other surface.
    var downloadFailureAlert: String?
    /// M10: the "Can't download now" alert; only the running-session refusal produces it.
    var downloadRefusedAlert: String?
    @ObservationIgnored private var awaitingUserResult: Set<WhisperModelID> = []

    init(manager: ModelManager, settings: SettingsStore, deviceInfo: DeviceInfo, isPipelineRunning: @escaping @MainActor () -> Bool,
         benchmarks: BenchmarkStore? = nil, isBenchmarkRunning: @escaping @MainActor () -> Bool = { false }) {
        self.manager = manager
        self.settings = settings
        self.deviceInfo = deviceInfo
        self.benchmarks = benchmarks
        self.isPipelineRunning = isPipelineRunning
        self.isBenchmarkRunning = isBenchmarkRunning
        manager.onActiveModelDeleted = { [weak self] replacement in
            guard let self, let replacement else { return }   // none left: the setting stays; Live shows "No model"
            self.settings.update { $0.model = replacement.rawValue }
        }
    }

    // MARK: Rows

    var selectedModel: WhisperModelID { settings.settings.whisperModel }

    // MARK: M11: the measured recommendation

    /// The latest run's measured results for the models on disk now: a deleted model's result stops counting.
    var measuredResults: [ModelBenchmarkResult] {
        guard let run = benchmarks?.latest else { return [] }
        let installed = manager.installedWhisper
        return run.measured.filter { installed.contains($0.model) }
    }

    /// The benchmark's pick, when one qualifies; nil means the memory tier decides.
    var measuredRecommendation: WhisperModelID? {
        DeviceRecommendation.bestMeasured(memory: deviceInfo.recommendation, results: measuredResults)
    }

    /// The memory tier with `recommended` moved to the measured pick; the memory tier alone until a run qualifies.
    var recommendation: DeviceRecommendation {
        DeviceRecommendation.measured(memory: deviceInfo.recommendation, results: measuredResults)
    }

    /// "Measured on this iPhone on 14 November 2023" for the recommended row, once the recommendation is measured.
    var measuredNote: String? {
        guard measuredRecommendation != nil, let date = benchmarks?.latest?.date else { return nil }
        return Self.measuredNoteText(date: date)
    }

    /// The Benchmark section's footer: the memory-size note, or when the recommendation was measured.
    var benchmarkFooterText: String {
        guard measuredRecommendation != nil, let date = benchmarks?.latest?.date else { return Self.notMeasuredFooterText }
        return Self.measuredFooterText(date: date)
    }

    static func measuredNoteText(date: Date, timeZone: TimeZone = .current) -> String {
        "Measured on this iPhone on \(BenchmarkVerdict.dateText(date, timeZone: timeZone))"
    }

    static func measuredFooterText(date: Date, timeZone: TimeZone = .current) -> String {
        "Recommendation measured on this iPhone on \(BenchmarkVerdict.dateText(date, timeZone: timeZone))"
    }

    var rows: [ModelRow] {
        let recommendation = self.recommendation
        let measuredNote = self.measuredNote
        return ModelCatalog.whisperModels.map { descriptor in
            let kind = DownloadKind.whisper(descriptor.id)
            let state = manager.state(for: kind)
            return ModelRow(
                id: descriptor.id,
                name: descriptor.id.displayName,
                sizeText: Self.rowSizeText(catalogBytes: descriptor.approximateBytes, state: state, measuredBytes: manager.storage.bytes(for: kind)),
                isRecommended: recommendation.recommended == descriptor.id,
                isSuitable: recommendation.suitable.contains(descriptor.id),
                warning: recommendation.warnings[descriptor.id],
                note: descriptor.note,
                state: state,
                isSelected: descriptor.id == selectedModel,
                measuredNote: recommendation.recommended == descriptor.id ? measuredNote : nil
            )
        }
    }

    var vadRow: VADRow {
        let state = manager.state(for: .vad)
        return VADRow(name: Self.vadName,
                      sizeText: Self.rowSizeText(catalogBytes: ModelCatalog.vad.approximateBytes, state: state, measuredBytes: manager.storage.bytes(for: .vad)),
                      state: state,
                      noticeText: manager.upstreamChangeText(for: .vad))
    }

    var canDelete: Bool { !isPipelineRunning() && !isBenchmarkRunning() }
    var canDownload: Bool { !isPipelineRunning() && !isBenchmarkRunning() }

    var footerText: String? {
        if manager.hasActiveDownload || !manager.pausedKinds.isEmpty { return Self.keepOpenText }
        if isBenchmarkRunning() { return Self.finishBenchmarkText }
        if !canDelete { return Self.stopToDeleteText }
        return nil
    }

    /// §8.3 footer (M7): the total ReVox's models occupy and the free space of the volume (DiskSpace reason 85F4.1).
    var storageFooterText: String { Self.storageFooterText(for: manager.storage) }

    // MARK: Actions

    func download(_ id: WhisperModelID) {
        lowStorageWarning = nil
        guard canDownload else {
            downloadRefusedAlert = isBenchmarkRunning() ? Self.finishBenchmarkText : Self.stopToDownloadText
            return
        }
        switch manager.freeSpaceVerdict(for: .whisper(id)) {
        case .refuse(let message):
            lowStorageAlert = message
            return
        case .lowRemaining(let remaining):
            lowStorageWarning = "Only \(ModelManager.gigabytesText(remaining)) will remain after this download"
        case .ok:
            break
        }
        awaitingUserResult.insert(id)
        manager.install(.whisper(id))
    }

    func cancel(_ id: WhisperModelID) {
        awaitingUserResult.remove(id)
        manager.cancel(.whisper(id))
    }

    func select(_ id: WhisperModelID) {
        guard manager.installedWhisper.contains(id) else { return }
        settings.update { $0.model = id.rawValue }
    }

    /// Behind the screen's `confirmationDialog`; the manager refuses while the pipeline runs (§6.9).
    func delete(_ id: WhisperModelID) throws {
        guard !isBenchmarkRunning() else { throw BenchmarkError.busy }
        try manager.delete(.whisper(id), activeModel: selectedModel)
    }

    /// What the confirmation dialog calls. `delete(_:)` keeps throwing for callers that handle the error themselves.
    func deleteConfirmed(_ id: WhisperModelID) {
        deleteFailureAlert = nil
        do {
            try delete(id)
        } catch {
            deleteFailureAlert = Self.deleteFailureText(error)
        }
    }

    /// `ModelManagerError` is `CustomStringConvertible` ("Stop translation to delete models"); anything else prints itself.
    static func deleteFailureText(_ error: Error) -> String { String(describing: error) }

    func applicationDidBecomeActive() {
        manager.applicationDidBecomeActive()
    }

    /// Called by the screen whenever the rows change. A `.failed` state that a user action was awaiting raises the
    /// alert once; `.installed`/`.idle` clear the flag; `.paused` clears it because the §6.9 auto-resume that follows
    /// is not user-initiated, so its failure stays on the row.
    func reconcileFailures() {
        for id in awaitingUserResult {
            switch manager.state(for: .whisper(id)).phase {
            case .failed(let message):
                awaitingUserResult.remove(id)
                downloadFailureAlert = Self.downloadFailureText(name: id.displayName, message: message)
            case .installed, .idle, .paused:
                awaitingUserResult.remove(id)
            case .listing, .downloading, .compiling, .verifying:
                break
            }
        }
    }

    static func downloadFailureText(name: String, message: String) -> String {
        "Couldn't download \(name): \(message)"
    }

    // MARK: Text

    static func sizeText(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "≈ %.1f GB", Double(bytes) / 1_000_000_000)
        }
        let megabytes = max(1, Int((Double(bytes) / 1_000_000).rounded()))
        return "≈ \(megabytes) MB"
    }

    /// Installed rows show what is on disk; every other row shows the catalog estimate ("≈ N MB").
    static func rowSizeText(catalogBytes: Int64, state: ModelDownloadState, measuredBytes: Int64?) -> String {
        if state.phase == .installed, let measuredBytes { return measuredSizeText(measuredBytes) }
        return sizeText(catalogBytes)
    }

    static func measuredSizeText(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1_000_000_000) }
        if bytes >= 1_000_000 { return "\(Int((Double(bytes) / 1_000_000).rounded())) MB" }
        return "under 1 MB"
    }

    static func storageFooterText(for usage: ModelStorageUsage) -> String {
        let used = usage.totalBytes > 0 ? "ReVox models: \(measuredSizeText(usage.totalBytes))" : noModelsText
        guard let free = usage.freeBytes else { return used }
        return "\(used) · Free: \(ModelManager.gigabytesText(free))"
    }

    static func confirmDeleteTitle(_ id: WhisperModelID) -> String {
        "Delete \(id.displayName) (\(sizeText(ModelCatalog.whisper(id).approximateBytes)))?"
    }

    static func phaseText(_ phase: ModelDownloadPhase) -> String {
        switch phase {
        case .idle: return "Not downloaded"
        case .listing: return "Listing files"
        case .downloading(let completed?, let total?): return "Downloading \(completed) of \(total) files"
        case .downloading: return "Downloading"
        case .compiling(let name?): return "Preparing \(name)"
        case .compiling(nil): return "Preparing"
        case .verifying: return "Verifying"
        case .installed: return "Installed"
        case .paused: return "Paused"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
