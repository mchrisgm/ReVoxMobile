import Foundation
import os
import ReVoxCore

/// What ReVox's models occupy on disk (§6.9 "Storage accounting", §8.3 footer) and what is left on the volume
/// (DiskSpace reason `85F4.1`, §11). Allocated sizes come from `.totalFileAllocatedSizeKey`; `ModelManager` caches
/// the value and refreshes it after every install and delete.
struct ModelStorageUsage: Equatable, Sendable {
    static let empty = ModelStorageUsage(bytesByKind: [:], freeBytes: nil)

    /// Allocated bytes per kind whose primary folder exists; absent otherwise.
    var bytesByKind: [DownloadKind: Int64]
    /// `volumeAvailableCapacityForImportantUsage` at the refresh; nil when the query failed.
    var freeBytes: Int64?

    var totalBytes: Int64 { bytesByKind.values.reduce(0, +) }

    func bytes(for kind: DownloadKind) -> Int64? { bytesByKind[kind] }
}

enum ModelStorage {
    private static let logger = Logger(subsystem: "revox", category: "storage")

    /// The folders that belong to one kind, primary folder first. Whisper: the variant folder, its Hub sidecar cache and
    /// the tokenizer folder; VAD: the repo folder; pocket-tts: the `pocket-tts` folder (every language FluidAudio wrote).
    static func folders(for kind: DownloadKind, layout: ModelLayout) -> [URL] {
        switch kind {
        case .whisper(let id):
            let descriptor = ModelCatalog.whisper(id)
            return [layout.whisperFolder(descriptor), layout.whisperSidecarCache(descriptor), layout.tokenizerFolder(descriptor)]
        case .vad:
            return [layout.vadRepoDirectory]
        case .pocketTTS:
            return [layout.fluidModelsDirectory.appendingPathComponent(ModelLayout.pocketTTSFolder, isDirectory: true)]
        }
    }

    /// Sum of `totalFileAllocatedSize` over every regular file beneath `url`; 0 when the folder is absent.
    static func allocatedBytes(under url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// One pass over every kind: a kind is counted when its primary folder exists (a leftover secondary folder alone,
    /// such as a tokenizer folder, never makes a deleted model reappear).
    static func usage(layout: ModelLayout, availableBytes: Int64?, fileManager: FileManager = .default) -> ModelStorageUsage {
        var bytesByKind: [DownloadKind: Int64] = [:]
        let kinds: [DownloadKind] = WhisperModelID.allCases.map { DownloadKind.whisper($0) } + [.vad, .pocketTTS]
        for kind in kinds {
            let folders = folders(for: kind, layout: layout)
            guard let primary = folders.first, fileManager.fileExists(atPath: primary.path) else { continue }
            bytesByKind[kind] = folders.reduce(Int64(0)) { $0 + allocatedBytes(under: $1, fileManager: fileManager) }
        }
        let usage = ModelStorageUsage(bytesByKind: bytesByKind, freeBytes: availableBytes)
        logger.info("storage total_mb=\(usage.totalBytes / 1_000_000, privacy: .public) free_mb=\((availableBytes ?? -1) / 1_000_000, privacy: .public) kinds=\(bytesByKind.count, privacy: .public)")
        return usage
    }
}
