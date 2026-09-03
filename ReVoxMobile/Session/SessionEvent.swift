import AVFAudio

/// What the Live screen shows for session-level conditions (§6.8, §9).
enum SessionEvent: Equatable, Sendable {
    case pausedByIOS                                    // "Translation paused by iOS"
    case resumed
    case resumeFailed                                   // "Tap Start to resume"
    case routeChanged(AVAudioSession.RouteChangeReason)
    case audioRestarted                                 // "Audio restarted"
    case captureStatus(String?)                         // the capture source's own line, e.g. "No microphone input"; nil clears it (§6.1)
}
