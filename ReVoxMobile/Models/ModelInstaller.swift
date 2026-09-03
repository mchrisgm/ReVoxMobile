import Foundation
import ReVoxCore

/// Owns the `ModelHub.offlineMode` transitions and the three install sequences of §6.9 (Whisper + tokenizer,
/// VAD, pocket-tts). Offline mode is `true` for the whole life of the process except while at least one
/// user-initiated install is transferring.
actor ModelInstaller {
    nonisolated let layout: ModelLayout
    private nonisolated let stepsForDeletion: InstallSteps
    private nonisolated let verifiedLoadsForDeletion: VerifiedLoadRecord
    private var steps: InstallSteps { stepsForDeletion }
    private var verifiedLoads: VerifiedLoadRecord { verifiedLoadsForDeletion }
    private var onlineInstalls = 0

    init(layout: ModelLayout, steps: InstallSteps = .production, verifiedLoads: VerifiedLoadRecord = VerifiedLoadRecord()) {
        self.layout = layout
        self.stepsForDeletion = steps
        self.verifiedLoadsForDeletion = verifiedLoads
        steps.setOfflineMode(true)
    }

    // MARK: Readiness (§6.9: ready = installed and a verified load for the current library version)

    func isWhisperReady(_ id: WhisperModelID) -> Bool {
        layout.isWhisperInstalled(id) && verifiedLoads.isRecorded(.whisper(id))
    }

    func isVADReady() -> Bool {
        layout.isVADInstalled() && verifiedLoads.isRecorded(.vad)
    }

    func isPocketTTSReady() -> Bool {
        layout.isPocketTTSInstalled() && verifiedLoads.isRecorded(.pocketTTS)
    }

    // MARK: Installs

    func installWhisper(_ id: WhisperModelID, progress: @escaping @Sendable (ModelDownloadState) -> Void) async throws {
        let descriptor = ModelCatalog.whisper(id)
        let expected = ModelCatalog.download(for: .whisper(id)).expectedBytes
        progress(ModelDownloadState(phase: .downloading(completedFiles: nil, totalFiles: nil), fraction: 0, bytesExpected: expected))
        do {
            try await withOnlineAccess {
                _ = try await steps.downloadWhisperVariant(descriptor, layout.root) { p in
                    progress(ModelDownloadState.whisperVariant(p, bytesExpected: expected))
                }
                try Task.checkCancellation()
                _ = try await steps.downloadTokenizer(descriptor, layout.root) { p in
                    progress(ModelDownloadState.whisperTokenizer(p, bytesExpected: expected))
                }
            }
            try Task.checkCancellation()
            layout.reapplyBackupExclusion()
            guard layout.isWhisperInstalled(id) else {
                throw ModelInstallError.filesMissingAfterDownload(descriptor.folderName)
            }
            progress(ModelDownloadState(phase: .verifying, fraction: 1, bytesExpected: expected))
            try await steps.verifyWhisper(descriptor, layout)
            verifiedLoads.record(.whisper(id))
            layout.reapplyBackupExclusion()
            progress(ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: expected))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            progress(ModelDownloadState(phase: .failed(String(describing: error)), fraction: nil, bytesExpected: expected))
            throw error
        }
    }

    func installVAD(progress: @escaping @Sendable (ModelDownloadState) -> Void) async throws {
        let expected = ModelCatalog.download(for: .vad).expectedBytes
        progress(ModelDownloadState(phase: .listing, fraction: 0, bytesExpected: expected))
        do {
            try await withOnlineAccess {
                try await steps.downloadVAD(layout.vadRepoDirectory) { fraction, phase in
                    progress(ModelDownloadState.fluidAudio(fractionCompleted: fraction, phase: phase, bytesExpected: expected))
                }
            }
            try Task.checkCancellation()
            layout.reapplyBackupExclusion()
            guard layout.isVADInstalled() else {
                throw ModelInstallError.filesMissingAfterDownload(ModelCatalog.vad.subdirectory)
            }
            progress(ModelDownloadState(phase: .verifying, fraction: 1, bytesExpected: expected))
            try await steps.verifyVAD(layout.vadBundle)
            verifiedLoads.record(.vad)
            layout.reapplyBackupExclusion()
            progress(ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: expected))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            progress(ModelDownloadState(phase: .failed(String(describing: error)), fraction: nil, bytesExpected: expected))
            throw error
        }
    }

    /// pocket-tts (§6.5, §6.9): listing → downloading → compiling inside the offline-mode window, then the installed
    /// check (which requires every offered voice file and `bos_before_voice.bin`), then the verified load.
    func installPocketTTS(progress: @escaping @Sendable (ModelDownloadState) -> Void) async throws {
        let expected = ModelCatalog.download(for: .pocketTTS).expectedBytes
        progress(ModelDownloadState(phase: .listing, fraction: 0, bytesExpected: expected))
        do {
            try await withOnlineAccess {
                try await steps.downloadPocketTTS(layout.fluidBaseDirectory) { fraction, phase in
                    progress(ModelDownloadState.fluidAudio(fractionCompleted: fraction, phase: phase, bytesExpected: expected))
                }
            }
            try Task.checkCancellation()
            layout.reapplyBackupExclusion()
            guard layout.isPocketTTSInstalled() else {
                throw ModelInstallError.filesMissingAfterDownload(ModelLayout.pocketTTSFolder)
            }
            progress(ModelDownloadState(phase: .verifying, fraction: 1, bytesExpected: expected))
            try await steps.verifyPocketTTS(layout.fluidBaseDirectory)
            verifiedLoads.record(.pocketTTS)
            layout.reapplyBackupExclusion()
            progress(ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: expected))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            progress(ModelDownloadState(phase: .failed(String(describing: error)), fraction: nil, bytesExpected: expected))
            throw error
        }
    }

    // MARK: Delete (§6.9)

    func deleteWhisper(_ id: WhisperModelID) throws {
        try deleteWhisperSync(id)
    }

    func deleteVAD() {
        deleteVADSync()
    }

    func deletePocketTTS() {
        deletePocketTTSSync()
    }

    // MARK: Offline-mode window

    /// `offlineMode` is false only while an install transfers; nested installs share one window.
    private func withOnlineAccess(_ body: () async throws -> Void) async throws {
        onlineInstalls += 1
        if onlineInstalls == 1 {
            steps.setOfflineMode(false)
        }
        defer {
            onlineInstalls -= 1
            if onlineInstalls == 0 {
                steps.setOfflineMode(true)
            }
        }
        try await body()
    }
}

