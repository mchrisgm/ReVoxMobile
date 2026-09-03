import Foundation

/// The pinned library versions (E1). A verified load is recorded per library version, so a bump
/// forces a fresh verified load of every model (§6.9).
enum LibraryVersions {
    static let whisperKit = "1.1.0"
    static let fluidAudio = "0.15.6"
}
