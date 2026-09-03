import Foundation
import ReVoxCore

/// What the pipeline knows about a run when it opens the transcript sink (§6.10 `Session` fields).
struct SessionMetadata: Sendable, Equatable {
    var startedAt: Date
    var captureMode: CaptureMode
    var pinnedLanguage: String?
    var modelID: String
    var voice: String
    var joinedInProgress: Bool
}
