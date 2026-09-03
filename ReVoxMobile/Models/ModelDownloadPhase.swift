import Foundation

/// One phase type for every download row (§6.9). Value fields only, so the state stays `Equatable`.
enum ModelDownloadPhase: Equatable, Sendable {
    case idle
    case listing
    case downloading(completedFiles: Int?, totalFiles: Int?)
    case compiling(String?)
    case verifying
    case installed
    case paused
    case failed(String)

    var isActive: Bool {
        switch self {
        case .listing, .downloading, .compiling, .verifying:
            return true
        case .idle, .installed, .paused, .failed:
            return false
        }
    }
}
