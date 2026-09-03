import Foundation
import ReVoxCore

/// Capture failures the Live screen surfaces (§6.1, §8.2, §9).
enum CaptureError: Error, Equatable, CustomStringConvertible {
    case microphoneDenied
    case unsupportedMode(CaptureMode)
    case engineUnavailable
    case noInput

    var description: String {
        switch self {
        case .microphoneDenied: return "Microphone access is off for ReVox"
        case .unsupportedMode(let mode): return "The microphone source cannot capture in \(mode.rawValue) mode"
        case .engineUnavailable: return "Microphone unavailable"
        case .noInput: return "No microphone input"
        }
    }
}
