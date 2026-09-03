import Foundation
import Observation
import ReVoxCore

enum ModelManagerError: Error, Equatable, CustomStringConvertible {
    case pipelineRunning
    case notEnoughSpace(String)

    var description: String {
        switch self {
        case .pipelineRunning:
            return "Stop translation to delete models"
        case .notEnoughSpace(let message):
            return message
        }
    }
}

enum FreeSpaceVerdict: Equatable {
    case ok
    case lowRemaining(remainingBytes: Int64)
    case refuse(message: String)
}

/// The observable owner of every model row (§6.9, §8.3). Installs run in one `Task` per kind; every
/// state change lands on the main actor.
@MainActor
@Observable
final class ModelManager {
    /// Warn (not refuse) when less than this would remain after the install (ASSUMED, measured in M7).
    static let lowRemainingThreshold: Int64 = 1_000_000_000

    let layout: ModelLayout
    let installer: ModelInstaller
    private let isPipelineRunning: @MainActor () -> Bool
    private let availableBytes: @MainActor () -> Int64?

    private(set) var states: [DownloadKind: ModelDownloadState] = [:]
    private(set) var installedWhisper: [WhisperModelID] = []
    private(set) var vadInstalled = false
    /// Called after the active Whisper model was deleted with the smallest installed model, or nil.
    var onActiveModelDeleted: (@MainActor (WhisperModelID?) -> Void)?

    @ObservationIgnored private var tasks: [DownloadKind: Task<Void, Never>] = [:]

    @ObservationIgnored private let host: any InstallHost
    @ObservationIgnored private var backgroundTasks: [DownloadKind: Int] = [:]
    @ObservationIgnored private var expired: Set<DownloadKind> = []
    /// Downloads interrupted by background-task expiration; resumed on `applicationDidBecomeActive()`.
    private(set) var pausedKinds: Set<DownloadKind> = []

    init(layout: ModelLayout, installer: ModelInstaller, isPipelineRunning: @escaping @MainActor () -> Bool,
         availableBytes: (@MainActor () -> Int64?)? = nil, host: (any InstallHost)? = nil) {
        self.layout = layout
        self.installer = installer
        self.isPipelineRunning = isPipelineRunning
        self.availableBytes = availableBytes ?? { layout.availableCapacityBytes() }
        self.host = host ?? UIApplicationInstallHost()
        refreshInstalledStates()
    }

    // MARK: State

    func state(for kind: DownloadKind) -> ModelDownloadState {
        states[kind] ?? .idle(bytesExpected: ModelCatalog.download(for: kind).expectedBytes)
    }

    var hasActiveDownload: Bool {
        states.values.contains { $0.phase.isActive }
    }

    /// Re-reads the disk: installed rows become `.installed`, everything else not in flight becomes `.idle`.
    func refreshInstalledStates() {
        installedWhisper = layout.installedWhisperModels()
        vadInstalled = layout.isVADInstalled()
        for id in WhisperModelID.allCases {
            let kind = DownloadKind.whisper(id)
            guard tasks[kind] == nil, !pausedKinds.contains(kind) else { continue }
            setState(kind, phase: installedWhisper.contains(id) ? .installed : .idle, fraction: installedWhisper.contains(id) ? 1 : nil)
        }
        if tasks[.vad] == nil, !pausedKinds.contains(.vad) {
            setState(.vad, phase: vadInstalled ? .installed : .idle, fraction: vadInstalled ? 1 : nil)
        }
    }

    private func setState(_ kind: DownloadKind, phase: ModelDownloadPhase, fraction: Double?) {
        states[kind] = ModelDownloadState(phase: phase, fraction: fraction, bytesExpected: ModelCatalog.download(for: kind).expectedBytes)
    }

    // MARK: Free space (§6.9, DiskSpace reason E174.1)

