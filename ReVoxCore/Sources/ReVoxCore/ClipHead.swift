import Foundation

/// Conditions the head of a synthesised clip so it starts on speech (M9).
///
/// The owner hears a click before every pocket-tts phrase. M4 added a 5 ms ramp at the edge of every scheduled
/// buffer and it did not settle the report, so whatever precedes the speech survives a 5 ms ramp: a burst longer
/// than that, a DC offset, or a stretch of not-quite-silence the model emits before it starts talking. Rather than
/// guess which, everything before the first *sustained* speech is dropped, and the 10 ms ahead of that onset is
/// ramped in. What a window measures is its *swing* (peak-to-peak), not its level: a DC offset has no swing and
/// so is never mistaken for speech, a click swings hard but only for a window or two, and speech swings for as
/// long as it lasts. "Sustained" is what tells speech from a click: an onset needs 8 ms of consecutive windows
/// above the threshold, and a 3 ms click fails that test and is skipped.
///
/// Foundation-only so the decision is proven on Linux; the app applies it to every pocket-tts clip.
public enum ClipHead {
    /// The analysis window: 2 ms at 24 kHz.
    public static let windowMilliseconds = 2
    /// Consecutive windows above the threshold before a stretch counts as speech: 8 ms.
    public static let sustainWindows = 4
    /// A window counts as speech when its swing reaches this fraction of the clip's largest swing.
    public static let onsetRatio: Float = 0.05
    /// Kept ahead of the onset and ramped in: 10 ms, so the first consonant is not clipped.
    public static let leadMilliseconds = 10

    /// The sample index where sustained speech starts, or nil when the clip never reaches the threshold.
    public static func onset(of samples: [Float], sampleRate: Int) -> Int? {
        let window = max(1, sampleRate * windowMilliseconds / 1000)
        guard samples.count >= window * sustainWindows else { return nil }
        guard let low = samples.min(), let high = samples.max(), high > low else { return nil }
        let threshold = (high - low) * onsetRatio
        var run = 0
        var index = 0
        while index + window <= samples.count {
            let slice = samples[index ..< index + window]
            let swing = (slice.max() ?? 0) - (slice.min() ?? 0)
            if swing >= threshold {
                run += 1
                if run == sustainWindows {
                    return index - window * (sustainWindows - 1)
                }
            } else {
                run = 0
            }
            index += window
        }
        return nil
    }

    /// The clip from `leadMilliseconds` before its onset, with that lead ramped in linearly. A clip with no onset,
    /// or too short to hold a lead, is returned unchanged.
    public static func conditioned(_ samples: [Float], sampleRate: Int) -> [Float] {
        let lead = max(1, sampleRate * leadMilliseconds / 1000)
        guard samples.count >= lead * 2, let onset = onset(of: samples, sampleRate: sampleRate) else { return samples }
        let start = max(0, onset - lead)
        var shaped = Array(samples[start...])
        let ramp = min(lead, shaped.count)
        for i in 0 ..< ramp {
            shaped[i] *= Float(i) / Float(ramp)
        }
        return shaped
    }
}
