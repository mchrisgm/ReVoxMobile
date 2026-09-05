import Foundation
import SwiftData

/// One transcript line or one drop marker (§6.10). `original` is "" unless Learning mode recorded the words as
/// spoken (M9); History and the export show it when present.
@Model
final class Entry {
    var timestamp: Date
    var language: String
    var original: String
    var english: String
    var isDropMarker: Bool
    /// M11: a phrase the gates were unsure about; greyed in Session detail, "(unsure) " in the export. The default
    /// is what SwiftData's lightweight migration writes into every row of a store from before M11
    /// (`TranscriptMigrationTests`), so no `VersionedSchema` or migration plan is needed.
    var isGuess: Bool = false
    var session: Session?

    init(timestamp: Date, language: String, original: String, english: String, isDropMarker: Bool, isGuess: Bool = false, session: Session? = nil) {
        self.timestamp = timestamp
        self.language = language
        self.original = original
        self.english = english
        self.isDropMarker = isDropMarker
        self.isGuess = isGuess
        self.session = session
    }
}
