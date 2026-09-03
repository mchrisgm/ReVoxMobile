import AVFAudio
import Foundation

/// One `AVAudioConverter` per tap format, kept for the life of the tap so the resampler's filter history
/// is continuous across buffers (§6.1: never FluidAudio's stateless `AudioConverter` for the tap).
///
/// Channels are averaged before the converter sees them (`PCMConverterDriver.averagedMonoSamples`), because
/// `AVAudioConverter` reduces channels by taking the first one rather than averaging, and Windows averages (P7).
/// The converter therefore only changes the sample rate, and at 16 kHz there is nothing left for it to do.
final class MicrophoneResampler: @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let monoFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private let lock = NSLock()

    init?(inputFormat: AVAudioFormat) {
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate, channels: 1, interleaved: false) else {
            return nil
        }
        if inputFormat.sampleRate == PCMConverterDriver.pipelineFormat.sampleRate {
            converter = nil                     // already at 16 kHz: averaging is the whole conversion
        } else {
            guard let converter = AVAudioConverter(from: monoFormat, to: PCMConverterDriver.pipelineFormat) else {
                return nil
            }
            self.converter = converter
        }
        self.inputFormat = inputFormat
        self.monoFormat = monoFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let mono = PCMConverterDriver.averagedMonoSamples(buffer) else {
            return MicrophoneCapture.fallbackResample(buffer)
        }
        guard let converter else { return mono }
        guard let monoBuffer = AVAudioPCMBuffer.mono(samples: mono, format: monoFormat) else { return [] }
        lock.lock(); defer { lock.unlock() }
        return (try? PCMConverterDriver.convertToMono(monoBuffer, with: converter)) ?? []
    }

    func reset() {
        lock.lock(); converter?.reset(); lock.unlock()
    }
}
