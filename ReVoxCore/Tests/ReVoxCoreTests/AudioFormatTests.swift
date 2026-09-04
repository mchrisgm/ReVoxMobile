import XCTest
@testable import ReVoxCore

/// Mirrors `tests/capture/test_base.py::test_to_mono_16k_*` (deviation W1: linear-interpolation reference resampler).
final class AudioFormatTests: XCTestCase {
    func testPipelineSampleRateConstant() {
        XCTAssertEqual(AudioFormat.pipelineSampleRate, 16_000)
    }

    func testDownmixesAndResamples() {
        let stereo48k = [Float](repeating: 0, count: 4800 * 2)
        let out = AudioFormat.toMono16k(interleaved: stereo48k, channels: 2, sampleRate: 48_000)
        XCTAssertLessThanOrEqual(abs(out.count - 1600), 16)
    }

    func testDownmixAveragesChannels() {
        var interleaved: [Float] = []
        for _ in 0 ..< 4800 {
            interleaved += [1.0, 0.0]       // L = 1, R = 0
        }
        let mono = AudioFormat.downmixInterleaved(interleaved, channels: 2)
        XCTAssertEqual(mono.count, 4800)
        XCTAssertEqual(mono.first, 0.5)
        XCTAssertEqual(mono.last, 0.5)
    }

    func testPassthroughAt16kMono() {
        let mono = [Float](repeating: 1, count: 1600)
        let out = AudioFormat.toMono16k(interleaved: mono, channels: 1, sampleRate: AudioFormat.pipelineSampleRate)
        XCTAssertEqual(out, mono)
        XCTAssertEqual(AudioFormat.resample(mono, from: 16_000, to: 16_000), mono)
    }

    func testPlanarAndInterleavedDownmixAgree() {
        let left: [Float] = [0.2, 0.4, 0.6]
        let right: [Float] = [0.0, 0.4, 1.0]
        let planar = AudioFormat.downmixPlanar([left, right])
        let interleaved = AudioFormat.downmixInterleaved([0.2, 0.0, 0.4, 0.4, 0.6, 1.0], channels: 2)
        XCTAssertEqual(planar, interleaved)
        XCTAssertEqual(planar, [0.1, 0.4, 0.8])
        XCTAssertEqual(AudioFormat.downmixPlanar([left]), left)
    }

    func testSineKeepsFrequencyThroughResampler() {
        let sourceRate = 48_000
        let sine = (0 ..< sourceRate).map { Float(sin(2 * Double.pi * 1000 * Double($0) / Double(sourceRate))) }
        let out = AudioFormat.resample(sine, from: sourceRate, to: 16_000)
        XCTAssertEqual(out.count, 16_000)
        var crossings = 0
        for index in 1 ..< out.count where (out[index - 1] < 0) != (out[index] < 0) {
            crossings += 1
        }
        XCTAssertLessThanOrEqual(abs(crossings - 2000), 20)   // 1 kHz for 1 s = 2 000 zero crossings, within 1 %
    }

    func testResampleLengthRule() {
        let samples = [Float](repeating: 0.25, count: 4410)
        XCTAssertEqual(AudioFormat.resample(samples, from: 44_100, to: 16_000).count, 1600)
        XCTAssertEqual(AudioFormat.resample(samples, from: 44_100, to: 16_000).first, 0.25)
        XCTAssertEqual(AudioFormat.resample([], from: 48_000, to: 16_000), [])
    }

    func testFloat32FromInt16() {
        XCTAssertEqual(AudioFormat.float32(fromInt16: [Int16.min, 0, 16_384, Int16.max]), [-1.0, 0.0, 0.5, 32767.0 / 32768.0])
    }

    /// Degenerate geometry (no channels, no rate, no data) must come back unchanged or empty, never trap.
    func testDegenerateInputsAreReturnedUnchangedOrEmpty() {
        XCTAssertEqual(AudioFormat.downmixInterleaved([1, 2], channels: 0), [1, 2])
        XCTAssertEqual(AudioFormat.downmixInterleaved([1, 2], channels: -1), [1, 2])
        XCTAssertEqual(AudioFormat.downmixInterleaved([1, 2, 3], channels: 2), [1.5])      // a trailing half frame is dropped
        XCTAssertEqual(AudioFormat.downmixInterleaved([], channels: 2), [])
        XCTAssertEqual(AudioFormat.downmixPlanar([]), [])
        XCTAssertEqual(AudioFormat.downmixPlanar([[1, 2, 3], [1]]), [1])                   // the shortest channel bounds the frames
        XCTAssertEqual(AudioFormat.resample([1, 2], from: 0, to: 16_000), [1, 2])
        XCTAssertEqual(AudioFormat.resample([1, 2], from: 16_000, to: 0), [1, 2])
        XCTAssertEqual(AudioFormat.resample([5], from: 48_000, to: 16_000), [])           // rounds to no output sample
        XCTAssertEqual(AudioFormat.toMono16k(interleaved: [1, 1], channels: 2, sampleRate: 0), [1])
    }

    func testUpsamplingInterpolatesLinearly() {
        let out = AudioFormat.resample([0, 1, 2, 3], from: 8_000, to: 16_000)
        XCTAssertEqual(out.count, 8)
        XCTAssertEqual(out[0], 0)
        XCTAssertEqual(out[1], 0.5)
        XCTAssertEqual(out[6], 3)                                                            // clamped at the last sample
        XCTAssertEqual(out[7], 3)
    }
}
