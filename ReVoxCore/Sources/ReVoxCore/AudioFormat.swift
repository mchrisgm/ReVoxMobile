import Foundation

/// Port of the `to_mono_16k` semantics in `revox/capture/base.py` (average channels, resample to 16 kHz Float32).
/// The resampler is linear interpolation (deviation W1); the app resamples with `AVAudioConverter` in production.
public enum AudioFormat {
    public static let pipelineSampleRate = 16_000            // PIPELINE_SAMPLE_RATE

    /// Average of the channels per frame, Float32; `channels == 1` returns the input unchanged.
    public static func downmixInterleaved(_ samples: [Float], channels: Int) -> [Float] {
        guard channels > 1 else { return samples }
        let frames = samples.count / channels
        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channels)
        for frame in 0 ..< frames {
            var sum: Float = 0
            let base = frame * channels
            for channel in 0 ..< channels {
                sum += samples[base + channel]
            }
            mono[frame] = sum * scale
        }
        return mono
    }

    /// Average of planar channels per frame; a single channel is returned unchanged.
    public static func downmixPlanar(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }
        let frames = channels.map(\.count).min() ?? 0
        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channels.count)
        for frame in 0 ..< frames {
            var sum: Float = 0
            for channel in channels {
                sum += channel[frame]
            }
            mono[frame] = sum * scale
        }
        return mono
    }

    /// Linear interpolation; `from == to` returns the input unchanged;
    /// output length = `Int((Double(count) * to / from).rounded())`.
    public static func resample(_ samples: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
        guard sourceRate != targetRate, sourceRate > 0, targetRate > 0, !samples.isEmpty else { return samples }
        let outputCount = Int((Double(samples.count) * Double(targetRate) / Double(sourceRate)).rounded())
        guard outputCount > 0 else { return [] }
        let step = Double(sourceRate) / Double(targetRate)
        let last = samples.count - 1
        var output = [Float](repeating: 0, count: outputCount)
        for index in 0 ..< outputCount {
            let position = Double(index) * step
            let lower = min(Int(position), last)
            let upper = min(lower + 1, last)
            let fraction = Float(position - Double(lower))
            output[index] = samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
        return output
    }

    /// Windows `to_mono_16k`: downmix, then resample to 16 kHz unless already there.
    public static func toMono16k(interleaved samples: [Float], channels: Int, sampleRate: Int) -> [Float] {
        let mono = downmixInterleaved(samples, channels: channels)
        guard sampleRate != pipelineSampleRate else { return mono }
        return resample(mono, from: sampleRate, to: pipelineSampleRate)
    }

    /// Int16 → Float32 in [-1, 1) (`/ 32768`), used by tests that model the broadcast source.
    public static func float32(fromInt16 samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32768 }
    }
}
