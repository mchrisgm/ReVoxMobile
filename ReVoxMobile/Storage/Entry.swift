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
    var session: Session?

    init(timestamp: Date, language: String, original: String, english: String, isDropMarker: Bool, session: Session? = nil) {
        self.timestamp = timestamp
        self.language = language
        self.original = original
        self.english = english
        self.isDropMarker = isDropMarker
        self.session = session
    }
}
