import Foundation
import Observation

/// Main-actor mirror of `EffectiveSpeaker.status` for the Live status line (§8.2) and the Voices screen.
@MainActor
@Observable
final class SpeakerStatusRelay {
    var status: SpeakerStatus = .systemNotDownloaded

    var text: String { status.text }

    /// Called from the speaker's status callback on any thread; the assignment hops to the main actor.
    nonisolated func post(_ status: SpeakerStatus) {
        Task { @MainActor in
            self.status = status
        }
    }
}
