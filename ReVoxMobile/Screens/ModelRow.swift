import Foundation
import ReVoxCore

/// One Whisper row of the Models screen (§8.3).
struct ModelRow: Identifiable, Equatable {
    let id: WhisperModelID
    let name: String
    let sizeText: String
    let isRecommended: Bool
    let isSuitable: Bool
    let warning: String?
    let note: String?
    let state: ModelDownloadState
    let isSelected: Bool
}

struct VADRow: Equatable {
    let name: String
    let sizeText: String
    let state: ModelDownloadState
}
