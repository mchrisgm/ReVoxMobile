import Foundation
import ReVoxCore

/// Writes one session as the Windows `.txt` (§6.10, P5): entries → `[TranscriptItem]` → `TranscriptFormatter.export`
/// → `<temporaryDirectory>/ReVox/<yyyy-MM-dd_HH-mm-ss>.txt`, UTF-8, `\n` line endings, no BOM. The `ShareLink`
/// of the Session detail screen hands this URL to the share sheet; files older than a day are pruned at launch
/// (FileTimestamp reason `C617.1` of §11).
struct TranscriptExporter: Sendable {
    static let directoryName = "ReVox"

    let directory: URL
    let formatter: TranscriptFormatter

    init(directory: URL = TranscriptExporter.defaultDirectory(), formatter: TranscriptFormatter = TranscriptFormatter()) {
        self.directory = directory
        self.formatter = formatter
    }

    static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// The relationship is unordered; the export is in timestamp order, which is the order the store received the items.
    static func sortedEntries(of session: Session) -> [Entry] {
        session.entries.sorted { $0.timestamp < $1.timestamp }
    }

    func fileName(for session: Session) -> String {
        formatter.fileName(startedAt: session.startedAt)
    }

    func text(for session: Session) -> String {
        formatter.export(startedAt: session.startedAt, items: TranscriptStore.items(from: Self.sortedEntries(of: session)))
    }

    /// Creates the directory if needed and (re)writes the file atomically; the same session always maps to the same URL.
    @discardableResult
    func export(_ session: Session) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(for: session), isDirectory: false)
        try Data(text(for: session).utf8).write(to: url, options: .atomic)
        return url
    }
}
