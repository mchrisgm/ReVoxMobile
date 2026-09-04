import Foundation
import ReVoxCore

/// Maps persisted `Entry` rows to the Live row model so Session detail renders "the entries in the Live row style" (§8.6).
enum SessionDetailRows {
    static func rows(for session: Session) -> [LiveTranscriptRow] {
        TranscriptExporter.sortedEntries(of: session).map(row(for:))
    }

    static func row(for entry: Entry) -> LiveTranscriptRow {
        LiveTranscriptRow(time: entry.timestamp, kind: entry.isDropMarker ? .dropMarker : .entry(language: entry.language, english: entry.english))
    }

    static func languagePinText(_ pin: String?) -> String {
        pin ?? SettingsViewModel.autoDetectTitle
    }
}
