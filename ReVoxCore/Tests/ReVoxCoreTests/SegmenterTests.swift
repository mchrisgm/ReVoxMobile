import XCTest
@testable import ReVoxCore

/// Mirrors `tests/pipeline/test_segmenter.py`.
final class SegmenterTests: XCTestCase {
    private let sampleRate = 16_000

    private func speech(_ ms: Int) -> [Float] {
        [Float](repeating: 0.5, count: sampleRate * ms / 1000)
    }

    private func silence(_ ms: Int) -> [Float] {
        [Float](repeating: 0, count: sampleRate * ms / 1000)
    }

    /// The Windows test cadence: 1 600-sample slices.
    private func feedAll(_ segmenter: Segmenter, _ audio: [Float], slice: Int = 1600) async throws -> [[Float]] {
        var segments: [[Float]] = []
        var start = 0
        while start < audio.count {
            let end = min(start + slice, audio.count)
            segments += try await segmenter.feed(Array(audio[start ..< end]))
            start = end
        }
        return segments
    }

    /// M9: not a Windows port — Windows has two presets. The numbers are the iOS choice and are asserted here
    /// so the constant gate sees them like the ported ones.
    func testVeryFastPresetIsAnIOSAdditionNotAPort() {
        XCTAssertEqual(SegmenterPreset.veryFast.rawValue, "very_fast")
        XCTAssertEqual(SegmenterPreset.veryFast.silenceMs, 200)
        XCTAssertEqual(SegmenterPreset.veryFast.maxSegmentSeconds, 3.0)
        let veryFast = Segmenter(vad: EnergyVAD(), preset: .veryFast)
        XCTAssertEqual(veryFast.silenceChunks, 6)      // int(0.2 * 16000 / 512)
        XCTAssertEqual(veryFast.maxChunks, 93)         // int(3.0 * 16000 / 512)
        XCTAssertEqual(veryFast.paddingChunks, 6)
        XCTAssertEqual(SegmenterPreset.allCases, [.balanced, .fast, .veryFast])
    }

    func testPresets() {
        XCTAssertEqual(SegmenterPreset.balanced.silenceMs, 500)
        XCTAssertEqual(SegmenterPreset.balanced.maxSegmentSeconds, 10.0)
        XCTAssertEqual(SegmenterPreset.fast.silenceMs, 300)
        XCTAssertEqual(SegmenterPreset.fast.maxSegmentSeconds, 4.0)
        XCTAssertEqual(SegmenterPreset.allCases, [.balanced, .fast, .veryFast])   // veryFast is M9's own, see below
        XCTAssertEqual(SegmenterPreset.balanced.rawValue, "balanced")
        XCTAssertEqual(SegmenterPreset.fast.rawValue, "fast")
    }

    func testChunkAndSampleRateConstants() {
        XCTAssertEqual(Segmenter.chunkSamples, 512)
        XCTAssertEqual(Segmenter.sampleRate, 16_000)
        XCTAssertEqual(Segmenter.defaultSpeechThreshold, 0.5)
        XCTAssertEqual(Segmenter.defaultPaddingMs, 200)
    }

    func testChunkCounts() {
        let balanced = Segmenter(vad: EnergyVAD(), preset: .balanced)
        XCTAssertEqual(balanced.silenceChunks, 15)
        XCTAssertEqual(balanced.maxChunks, 312)
        XCTAssertEqual(balanced.paddingChunks, 6)
        let fast = Segmenter(vad: EnergyVAD(), preset: .fast)
        XCTAssertEqual(fast.silenceChunks, 9)
        XCTAssertEqual(fast.maxChunks, 125)
        XCTAssertEqual(fast.paddingChunks, 6)
        XCTAssertEqual(balanced.speechThreshold, 0.5)
    }

