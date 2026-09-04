import XCTest
@testable import ReVoxCore

/// R9 self-capture suppression (new; no Windows counterpart).
final class CaptureGateTests: XCTestCase {
    func testDefaultHoldIs4800() {
        XCTAssertEqual(CaptureGate.defaultHoldFrames, 4_800)
        let gate = CaptureGate()
        XCTAssertEqual(gate.holdFrames, 4_800)
        XCTAssertEqual(gate.captureLatencyFrames, 0)
        XCTAssertFalse(gate.isClosed)
        XCTAssertTrue(gate.allows(chunkEndingAt: 0))
    }

    func testChunksDuringSpeakingAreDropped() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 10_000)
        XCTAssertTrue(gate.isClosed)
        XCTAssertTrue(gate.allows(chunkEndingAt: 9_999))      // ends before the edge
        XCTAssertFalse(gate.allows(chunkEndingAt: 10_000))
        XCTAssertFalse(gate.allows(chunkEndingAt: 60_000))
    }

    func testChunksWithinHoldAfterSpeakingFalseAreDropped() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(false, atPosition: 20_000)
        XCTAssertTrue(gate.isClosed)
        XCTAssertFalse(gate.allows(chunkEndingAt: 20_000))
        XCTAssertFalse(gate.allows(chunkEndingAt: 24_799))
        XCTAssertTrue(gate.allows(chunkEndingAt: 24_800))     // first chunk ending after the boundary passes
        XCTAssertTrue(gate.allows(chunkEndingAt: 9_000))      // still before the speaking-true edge
    }

    func testRetriggerDuringHoldExtendsIt() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(false, atPosition: 20_000)
        gate.speakingChanged(true, atPosition: 22_000)        // inside the hold
        XCTAssertFalse(gate.allows(chunkEndingAt: 24_800))
        XCTAssertFalse(gate.allows(chunkEndingAt: 21_000))    // the window continues from 10 000, no gap
        gate.speakingChanged(false, atPosition: 30_000)
        XCTAssertFalse(gate.allows(chunkEndingAt: 34_799))
        XCTAssertTrue(gate.allows(chunkEndingAt: 34_800))
        XCTAssertTrue(gate.allows(chunkEndingAt: 9_999))
    }

    func testSpeakingAfterHoldElapsedOpensNewWindow() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(false, atPosition: 20_000)
        gate.speakingChanged(true, atPosition: 100_000)       // long after the hold (24 800)
        XCTAssertTrue(gate.allows(chunkEndingAt: 50_000))     // between the windows: late-delivered chunks pass
        XCTAssertFalse(gate.allows(chunkEndingAt: 100_000))
    }

    func testCaptureLatencyExtendsHold() {
        var gate = CaptureGate(holdFrames: 4_800, captureLatencyFrames: 1_600)
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(false, atPosition: 20_000)
        XCTAssertFalse(gate.allows(chunkEndingAt: 26_399))
        XCTAssertTrue(gate.allows(chunkEndingAt: 26_400))
    }

    func testDuplicateEdgesAreHarmless() {
        var gate = CaptureGate()
        gate.speakingChanged(false, atPosition: 5_000)        // false before any true: ignored
        XCTAssertFalse(gate.isClosed)
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(true, atPosition: 12_000)        // duplicate true keeps the original edge
        XCTAssertFalse(gate.allows(chunkEndingAt: 11_000))
    }

    /// Dropped chunks never reach the VAD and a phrase in progress survives a closure.
    func testDroppedChunksSkipVADAndPhraseSurvivesClosure() async throws {
        let vad = EnergyVAD()
        let segmenter = Segmenter(vad: vad, preset: .balanced)
        var gate = CaptureGate()
        var reframer = ChunkReframer()
        var segments: [[Float]] = []

        // The capture stage in miniature: reframe, gate, feed.
        func deliver(_ samples: [Float]) async throws {
            let end = (reframer.expectedNextPosition ?? 0) + Int64(samples.count)
            for chunk in reframer.push(samples, endingAt: end) where gate.allows(chunkEndingAt: chunk.endPosition) {
                segments += try await segmenter.feed(chunk.samples)
            }
        }

        let speech = [Float](repeating: 0.5, count: 20 * Segmenter.chunkSamples)
        try await deliver(speech)                               // phrase starts: 20 chunks
        let callsBeforeClosure = await vad.callCount
        XCTAssertEqual(callsBeforeClosure, 20)

        gate.speakingChanged(true, atPosition: 20 * 512)        // ReVox starts speaking
        try await deliver([Float](repeating: 0.5, count: 30 * Segmenter.chunkSamples))   // its own voice: dropped
        let callsDuringClosure = await vad.callCount
        XCTAssertEqual(callsDuringClosure, 20)                  // the VAD never saw them

        gate.speakingChanged(false, atPosition: 50 * 512)       // hold until 50*512 + 4800 = 30 400
        try await deliver([Float](repeating: 0, count: 9 * Segmenter.chunkSamples))     // 25 600 … 30 208: dropped
        let callsInHold = await vad.callCount
        XCTAssertEqual(callsInHold, 20)

        try await deliver([Float](repeating: 0.5, count: 5 * Segmenter.chunkSamples))   // 30 720 …: passes, phrase resumes
        try await deliver([Float](repeating: 0, count: 15 * Segmenter.chunkSamples))    // silence gap: phrase completes
        XCTAssertEqual(segments.count, 1)
        // 20 + 5 speech chunks + 15 silence − 9 trimmed = 31 chunks: the closure left no hole and no reset
        XCTAssertEqual(segments[0].count, 31 * Segmenter.chunkSamples)
    }

    /// The stamped positions run 32 000 frames ahead of the delivered chunk positions (the reader lags the writer
    /// by 2 s); the chunks whose positions cover the stamped speaking window are still dropped.
    func testReaderLagStillDropsVoice() {
        var gate = CaptureGate()
        let lag: Int64 = 32_000
        // ReVox starts speaking when the writer is at 100 000; the reader is delivering chunks around 68 000.
        gate.speakingChanged(true, atPosition: 68_000 + lag)
        XCTAssertTrue(gate.allows(chunkEndingAt: 68_000))      // before the voice entered the ring
        XCTAssertTrue(gate.allows(chunkEndingAt: 99_999))
        XCTAssertFalse(gate.allows(chunkEndingAt: 100_000))    // the voice itself, delivered 2 s later
        gate.speakingChanged(false, atPosition: 78_000 + lag)  // writer at 110 000 → boundary 114 800
        XCTAssertFalse(gate.allows(chunkEndingAt: 110_000))
        XCTAssertFalse(gate.allows(chunkEndingAt: 114_799))
        XCTAssertTrue(gate.allows(chunkEndingAt: 114_800))
    }

    /// Broadcast lag across two utterances: the reader is still delivering chunks from the first utterance
    /// when the second speaking-true edge (stamped with the writer cursor) arrives. Those chunks are ReVox's
    /// own voice and must not reach the VAD, while the gap between the two windows stays open.
    func testLaggedChunkFromAPreviousWindowIsStillDropped() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 100_000)        // first utterance starts (writer cursor)
        gate.speakingChanged(false, atPosition: 110_000)       // first window: [100 000, 114 800)
        gate.speakingChanged(true, atPosition: 150_000)        // second utterance opens a new window
        XCTAssertFalse(gate.allows(chunkEndingAt: 105_000))    // still-unread voice of the first utterance
        XCTAssertFalse(gate.allows(chunkEndingAt: 114_799))    // last frame of the first hold
        XCTAssertTrue(gate.allows(chunkEndingAt: 114_800))     // the gap between the windows stays open
        XCTAssertTrue(gate.allows(chunkEndingAt: 130_000))
        XCTAssertFalse(gate.allows(chunkEndingAt: 150_000))    // the second window still closes
    }

    func testAZeroHoldOpensAtTheSpeakingFalseEdge() {
        var gate = CaptureGate(holdFrames: 0)
        gate.speakingChanged(true, atPosition: 10_000)
        gate.speakingChanged(false, atPosition: 20_000)
        XCTAssertFalse(gate.allows(chunkEndingAt: 19_999))
        XCTAssertTrue(gate.allows(chunkEndingAt: 20_000))
        XCTAssertTrue(gate.isClosed, "isClosed reflects the edges seen, not chunk positions")
    }

    /// One displaced slot by design: the window before the previous one is forgotten when a third opens. The
    /// reader lag it covers is bounded (2 s), so a window two utterances back has always been consumed by then.
    func testOnlyTheMostRecentlyDisplacedWindowIsRemembered() {
        var gate = CaptureGate()
        gate.speakingChanged(true, atPosition: 100_000)
        gate.speakingChanged(false, atPosition: 110_000)       // first: [100 000, 114 800)
        gate.speakingChanged(true, atPosition: 150_000)
        gate.speakingChanged(false, atPosition: 160_000)       // second: [150 000, 164 800), first displaced
        XCTAssertFalse(gate.allows(chunkEndingAt: 105_000))
        gate.speakingChanged(true, atPosition: 200_000)        // third: second displaced, first forgotten
        XCTAssertTrue(gate.allows(chunkEndingAt: 105_000))
        XCTAssertFalse(gate.allows(chunkEndingAt: 155_000))
        XCTAssertTrue(gate.allows(chunkEndingAt: 164_800))
        XCTAssertFalse(gate.allows(chunkEndingAt: 200_000))
    }

    func testGatesWithTheSameHistoryAreEqual() {
        var a = CaptureGate(holdFrames: 100, captureLatencyFrames: 5)
        var b = CaptureGate(holdFrames: 100, captureLatencyFrames: 5)
        XCTAssertEqual(a, b)
        a.speakingChanged(true, atPosition: 1)
        XCTAssertNotEqual(a, b)
        b.speakingChanged(true, atPosition: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, CaptureGate(holdFrames: 101, captureLatencyFrames: 5))
    }
}
