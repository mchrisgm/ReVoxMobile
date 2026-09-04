import Foundation
import ReVoxCore

/// The History row projection of a `Session` (§8.6): date/time, source, duration, entry count, first English line.
struct SessionSummary: Equatable, Sendable {
    static let noEntriesText = "Nothing translated"

    let startedAt: Date
    let endedAt: Date?
    let captureMode: CaptureMode
    let modelID: String
    let voice: String
    let pinnedLanguage: String?
    let joinedInProgress: Bool
    let entryCount: Int
    let dropCount: Int
    let firstEnglishLine: String?
    let duration: TimeInterval?

    init(session: Session) {
        startedAt = session.startedAt
        endedAt = session.endedAt
        captureMode = CaptureMode(rawValue: session.captureMode) ?? .microphone
        modelID = session.modelID
        voice = session.voice
        pinnedLanguage = session.pinnedLanguage
        joinedInProgress = session.joinedInProgress
        let rows = session.entries.sorted { $0.timestamp < $1.timestamp }
        let entries = rows.filter { !$0.isDropMarker }
        entryCount = entries.count
        dropCount = rows.count - entries.count
        firstEnglishLine = entries.first?.english
        if let end = session.endedAt ?? rows.last?.timestamp {
            duration = max(0, end.timeIntervalSince(session.startedAt))
        } else {
            duration = nil
        }
    }

    var sourceTitle: String { LiveView.title(for: captureMode) }

    var durationText: String { Self.durationText(duration ?? 0) }

    var entryCountText: String { entryCount == 1 ? "1 entry" : "\(entryCount) entries" }

    /// M10: the drop markers as a count for the Session detail header; nil when there were none, so the row is absent.
    var dropCountText: String? {
        switch dropCount {
        case 0: return nil
        case 1: return "1 phrase skipped"
        default: return "\(dropCount) phrases skipped"
        }
    }

    var previewText: String { firstEnglishLine ?? Self.noEntriesText }

    /// "m:ss" below an hour, "h:mm:ss" from one hour; negative input reads "0:00".
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
