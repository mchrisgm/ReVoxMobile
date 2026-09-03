import Foundation
import SwiftData

/// One translation run (§6.10). `entries` cascade-delete with the session.
@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var captureMode: String
    var pinnedLanguage: String?
    var modelID: String
    var voice: String
    var joinedInProgress: Bool
    @Relationship(deleteRule: .cascade, inverse: \Entry.session) var entries: [Entry]

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, captureMode: String, pinnedLanguage: String?,
         modelID: String, voice: String, joinedInProgress: Bool, entries: [Entry] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.captureMode = captureMode
        self.pinnedLanguage = pinnedLanguage
        self.modelID = modelID
        self.voice = voice
        self.joinedInProgress = joinedInProgress
        self.entries = entries
    }
}
