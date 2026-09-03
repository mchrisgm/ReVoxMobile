import AVFAudio
import Foundation

/// One `AVAudioConverter` per tap format, kept for the life of the tap so the resampler's filter history
/// is continuous across buffers (§6.1: never FluidAudio's stateless `AudioConverter` for the tap).
final class MicrophoneResampler: @unchecked Sendable {
    let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let lock = NSLock()

    init?(inputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: PCMConverterDriver.pipelineFormat) else {
            return nil
        }
        self.inputFormat = inputFormat
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return (try? PCMConverterDriver.convertToMono(buffer, with: converter)) ?? []
    }

    func reset() {
        lock.lock(); converter.reset(); lock.unlock()
    }
}
