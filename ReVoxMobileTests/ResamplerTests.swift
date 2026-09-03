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

    func testStereo48kTo16k() throws {
        let buffer = try stereoBuffer(frames: 4_800, rate: 48_000)
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: buffer.format))
        let out = resampler.convert(buffer)
        XCTAssertEqual(Double(out.count), 1_600, accuracy: 16)   // the Windows tolerance (W1)
        XCTAssertEqual(out.count, out.filter { $0.isFinite }.count)
    }

    func testAgreesWithTheCoreReferenceResampler() throws {
        let buffer = try stereoBuffer(frames: 48_000, rate: 48_000)
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: buffer.format))
        let production = resampler.convert(buffer)
        let mono = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 48_000))
        let reference = AudioFormat.resample(mono, from: 48_000, to: 16_000)
        XCTAssertEqual(Double(production.count), Double(reference.count), accuracy: 16)
        // A 1 kHz tone keeps its frequency on both paths: ~2 000 zero crossings per second.
        let productionCrossings = zeroCrossings(production)
        let referenceCrossings = zeroCrossings(reference)
        XCTAssertEqual(Double(productionCrossings), Double(referenceCrossings), accuracy: Double(referenceCrossings) * 0.01)
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
