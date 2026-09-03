import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class ResamplerTests: XCTestCase {
    private func stereoBuffer(frames: Int, rate: Double, hz: Double = 1_000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        let data = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<frames {
            let value = Float(sin(2 * Double.pi * hz * Double(i) / rate)) * 0.5
            data[0][i] = value
            data[1][i] = value
        }
        return buffer
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        var count = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) {
            count += 1
        }
        return count
    }

    /// The tap resampler is stateful by design (§6.1), so the first 100 ms buffer comes out short by the
    /// converter's priming latency and the rest of it arrives with the next buffer. What must hold is that
    /// nothing is lost from then on: ten buffers of 4 800 frames give ten buffers' worth of 16 kHz samples.
    func testStereo48kTo16k() throws {
        let buffer = try stereoBuffer(frames: 4_800, rate: 48_000)
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: buffer.format))
        var counts: [Int] = []
        for _ in 0..<10 {
            let out = resampler.convert(buffer)
            counts.append(out.count)
            XCTAssertEqual(out.count, out.filter { $0.isFinite }.count)
        }
        XCTAssertEqual(Double(counts.reduce(0, +)), 16_000, accuracy: 64, "per-buffer counts \(counts)")
        // Steady state, after priming: each buffer is the Windows 1 600 ± 16 (W1).
        for count in counts.dropFirst() {
            XCTAssertEqual(Double(count), 1_600, accuracy: 16, "per-buffer counts \(counts)")
        }
    }

    func testAgreesWithTheCoreReferenceResampler() throws {
        let buffer = try stereoBuffer(frames: 48_000, rate: 48_000)
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: buffer.format))
        _ = resampler.convert(buffer)                       // primes the converter
        let production = resampler.convert(buffer)          // steady state
        let mono = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 48_000))
        let reference = AudioFormat.resample(mono, from: 48_000, to: 16_000)
        XCTAssertEqual(Double(production.count), Double(reference.count), accuracy: 16)
        // A 1 kHz tone keeps its frequency on both paths: ~2 000 zero crossings per second.
        let productionCrossings = zeroCrossings(production)
        let referenceCrossings = zeroCrossings(reference)
        XCTAssertEqual(Double(productionCrossings), Double(referenceCrossings), accuracy: Double(referenceCrossings) * 0.01)
    }

    /// Windows averages the channels (P7); `AVAudioConverter` takes the first one, so the resampler averages
    /// before it converts.
    func testChannelsAreAveragedNotTakenFromTheFirst() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        for i in 0..<4 {
            buffer.floatChannelData![0][i] = 0.2
            buffer.floatChannelData![1][i] = 0.4
        }
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: format))
        let out = resampler.convert(buffer)
        XCTAssertEqual(out.count, 4, "16 kHz stereo needs no rate conversion")
        for sample in out {
            XCTAssertEqual(sample, 0.3, accuracy: 0.0001)
        }
    }

    func testPassthroughAt16kMono() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let samples: [Float] = (0..<1_600).map { Float($0 % 7) / 10 }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer.mono(samples: samples, format: format))
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: format))
        let out = resampler.convert(buffer)
        XCTAssertEqual(out.count, 1_600)
        for (a, b) in zip(out, samples) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }

    func testFallbackPathMatchesTheCoreResampler() throws {
        let buffer = try stereoBuffer(frames: 4_800, rate: 48_000)
        let fallback = MicrophoneCapture.fallbackResample(buffer)
        XCTAssertEqual(Double(fallback.count), 1_600, accuracy: 16)
    }
}
