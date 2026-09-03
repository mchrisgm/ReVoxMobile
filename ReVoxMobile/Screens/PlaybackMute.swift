import Foundation
import Observation

/// Runtime mute state shared by the Live toolbar and the Settings toggle (§8.2, §8.5); not persisted.
@MainActor
@Observable
final class PlaybackMute {
    var isMuted = false
}
