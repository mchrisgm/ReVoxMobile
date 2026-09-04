import Foundation
import os
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
    private static let logger = Logger(subsystem: "revox", category: "models")
    static let lowRemainingThreshold: Int64 = 1_000_000_000

    let layout: ModelLayout
    let installer: ModelInstaller
    private let isPipelineRunning: @MainActor () -> Bool
    private let fileRecord: InstalledFileRecord
    private let availableBytes: @MainActor () -> Int64?

    private(set) var states: [DownloadKind: ModelDownloadState] = [:]
    private(set) var installedWhisper: [WhisperModelID] = []
    private(set) var vadInstalled = false
    /// On-disk accounting (§6.9): refreshed by `refreshInstalledStates()`, i.e. after every install and delete.
    private(set) var storage: ModelStorageUsage = .empty
    /// The unpinned FluidAudio downloads whose files no longer match what was recorded at install (§11).
    private(set) var upstreamChanged: Set<DownloadKind> = []
    static let upstreamChangedText = "Files changed since download — re-download to be sure"
    private(set) var pocketTTSInstalled = false
    /// Called after the active Whisper model was deleted with the smallest installed model, or nil.
    var onActiveModelDeleted: (@MainActor (WhisperModelID?) -> Void)?
    /// Fired after a delete removed files that a cached, loaded pipeline may still hold open (§6.9, M7).
    var onModelFilesChanged: (@MainActor () -> Void)?

    @ObservationIgnored private var tasks: [DownloadKind: Task<Void, Never>] = [:]

    @ObservationIgnored private let host: any InstallHost
    @ObservationIgnored private var backgroundTasks: [DownloadKind: Int] = [:]
    @ObservationIgnored private var expired: Set<DownloadKind> = []
    /// Downloads interrupted by background-task expiration; resumed on `applicationDidBecomeActive()`.
    private(set) var pausedKinds: Set<DownloadKind> = []

    init(layout: ModelLayout, installer: ModelInstaller, isPipelineRunning: @escaping @MainActor () -> Bool,
         availableBytes: (@MainActor () -> Int64?)? = nil, host: (any InstallHost)? = nil,
         fileRecord: InstalledFileRecord = InstalledFileRecord()) {
        self.layout = layout
        self.installer = installer
        self.isPipelineRunning = isPipelineRunning
        self.availableBytes = availableBytes ?? { layout.availableCapacityBytes() }
        self.host = host ?? UIApplicationInstallHost()
        self.fileRecord = fileRecord
        refreshInstalledStates()
    }

    // MARK: State

    func state(for kind: DownloadKind) -> ModelDownloadState {
        states[kind] ?? .idle(bytesExpected: ModelCatalog.download(for: kind).expectedBytes)
    }

    var hasActiveDownload: Bool {
        states.values.contains { $0.phase.isActive }
    }

    /// Re-reads the disk for the derived flags alone, leaving every row's phase untouched.
    ///
    /// A row reaches `.installed` from the installer's last progress report, which lands before the task is
    /// finished and `refreshInstalledStates()` runs. Without this the screen can show a row as installed while
    /// `vadInstalled` and `installedWhisper` still say otherwise — a window a test caught (run 33811704361) and
    /// a viewer could catch too.
    func refreshInstalledFlags() {
        installedWhisper = layout.installedWhisperModels()
        vadInstalled = layout.isVADInstalled()
        pocketTTSInstalled = layout.isPocketTTSInstalled()
    }

    /// Re-reads the disk: installed rows become `.installed`, everything else not in flight becomes `.idle`.
    func refreshInstalledStates() {
        refreshInstalledFlags()
        for id in WhisperModelID.allCases {
            let kind = DownloadKind.whisper(id)
            guard tasks[kind] == nil, !pausedKinds.contains(kind) else { continue }
            setState(kind, phase: installedWhisper.contains(id) ? .installed : .idle, fraction: installedWhisper.contains(id) ? 1 : nil)
        }
        if tasks[.vad] == nil, !pausedKinds.contains(.vad) {
            setState(.vad, phase: vadInstalled ? .installed : .idle, fraction: vadInstalled ? 1 : nil)
        }
        if tasks[.pocketTTS] == nil, !pausedKinds.contains(.pocketTTS) {
            setState(.pocketTTS, phase: pocketTTSInstalled ? .installed : .idle, fraction: pocketTTSInstalled ? 1 : nil)
        }
        refreshUpstreamChanges()
        refreshStorage()
    }

    /// Enumerates the model root (metadata only, no file reads) and re-reads the free space.
    func refreshStorage() {
        storage = ModelStorage.usage(layout: layout, availableBytes: availableBytes())
    }

    /// Compares the recorded file set of every unpinned download with what is on disk (§11). Cheap: metadata only.
    func refreshUpstreamChanges() {
        var changed: Set<DownloadKind> = []
        for kind in InstalledFileRecord.unpinnedKinds {
            guard let folder = ModelStorage.folders(for: kind, layout: layout).first,
                  FileManager.default.fileExists(atPath: folder.path),
                  let recorded = fileRecord.recorded(kind) else { continue }
            if !InstalledFileRecord.changes(recorded: recorded, current: InstalledFileRecord.snapshot(of: folder)).isEmpty {
                changed.insert(kind)
            }
        }
        upstreamChanged = changed
    }

    /// The caption the Models and Voices screens show for a flagged download; nil when nothing changed.
    func upstreamChangeText(for kind: DownloadKind) -> String? {
        upstreamChanged.contains(kind) ? Self.upstreamChangedText : nil
    }

    /// Writes the file set of an unpinned download after a successful install; a difference against the previous
    /// record is the upstream change itself, so it is logged before the new record replaces it (§11).
    private func recordInstalledFiles(_ kind: DownloadKind) {
        guard InstalledFileRecord.unpinnedKinds.contains(kind),
              let folder = ModelStorage.folders(for: kind, layout: layout).first else { return }
        let current = InstalledFileRecord.snapshot(of: folder)
        if let previous = fileRecord.recorded(kind) {
            let changes = InstalledFileRecord.changes(recorded: previous, current: current)
            if !changes.isEmpty {
                Self.logger.notice("upstream changed for \(InstalledFileRecord.key(for: kind), privacy: .public): \(changes.summary, privacy: .public)")
            }
        }
        fileRecord.record(kind, files: current)
        upstreamChanged.remove(kind)
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
    ///
    /// Progress crosses from the installer actor through one stream that a main-actor pump drains in order.
    /// The pump is finished and awaited before the row is finalised, so a report that was in flight when the
    /// install ended cannot land afterwards and paint `.downloading` over `.installed` or `.failed`.
    private func runInstall(_ kind: DownloadKind) async {
        let installer = self.installer
        let (reports, continuation) = AsyncStream<ModelDownloadState>.makeStream(bufferingPolicy: .unbounded)
        let report: @Sendable (ModelDownloadState) -> Void = { state in continuation.yield(state) }
        // A failure phase is withheld here and published by the caller only after the task slot is freed. A row
        // that reads Failed while `tasks[kind]` is still set refuses the Retry it is inviting — `install(_:)`
        // returns early when a task exists — so the tap would do nothing. The window is small but real: the pump
        // applies the phase, and the slot is cleared only after `await pump.value` resumes, leaving the main actor
        // free in between. Run 33868423907 caught it from a test; a fast finger would have caught it from a user.
        let pump = Task { @MainActor [weak self] () -> ModelDownloadState? in
            var withheldFailure: ModelDownloadState?
            for await state in reports {
                if case .failed = state.phase {
                    withheldFailure = state
                    continue
                }
                self?.states[kind] = state
                if state.phase == .installed {
                    self?.refreshInstalledFlags()   // the row and the flags become true together
                }
            }
            return withheldFailure
        }

        @discardableResult
        func drainReports() async -> ModelDownloadState? {
            continuation.finish()
            return await pump.value
        }

        do {
            switch kind {
            case .whisper(let id):
                try await installer.installWhisper(id, progress: report)
            case .vad:
                try await installer.installVAD(progress: report)
            case .pocketTTS:
                try await installer.installPocketTTS(progress: report)
            }
            await drainReports()
            finishTask(for: kind, cancelled: false)
            recordInstalledFiles(kind)
            if case .whisper = kind, !layout.isVADInstalled(), tasks[.vad] == nil {
                install(.vad)
            }
        } catch is CancellationError {
            await drainReports()
            finishTask(for: kind, cancelled: true)
        } catch {
            let failure = await drainReports()
            tasks[kind] = nil
            didEndTask(for: kind)
            // Only now, with the slot free, does the row say Failed — so the Retry it offers is always accepted.
            if let failure {
                states[kind] = failure
            }
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
            installer.deletePocketTTSSync()
            refreshInstalledStates()
        }
        fileRecord.clear(kind)
        upstreamChanged.remove(kind)
        onModelFilesChanged?()
    }

    // MARK: Readiness

    func isWhisperReady(_ id: WhisperModelID) async -> Bool {
        await installer.isWhisperReady(id)
    }

    func isVADReady() async -> Bool {
        await installer.isVADReady()
    }

    func isPocketTTSReady() async -> Bool {
        await installer.isPocketTTSReady()
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
