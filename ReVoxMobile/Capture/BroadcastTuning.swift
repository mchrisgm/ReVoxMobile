import Foundation

/// Broadcast-mode constants that only a device can decide (§5.2, §10.4).
enum BroadcastTuning {
    /// Extra hold after the speaking-false edge, in 16 kHz ring frames: the delay between "the player finished" and
    /// "the extension wrote the last sample of ReVox's voice". ASSUMED 0 until measured; replace with the median
    /// `tailFrames` of twenty `selfcapture` measurements and update the recorded value in the file named below.
    static let captureLatencyFrames = 0
    static let measurementSource = "docs/measurements/m5-broadcast-capture.md row 7"
}
