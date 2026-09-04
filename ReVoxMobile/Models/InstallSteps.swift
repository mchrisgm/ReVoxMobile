import CoreML
import FluidAudio
import Foundation
import ReVoxCore
import WhisperKit

/// The library calls of §6.9 behind value-typed closures, so the installer's sequencing, offline-mode
/// window and state bridging are tested without a network (R15). `production` is the only place the
/// app touches the Hub.
struct InstallSteps: Sendable {
    typealias FoundationProgress = @Sendable (Progress) -> Void
    typealias FluidProgress = @Sendable (_ fractionCompleted: Double, _ phase: ModelDownloadPhase) -> Void

    /// `ModelDownloader.resolveRepo` at the pinned SHA; returns the snapshot root.
    var downloadWhisperVariant: @Sendable (_ descriptor: WhisperModelDescriptor, _ root: URL, _ progress: @escaping FoundationProgress) async throws -> URL
    /// `HubApiWrapper.snapshot` of the three tokenizer files at the pinned SHA; returns the local repo folder.
    var downloadTokenizer: @Sendable (_ descriptor: WhisperModelDescriptor, _ root: URL, _ progress: @escaping FoundationProgress) async throws -> URL
    /// `ModelHub.download(.vad, subdirectory:to:)` into `repoDirectory` (= `layout.vadRepoDirectory`).
    var downloadVAD: @Sendable (_ repoDirectory: URL, _ progress: @escaping FluidProgress) async throws -> Void
    /// A full WhisperKit load (prewarm + load) that must reach `.loaded`; the instance is dropped afterwards.
    var verifyWhisper: @Sendable (_ descriptor: WhisperModelDescriptor, _ layout: ModelLayout) async throws -> Void
    /// `MLModel(contentsOf:)` on the VAD bundle.
    var verifyVAD: @Sendable (_ bundle: URL) async throws -> Void
    /// `ModelHub.clearCache(for: .vad, directory:)` on `layout.fluidModelsDirectory`.
    var deleteVAD: @Sendable (_ fluidModelsDirectory: URL) -> Void
    /// `ModelHub.offlineMode = value`.
    var setOfflineMode: @Sendable (Bool) -> Void

    /// `PocketTtsResourceDownloader.ensureModels(language: .english, directory: fluidBase, precision: .fp16, placement: .ane)`;
    /// the downloader appends `Models` itself, so files land under `root/fluid/Models/pocket-tts/v2.1/english/` (§6.5).
    /// Progress is byte-weighted over 0-1.
    var downloadPocketTTS: @Sendable (_ fluidBaseDirectory: URL, _ progress: @escaping FluidProgress) async throws -> Void = { _, _ in
        throw ModelInstallError.stepUnavailable("downloadPocketTTS")
    }
    /// The verified load: `PocketTtsManager(... directory: fluidBase, precision: .fp16, placement: .ane).initialize()`.
    var verifyPocketTTS: @Sendable (_ fluidBaseDirectory: URL) async throws -> Void = { _ in
        throw ModelInstallError.stepUnavailable("verifyPocketTTS")
    }
    /// `ModelHub.clearCache(for: .pocketTts, directory:)` on `layout.fluidModelsDirectory` (§6.9; never `clearAllCaches()`).
    var deletePocketTTS: @Sendable (_ fluidModelsDirectory: URL) -> Void = { _ in }

    static let tokenizerFiles = ModelLayout.tokenizerFiles

    static let production = InstallSteps(
        downloadWhisperVariant: { descriptor, root, progress in
            let config = ModelDownloadConfig(modelRepo: descriptor.modelRepo, revision: descriptor.revision)
            let downloader = ModelDownloader(config: config)
            return try await downloader.resolveRepo(
                patterns: ["\(descriptor.folderName)/*"],
                downloadBase: root,
                download: true,
                progressCallback: { progress($0) }
            )
        },
        downloadTokenizer: { descriptor, root, progress in
            let hub = HubApiWrapper(downloadBase: root)
            return try await hub.snapshot(
                from: HubApiWrapper.Repo(id: descriptor.tokenizerRepo),
                revision: descriptor.tokenizerRevision,
                matching: InstallSteps.tokenizerFiles,
                progressHandler: { progress($0) }
            )
        },
        downloadVAD: { repoDirectory, progress in
            try await ModelHub.download(
                Repo.vad,
                subdirectory: ModelCatalog.vad.subdirectory,
                to: repoDirectory,
                config: .default,
                progressHandler: { report in
                    progress(report.fractionCompleted, InstallSteps.phase(from: report.phase))
                }
            )
        },
        verifyWhisper: { descriptor, layout in
            let config = WhisperKitConfig(
                modelFolder: layout.whisperFolder(descriptor).path,
                tokenizerFolder: layout.root,
                computeOptions: ModelComputeOptions(),
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: false,
                download: false
            )
            let kit = try await WhisperKit(config)
            try await kit.prewarmModels()
            try await kit.loadModels()
            guard kit.modelState == .loaded else {
                throw WhisperError.modelsUnavailable("Model state after load is \(kit.modelState)")
            }
            guard kit.tokenizer != nil else {
                throw WhisperError.tokenizerUnavailable()
            }
            await kit.unloadModels()
        },
        verifyVAD: { bundle in
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            _ = try MLModel(contentsOf: bundle, configuration: configuration)
        },
        deleteVAD: { fluidModelsDirectory in
            ModelHub.clearCache(for: Repo.vad, directory: fluidModelsDirectory)
        },
        setOfflineMode: { offline in
            ModelHub.offlineMode = offline
        },
        downloadPocketTTS: { fluidBaseDirectory, progress in
            _ = try await PocketTtsResourceDownloader.ensureModels(
                language: .english,
                directory: fluidBaseDirectory,
                precision: .fp16,
                placement: .ane,
                progressHandler: { report in
                    progress(report.fractionCompleted, InstallSteps.phase(from: report.phase))
                }
            )
        },
        verifyPocketTTS: { fluidBaseDirectory in
            // Same directory / precision / placement as the download and as PocketTTSSpeaker: the cache hits.
            let manager = PocketTtsManager(
                defaultVoice: PocketTtsConstants.defaultVoice,
                language: .english,
                directory: fluidBaseDirectory,
                precision: .fp16,
                placement: .ane
            )
            try await manager.initialize()
            guard await manager.isAvailable else {
                throw PocketTTSError.modelNotFound("pocket-tts reported unavailable after initialize()")
            }
            // The manager is dropped here; whether ARC releases the models is measured on device (§13 Q7).
        },
        deletePocketTTS: { fluidModelsDirectory in
            ModelHub.clearCache(for: Repo.pocketTts, directory: fluidModelsDirectory)
        }
    )

    /// FluidAudio `DownloadPhase` → the row phase (§6.9 bridging).
    static func phase(from phase: DownloadPhase) -> ModelDownloadPhase {
        switch phase {
        case .listing:
            return .listing
        case .downloading(let completedFiles, let totalFiles):
            return .downloading(completedFiles: completedFiles, totalFiles: totalFiles)
        case .compiling(let modelName):
            return .compiling(modelName)
        }
    }
}