extension ModelInstaller {
    /// File removal needs no actor hop: the layout is immutable and the record is a `UserDefaults` write.
    nonisolated func deleteWhisperSync(_ id: WhisperModelID) throws {
        let descriptor = ModelCatalog.whisper(id)
        let fileManager = FileManager.default
        let folder = layout.whisperFolder(descriptor)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
        let sidecars = layout.whisperSidecarCache(descriptor)
        if fileManager.fileExists(atPath: sidecars.path) {
            try fileManager.removeItem(at: sidecars)
        }
        verifiedLoadsForDeletion.clear(.whisper(id))
    }

    nonisolated func deleteVADSync() {
        stepsForDeletion.deleteVAD(layout.fluidModelsDirectory)
        verifiedLoadsForDeletion.clear(.vad)
    }

    nonisolated func deletePocketTTSSync() {
        stepsForDeletion.deletePocketTTS(layout.fluidModelsDirectory)
        verifiedLoadsForDeletion.clear(.pocketTTS)
    }
}

enum ModelInstallError: Error, Equatable, CustomStringConvertible {
    case filesMissingAfterDownload(String)
    case stepUnavailable(String)

    var description: String {
        switch self {
        case .filesMissingAfterDownload(let name):
            return "Download of \(name) finished but required files are missing; try again"
        case .stepUnavailable(let step):
            return "Install step \(step) is not configured in this build"
        }
    }
}