    static func gigabytesText(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    static func freeSpaceVerdict(expectedBytes: Int64, availableBytes: Int64?) -> FreeSpaceVerdict {
        guard let available = availableBytes else { return .ok }
        guard ModelCatalog.hasRoomToInstall(expectedBytes: expectedBytes, availableBytes: available) else {
            let needed = Int64(Double(expectedBytes) * 1.25) + 200_000_000
            return .refuse(message: "Not enough space: needs about \(gigabytesText(needed)), \(gigabytesText(available)) free")
        }
        let remaining = available - expectedBytes
        if remaining < lowRemainingThreshold {
            return .lowRemaining(remainingBytes: remaining)
        }
        return .ok
    }

    func freeSpaceVerdict(for kind: DownloadKind) -> FreeSpaceVerdict {
        Self.freeSpaceVerdict(expectedBytes: ModelCatalog.download(for: kind).expectedBytes, availableBytes: availableBytes())
    }

    // MARK: Install / cancel

    func install(_ kind: DownloadKind) {
        guard tasks[kind] == nil else { return }
        if case .refuse(let message) = freeSpaceVerdict(for: kind) {
            setState(kind, phase: .failed(message), fraction: nil)
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runInstall(kind)
        }
        tasks[kind] = task
        didStartTask(for: kind)
    }

    /// Runs one install to completion, then the automatic VAD install after a Whisper install (§8.3).
    private func runInstall(_ kind: DownloadKind) async {
        let installer = self.installer
        let report: @Sendable (ModelDownloadState) -> Void = { [weak self] state in
            Task { @MainActor in self?.states[kind] = state }
        }
        do {
            switch kind {
            case .whisper(let id):
                try await installer.installWhisper(id, progress: report)
            case .vad:
                try await installer.installVAD(progress: report)
            case .pocketTTS:
                break   // M4
            }
            finishTask(for: kind, cancelled: false)
            if case .whisper = kind, !layout.isVADInstalled(), tasks[.vad] == nil {
                install(.vad)
            }
        } catch is CancellationError {
            finishTask(for: kind, cancelled: true)
        } catch {
            // `.failed` was already reported by the installer; keep it on screen (Retry re-installs).
            tasks[kind] = nil
            didEndTask(for: kind)
        }
    }

    private func finishTask(for kind: DownloadKind, cancelled: Bool) {
        tasks[kind] = nil
        didEndTask(for: kind)
        if cancelled, cancelledByExpiration(kind) {
            return   // the row is now .paused (Task 26)
        }
        refreshInstalledStates()
    }

    func cancel(_ kind: DownloadKind) {
        if pausedKinds.remove(kind) != nil {
            refreshInstalledStates()
            return
        }
        tasks[kind]?.cancel()
    }

    // MARK: Delete (§6.9: idle only; the confirmation lives in the screen)

    func delete(_ kind: DownloadKind, activeModel: WhisperModelID) throws {
        guard !isPipelineRunning() else { throw ModelManagerError.pipelineRunning }
        guard tasks[kind] == nil else { return }
        switch kind {
        case .whisper(let id):
            try installer.deleteWhisperSync(id)
            refreshInstalledStates()
            if id == activeModel {
                onActiveModelDeleted?(installedWhisper.first)
            }
        case .vad:
            installer.deleteVADSync()
            refreshInstalledStates()
        case .pocketTTS:
            break   // M4
        }
    }

    // MARK: Readiness

    func isWhisperReady(_ id: WhisperModelID) async -> Bool {
        await installer.isWhisperReady(id)
    }

    func isVADReady() async -> Bool {
        await installer.isVADReady()
    }

    // MARK: Backgrounding (§6.9)

    static func backgroundTaskName(for kind: DownloadKind) -> String {
        switch kind {
        case .whisper(let id): return "ReVox model install whisper.\(id.rawValue)"
        case .vad: return "ReVox model install vad"
        case .pocketTTS: return "ReVox model install pocketTTS"
        }
    }

    func didStartTask(for kind: DownloadKind) {
        pausedKinds.remove(kind)
        expired.remove(kind)
        backgroundTasks[kind] = host.beginBackgroundTask(name: Self.backgroundTaskName(for: kind)) { [weak self] in
            self?.backgroundTimeExpired(for: kind)
        }
        host.isIdleTimerDisabled = true
    }

    func didEndTask(for kind: DownloadKind) {
        if let identifier = backgroundTasks.removeValue(forKey: kind) {
            host.endBackgroundTask(identifier)
        }
        host.isIdleTimerDisabled = !tasks.isEmpty   // the finished task was already removed
    }

    func cancelledByExpiration(_ kind: DownloadKind) -> Bool {
        guard expired.remove(kind) != nil else { return false }
        pausedKinds.insert(kind)
        setState(kind, phase: .paused, fraction: states[kind]?.fraction)
        return true
    }

    /// iOS ran out of background time: cancel the awaiting task; the installer leaves resumable partial files.
    private func backgroundTimeExpired(for kind: DownloadKind) {
        guard let task = tasks[kind] else { return }
        expired.insert(kind)
        task.cancel()
    }

    /// `UIApplication.didBecomeActiveNotification`: resume every paused download the user has not cancelled.
    func applicationDidBecomeActive() {
        for kind in pausedKinds.sorted(by: { Self.backgroundTaskName(for: $0) < Self.backgroundTaskName(for: $1) }) {
            install(kind)
        }
    }
}
