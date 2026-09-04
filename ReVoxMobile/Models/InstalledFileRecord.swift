import Foundation
import os
import ReVoxCore

/// What changed between the file set recorded at install and what is on disk now.
struct UpstreamChanges: Equatable, Sendable {
    var added: [String] = []
    var removed: [String] = []
    var resized: [String] = []

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && resized.isEmpty }
    var count: Int { added.count + removed.count + resized.count }
    var summary: String { "\(added.count) added, \(removed.count) removed, \(resized.count) resized" }
}

/// Per-file size record for the downloads FluidAudio cannot pin to a revision (§6.9, §11 "Model integrity"): the
/// Silero VAD bundle and the pocket-tts models come from `main`, so ReVox records their file set at install and
/// compares it afterwards. A difference is shown as "upstream changed" and never silently used. Whisper variants and
/// tokenizers are downloaded at pinned commit SHAs, so they are not recorded here.
/// Stored in `UserDefaults.standard` (required-reason `CA92.1`, already declared in `PrivacyInfo.xcprivacy`).
struct InstalledFileRecord: Sendable {
    static let defaultsKeyPrefix = "installedFiles."
    static let unpinnedKinds: [DownloadKind] = [.vad, .pocketTTS]
    private static let logger = Logger(subsystem: "revox", category: "models")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for kind: DownloadKind) -> String {
        switch kind {
        case .whisper(let id): return "\(defaultsKeyPrefix)whisper.\(id.rawValue)"
        case .vad: return "\(defaultsKeyPrefix)vad"
        case .pocketTTS: return "\(defaultsKeyPrefix)pocketTTS"
        }
    }

    /// Relative path → byte size for every regular file beneath `folder`; empty when the folder is absent.
    static func snapshot(of folder: URL, fileManager: FileManager = .default) -> [String: Int64] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
            return [:]
        }
        let prefix = folder.standardizedFileURL.path.hasSuffix("/") ? folder.standardizedFileURL.path : folder.standardizedFileURL.path + "/"
        var files: [String: Int64] = [:]
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let path = item.standardizedFileURL.path
            let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : item.lastPathComponent
            files[relative] = Int64(values.fileSize ?? 0)
        }
        return files
    }

    static func changes(recorded: [String: Int64], current: [String: Int64]) -> UpstreamChanges {
        var changes = UpstreamChanges()
        changes.added = current.keys.filter { recorded[$0] == nil }.sorted()
        changes.removed = recorded.keys.filter { current[$0] == nil }.sorted()
        changes.resized = recorded.keys.filter { key in
            guard let now = current[key] else { return false }
            return now != recorded[key]
        }.sorted()
        return changes
    }

    func record(_ kind: DownloadKind, files: [String: Int64]) {
        defaults.set(files.mapValues { NSNumber(value: $0) }, forKey: Self.key(for: kind))
        Self.logger.info("recorded \(files.count, privacy: .public) files for \(Self.key(for: kind), privacy: .public)")
    }

    func recorded(_ kind: DownloadKind) -> [String: Int64]? {
        guard let stored = defaults.dictionary(forKey: Self.key(for: kind)) else { return nil }
        var files: [String: Int64] = [:]
        for (path, value) in stored {
            guard let number = value as? NSNumber else { continue }
            files[path] = number.int64Value
        }
        return files
    }

    func clear(_ kind: DownloadKind) {
        defaults.removeObject(forKey: Self.key(for: kind))
    }
}
