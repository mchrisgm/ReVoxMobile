import Foundation
import ReVoxCore

/// Pure path and installed-check functions over the single model root (R5, §6.9).
/// WhisperKit writes `root/models/...` (lower case), FluidAudio writes `root/Models/...`; on iOS's
/// case-sensitive APFS they are distinct siblings.
struct ModelLayout: Sendable, Equatable {
    static let rootFolderName = "ReVox"
    static let modelsFolderName = "Models"
    static let whisperRepoPath = "models/argmaxinc/whisperkit-coreml"
    static let whisperSidecarPath = ".cache/huggingface/download"
    static let fluidModelsFolder = "Models"
    static let vadFolder = "silero-vad"
    static let pocketTTSFolder = "pocket-tts"
    static let whisperBundles = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]
    static let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "config.json"]
    static let compiledMarker = "coremldata.bin"
    static let partialSuffix = ".partial"

    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// `<Application Support>/ReVox/Models`, created and excluded from backup.
    static func defaultRoot(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appendingPathComponent(rootFolderName, isDirectory: true).appendingPathComponent(modelsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try excludeFromBackup(root)
        return root
    }

    // MARK: Whisper

    var whisperRepoDirectory: URL {
        root.appendingPathComponent(Self.whisperRepoPath, isDirectory: true)
    }

    func whisperFolder(_ descriptor: WhisperModelDescriptor) -> URL {
        whisperRepoDirectory.appendingPathComponent(descriptor.folderName, isDirectory: true)
    }

    func whisperSidecarCache(_ descriptor: WhisperModelDescriptor) -> URL {
        whisperRepoDirectory.appendingPathComponent(Self.whisperSidecarPath, isDirectory: true).appendingPathComponent(descriptor.folderName, isDirectory: true)
    }

    /// `HubApi.localRepoLocation` = `downloadBase/models/<repo id>`, the first folder WhisperKit's tokenizer loader searches.
    func tokenizerFolder(_ descriptor: WhisperModelDescriptor) -> URL {
        root.appendingPathComponent("models", isDirectory: true).appendingPathComponent(descriptor.tokenizerRepo, isDirectory: true)
    }

    // MARK: FluidAudio

    var fluidModelsDirectory: URL {
        root.appendingPathComponent(Self.fluidModelsFolder, isDirectory: true)
    }

    var vadRepoDirectory: URL {
        fluidModelsDirectory.appendingPathComponent(Self.vadFolder, isDirectory: true)
    }

    var vadBundle: URL {
        vadRepoDirectory.appendingPathComponent(ModelCatalog.vad.subdirectory, isDirectory: true)
    }

    var pocketTTSLanguageFolder: URL {
        fluidModelsDirectory.appendingPathComponent(Self.pocketTTSFolder, isDirectory: true).appendingPathComponent(ModelCatalog.pocketTTS.languageFolder, isDirectory: true)
    }

    // MARK: Installed checks (§6.9)

    func isWhisperInstalled(_ id: WhisperModelID, fileManager: FileManager = .default) -> Bool {
        let descriptor = ModelCatalog.whisper(id)
        let folder = whisperFolder(descriptor)
        for bundle in Self.whisperBundles {
            let marker = folder.appendingPathComponent(bundle).appendingPathComponent(Self.compiledMarker)
            guard fileManager.fileExists(atPath: marker.path) else { return false }
        }
        guard fileManager.fileExists(atPath: folder.appendingPathComponent("config.json").path) else { return false }
        let tokenizer = tokenizerFolder(descriptor)
        for file in Self.tokenizerFiles {
            guard fileManager.fileExists(atPath: tokenizer.appendingPathComponent(file).path) else { return false }
        }
        return !Self.containsPartialFiles(under: folder, fileManager: fileManager)
    }

    func isVADInstalled(fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: vadBundle.appendingPathComponent(Self.compiledMarker).path) else { return false }
        return !Self.containsPartialFiles(under: vadBundle, fileManager: fileManager)
    }

    func installedWhisperModels(fileManager: FileManager = .default) -> [WhisperModelID] {
        WhisperModelID.allCases.filter { isWhisperInstalled($0, fileManager: fileManager) }
    }

    static func containsPartialFiles(under url: URL, fileManager: FileManager = .default) -> Bool {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else { return false }
        for case let item as URL in enumerator where item.lastPathComponent.hasSuffix(partialSuffix) {
            return true
        }
        return false
    }

    // MARK: Backup exclusion and free space

    static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }

    /// Re-applied after every download and every verified load: file operations reset the flag (§6.9).
    func reapplyBackupExclusion(fileManager: FileManager = .default) {
        try? Self.excludeFromBackup(root)
        let topLevel = [whisperRepoDirectory, vadRepoDirectory, fluidModelsDirectory.appendingPathComponent(Self.pocketTTSFolder, isDirectory: true)]
        for folder in topLevel where fileManager.fileExists(atPath: folder.path) {
            try? Self.excludeFromBackup(folder)
        }
    }

    /// DiskSpace required-reason API, declared as `E174.1` in `PrivacyInfo.xcprivacy` (§11).
    func availableCapacityBytes() -> Int64? {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
