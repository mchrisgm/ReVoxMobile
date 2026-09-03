import Foundation
import Observation
import ReVoxCore

/// Owns the on-disk `settings.json` (R11, §5.7): every change is written immediately through `SettingsCodec`.
@MainActor
@Observable
final class SettingsStore {
    static let folderName = "ReVox"

    private(set) var settings: Settings
    let fileURL: URL
    var lastSaveError: String?

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.settings = SettingsCodec.load(from: fileURL)
    }

    /// `<Application Support>/ReVox/settings.json`; the folder is created if needed.
    static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(SettingsCodec.fileName)
    }

    func update(_ change: (inout Settings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        save()
    }

    func reload() {
        settings = SettingsCodec.load(from: fileURL)
    }

    private func save() {
        do {
            try SettingsCodec.save(settings, to: fileURL)
            lastSaveError = nil
        } catch {
            lastSaveError = String(describing: error)
        }
    }
}
