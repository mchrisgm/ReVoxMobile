import ReplayKit

/// Receives audio from other apps while a system broadcast is running.
///
/// Milestone 0 only proves the target builds and embeds. Milestone 5 converts the
/// `.audioApp` buffers to mono 16 kHz and writes them into the App Group ring buffer.
final class SampleHandler: RPBroadcastSampleHandler {
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .audioApp else { return }
        // Intentionally empty until milestone 5.
    }

    override func broadcastFinished() {
        super.broadcastFinished()
    }
}