    func testEmitsSegmentAfterSilenceGap() async throws {
        let segmenter = Segmenter(vad: EnergyVAD(), preset: .balanced)
        let segments = try await feedAll(segmenter, silence(300) + speech(1000) + silence(700))
        XCTAssertEqual(segments.count, 1)
        // roughly the speech length plus padding, well under the total
        XCTAssertGreaterThan(Double(segments[0].count), Double(sampleRate) * 0.8)
        XCTAssertLessThan(Double(segments[0].count), Double(sampleRate) * 1.6)
    }

    func testNoSegmentForPureSilence() async throws {
        let segmenter = Segmenter(vad: EnergyVAD())
        let segments = try await feedAll(segmenter, silence(2000))
        XCTAssertTrue(segments.isEmpty)
        XCTAssertNil(segmenter.flush())
    }

    func testShortPauseDoesNotSplit() async throws {
        let segmenter = Segmenter(vad: EnergyVAD(), preset: .balanced)   // 500 ms gap needed
        let segments = try await feedAll(segmenter, speech(500) + silence(200) + speech(500) + silence(700))
        XCTAssertEqual(segments.count, 1)
    }

    func testLongPauseSplits() async throws {
        let segmenter = Segmenter(vad: EnergyVAD(), preset: .fast)       // 300 ms gap
        let segments = try await feedAll(segmenter, speech(500) + silence(500) + speech(500) + silence(500))
        XCTAssertEqual(segments.count, 2)
    }

    func testMaxSegmentForcesEmit() async throws {
        let segmenter = Segmenter(vad: EnergyVAD(), preset: .fast)       // max 4 s
        let segments = try await feedAll(segmenter, speech(9000))
        XCTAssertGreaterThanOrEqual(segments.count, 2)
        for segment in segments {
            XCTAssertLessThanOrEqual(Double(segment.count), Double(sampleRate) * 4.2)
        }
    }

    func testFlushReturnsPartial() async throws {
        let segmenter = Segmenter(vad: EnergyVAD())
        _ = try await feedAll(segmenter, speech(800))
        let flushed = try XCTUnwrap(segmenter.flush())
        XCTAssertGreaterThanOrEqual(Double(flushed.count), Double(sampleRate) * 0.7)
        XCTAssertNil(segmenter.flush())
    }

    func testSliceCadenceDoesNotChangeSegments() async throws {
        let audio = silence(300) + speech(1000) + silence(700) + speech(600) + silence(600)
        let coarse = try await feedAll(Segmenter(vad: EnergyVAD()), audio, slice: 1600)
        let fine = try await feedAll(Segmenter(vad: EnergyVAD()), audio, slice: 480)
        XCTAssertEqual(coarse, fine)
    }

    func testTailTrimmingAndPreRollClearedAfterEmit() async throws {
        // Chunk-aligned durations: 6 chunks silence, 32 chunks speech, 15 chunks silence (= silenceChunks), twice.
        let chunk = Segmenter.chunkSamples
        let preRollSilence = [Float](repeating: 0, count: 6 * chunk)
        let phrase = [Float](repeating: 0.5, count: 32 * chunk)
        let gap = [Float](repeating: 0, count: 15 * chunk)
        let segmenter = Segmenter(vad: EnergyVAD(), preset: .balanced)
        let segments = try await feedAll(segmenter, preRollSilence + phrase + gap + phrase + gap, slice: chunk)
        XCTAssertEqual(segments.count, 2)
        // 6 pre-roll + 32 speech + 15 silence − (15 − 6) trimmed = 44 chunks
        XCTAssertEqual(segments[0].count, 44 * chunk)
        // pre-roll was cleared by the first emit: 0 + 32 + 6 = 38 chunks
        XCTAssertEqual(segments[1].count, 38 * chunk)
    }

    func testResetForgetsStateAndResetsVAD() async throws {
        let vad = EnergyVAD()
        let segmenter = Segmenter(vad: vad)
        _ = try await feedAll(segmenter, speech(800))
        await segmenter.reset()
        XCTAssertNil(segmenter.flush())
        let resets = await vad.resetCount
        XCTAssertEqual(resets, 1)
    }
}
