import Foundation
import ReVoxCore

/// The two `AudioSource`s of §4.2, chosen by `settings.capture` in `PipelineAssembler.build`. The broadcast capture is
/// one object for the app's lifetime (its `frames()` is fresh per run, §5.4); the microphone capture is built per pipeline.
struct CaptureSources: Sendable {
    let makeMicrophone: @Sendable (AudioSessionController) -> any AudioSource
    let makeBroadcast: @Sendable () -> any AudioSource
    /// True when the last attach happened more than the catch-up window behind the writer (§6.2, §6.10).
    let broadcastJoinedInProgress: @Sendable () -> Bool
    /// Installs the pipeline's `noteCaptureGap()` as the ring-overrun handler (§5.4, §6.2).
    let setBroadcastGapHandler: @Sendable ((@Sendable (Int) async -> Void)?) -> Void

    static func live(broadcast: BroadcastCapture) -> CaptureSources {
        CaptureSources(
            makeMicrophone: { controller in MicrophoneCapture(controller: controller) },
            makeBroadcast: { broadcast },
            broadcastJoinedInProgress: { broadcast.joinedInProgress },
            setBroadcastGapHandler: { handler in broadcast.setGapHandler(handler) }
        )
    }
}
