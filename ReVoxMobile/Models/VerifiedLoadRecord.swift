import Foundation
import ReVoxCore

/// `UserDefaults.standard` record `verifiedLoads[<kind>:<library version>]` (§6.9; UserDefaults reason CA92.1, §11).
struct VerifiedLoadRecord: Sendable {
    static let key = "verifiedLoads"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func entryKey(for kind: DownloadKind) -> String {
        switch kind {
        case .whisper(let id):
            return "whisper.\(id.rawValue):\(LibraryVersions.whisperKit)"
        case .vad:
            return "vad:\(LibraryVersions.fluidAudio)"
        case .pocketTTS:
            return "pocketTTS:\(LibraryVersions.fluidAudio)"
        }
    }

    func isRecorded(_ kind: DownloadKind) -> Bool {
        let table = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        return table[Self.entryKey(for: kind)] == true
    }

    func record(_ kind: DownloadKind) {
        var table = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        table[Self.entryKey(for: kind)] = true
        defaults.set(table, forKey: Self.key)
    }

    func clear(_ kind: DownloadKind) {
        var table = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        table.removeValue(forKey: Self.entryKey(for: kind))
        defaults.set(table, forKey: Self.key)
    }
}
