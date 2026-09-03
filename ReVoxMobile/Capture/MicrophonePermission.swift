import AVFAudio
import Foundation

enum MicrophonePermissionStatus: Sendable, Equatable {
    case undetermined
    case denied
    case granted
}

/// `AVAudioApplication` (iOS 17) behind two closures so view models and the capture source are testable (§6.1).
struct MicrophonePermission: Sendable {
    var status: @Sendable () -> MicrophonePermissionStatus
    var request: @Sendable () async -> Bool

    static let live = MicrophonePermission(
        status: {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            case .undetermined: return .undetermined
            @unknown default: return .undetermined
            }
        },
        request: { await AVAudioApplication.requestRecordPermission() }
    )

    static func fixed(_ status: MicrophonePermissionStatus, requestGrants: Bool = false) -> MicrophonePermission {
        MicrophonePermission(status: { status }, request: { requestGrants })
    }
}
