import AVFAudio
import Foundation

enum PCMConversionError: Error {
    case bufferAllocationFailed
    case conversionFailed
}

/// Sample-rate conversion with `AVAudioConverter`, plus the channel averaging Windows does (P7).
///
/// `AVAudioConverter` reduces a multi-channel input to mono by taking the first channel, not by averaging
/// (measured on the simulator, run 33771885792: a stereo buffer of 0.2 / 0.4 converted to 0.2, not 0.3),
/// so channels are averaged here — `AudioFormat.downmixPlanar` semantics — and the converter is left with
/// nothing to do but the sample rate. This supersedes the assumption in §6.1 that the converter downmixes.
enum PCMConverterDriver {
    static let pipelineFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// `ceil(frames × outputRate / inputRate) + 64` (§6.1).
    static func outputCapacity(inputFrames: AVAudioFrameCount, inputRate: Double, outputRate: Double) -> AVAudioFrameCount {
        AVAudioFrameCount((Double(inputFrames) * outputRate / inputRate).rounded(.up)) + 64
    }

    /// Mono Float32 at the buffer's own rate: the average of its channels, converting Int16 and Int32
    /// samples to ±1 Float. `nil` for a sample format this cannot read, which sends the caller to its
    /// `AVAudioConverter` fallback.
    static func averagedMonoSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return [] }
        let interleaved = buffer.format.isInterleaved
        let scale = 1 / Float(channels)

        func average(_ value: (Int, Int) -> Float) -> [Float] {
            var mono = [Float](repeating: 0, count: frames)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += value(frame, channel)
                }
                mono[frame] = sum * scale
            }
            return mono
        }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let data = buffer.floatChannelData else { return nil }
            return average { frame, channel in
                interleaved ? data[0][frame * channels + channel] : data[channel][frame]
            }
        case .pcmFormatInt16:
            guard let data = buffer.int16ChannelData else { return nil }
            return average { frame, channel in
                Float(interleaved ? data[0][frame * channels + channel] : data[channel][frame]) / 32_768
            }
        case .pcmFormatInt32:
            guard let data = buffer.int32ChannelData else { return nil }
            return average { frame, channel in
                Float(interleaved ? data[0][frame * channels + channel] : data[channel][frame]) / 2_147_483_648
            }
        default:
            return nil
        }
    }

    /// Feeds `input` to `converter` once and drains what the converter will give back.
    ///
    /// `endOfStream: false` is the tap path (§6.1): the converter keeps its filter tail, which comes out with
    /// the next buffer, so one buffer converts a little short and a run of them does not. `endOfStream: true`
    /// is the one-shot path — a whole clip — where that tail is the end of the audio: the converter is told the
    /// stream ended so it flushes, and is reset afterwards so the next clip starts clean instead of inheriting
    /// this one's tail.
    static func convertToMono(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter, endOfStream: Bool = false) throws -> [Float] {
        let capacity = outputCapacity(inputFrames: input.frameLength, inputRate: input.format.sampleRate, outputRate: converter.outputFormat.sampleRate)
        var samples: [Float] = []
        samples.reserveCapacity(Int(capacity))
        var consumed = false
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
                throw PCMConversionError.bufferAllocationFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if consumed {
                    outStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return input
            }
            if status == .error {
                throw conversionError ?? PCMConversionError.conversionFailed
            }
            samples.append(contentsOf: output.monoFloatSamples)
            // `.inputRanDry` and `.endOfStream` are both the end; the frame-count guard stops a `.haveData`
            // that produced nothing from spinning.
            if status != .haveData || output.frameLength == 0 {
                break
            }
        }
        if endOfStream {
            converter.reset()
        }
        return samples
    }
}

extension AVAudioPCMBuffer {
    /// Channel 0 of a Float32 non-interleaved buffer; empty for other formats.
    var monoFloatSamples: [Float] {
        guard let data = floatChannelData, frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(frameLength)))
    }

    static func mono(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved, format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if !samples.isEmpty, let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
