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
    /// M11: "Measured on this iPhone on 14 November 2023" on the row the benchmark recommended; nil elsewhere.
    /// Defaulted, so the memberwise construction sites of the earlier milestones keep compiling.
    var measuredNote: String? = nil
}

struct VADRow: Equatable {
    let name: String
    let sizeText: String
    let state: ModelDownloadState
    /// §11: the bundle comes from FluidAudio's `main`, so a changed file set is captioned, never hidden.
    let noticeText: String?
}
