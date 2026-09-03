import AVFAudio
import Foundation

enum PCMConversionError: Error {
    case bufferAllocationFailed
    case conversionFailed
}

/// One long-lived `AVAudioConverter` per format, fed one buffer at a time with `.haveData` and then
/// `.noDataNow` until the converter reports `.inputRanDry` (§6.1; the feeding pattern is ASSUMED and the
/// M3 measurement record checks for chunk-edge clicks on 48 kHz and HFP routes).
enum PCMConverterDriver {
    static let pipelineFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// `ceil(frames × outputRate / inputRate) + 64` (§6.1).
    static func outputCapacity(inputFrames: AVAudioFrameCount, inputRate: Double, outputRate: Double) -> AVAudioFrameCount {
        AVAudioFrameCount((Double(inputFrames) * outputRate / inputRate).rounded(.up)) + 64
    }

    static func convertToMono(_ input: AVAudioPCMBuffer, with converter: AVAudioConverter) throws -> [Float] {
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
                    outStatus.pointee = .noDataNow
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
            if status != .haveData {
                break   // .inputRanDry (the normal end) or .endOfStream
            }
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
