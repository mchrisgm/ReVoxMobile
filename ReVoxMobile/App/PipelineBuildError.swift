import Foundation
import ReVoxCore

/// Load failures surfaced by the Live screen before the pipeline starts (§9 rows 1 and 4).
enum PipelineBuildError: Error, Equatable, CustomStringConvertible {
    case vadLoadFailed(String)
    case whisperLoadFailed(model: WhisperModelID, reason: String)

    var description: String {
        switch self {
        case .vadLoadFailed:
            return "Voice detector failed to load. Re-download it in Models."
        case .whisperLoadFailed(let model, let reason):
            return "Couldn't load \(model.displayName). Re-download \(model.displayName) in Models. (\(reason))"
        }
    }
}
