import XCTest
@testable import ReVoxCore

final class ClipHeadTests: XCTestCase {
    private let rate = 24_000

    private func frames(_ milliseconds: Int) -> Int { rate * milliseconds / 1000 }

    private func tone(_ milliseconds: Int, amplitude: Float = 0.5) -> [Float] {
        (0 ..< frames(milliseconds)).map { amplitude * sin(Float($0) * 2 * .pi * 220 / Float(rate)) }
    }

    private func silence(_ milliseconds: Int) -> [Float] { [Float](repeating: 0, count: frames(milliseconds)) }

    func testAClickBeforeTheSpeechIsDropped() {
        let click = [Float](repeating: 1, count: frames(3))
        let clip = click + silence(40) + tone(200)
        let onset = ClipHead.onset(of: clip, sampleRate: rate)
        XCTAssertNotNil(onset)
        // The onset lands in the 2 ms window that straddles the tone's first sample, so it can read one window early.
        XCTAssertGreaterThanOrEqual(onset ?? 0, click.count + silence(40).count - frames(2), "the click is not the onset: it is loud but not sustained")
        let out = ClipHead.conditioned(clip, sampleRate: rate)
        XCTAssertEqual(out.count, clip.count - (onset! - frames(10)))
        XCTAssertEqual(out[0], 0, "starts on the ramp")
        XCTAssertLessThan(out[0 ..< frames(10)].map(abs).max() ?? 1, 0.5, "the lead is ramped, not stepped")
        XCTAssertFalse(out.prefix(frames(30)).contains { abs($0) >= 0.99 }, "the click is gone")
    }

    /// A steady offset has no swing, so it is never mistaken for speech however loud it is.
    func testADCOffsetBeforeTheSpeechIsDropped() {
        let offset = [Float](repeating: 0.3, count: frames(50))
        let clip = offset + tone(200, amplitude: 0.9)
        let onset = ClipHead.onset(of: clip, sampleRate: rate)
        XCTAssertGreaterThanOrEqual(onset ?? 0, offset.count - frames(2))
        let out = ClipHead.conditioned(clip, sampleRate: rate)
        XCTAssertLessThan(out.count, clip.count - frames(38), "all but the 10 ms lead of the offset is gone")
        XCTAssertEqual(out[0], 0, "the lead is ramped from zero, so the remaining offset is no longer a step")
    }

    func testACleanClipLosesAtMostTheLead() {
        let clip = tone(300)
        let out = ClipHead.conditioned(clip, sampleRate: rate)
        XCTAssertGreaterThanOrEqual(out.count, clip.count - frames(10))
        XCTAssertEqual(out[0], 0)
        XCTAssertEqual(Array(out.suffix(100)), Array(clip.suffix(100)), "the tail is untouched")
    }

    func testSilenceAndTinyClipsAreReturnedUnchanged() {
        let quiet = silence(100)
        XCTAssertEqual(ClipHead.conditioned(quiet, sampleRate: rate), quiet)
        XCTAssertNil(ClipHead.onset(of: quiet, sampleRate: rate))
        let tiny = tone(5)
        XCTAssertEqual(ClipHead.conditioned(tiny, sampleRate: rate), tiny)
        XCTAssertEqual(ClipHead.conditioned([], sampleRate: rate), [])
    }

    func testTheConstantsAreTheDocumentedOnes() {
        XCTAssertEqual(ClipHead.windowMilliseconds, 2)
        XCTAssertEqual(ClipHead.sustainWindows, 4)
        XCTAssertEqual(ClipHead.onsetRatio, 0.05)
        XCTAssertEqual(ClipHead.leadMilliseconds, 10)
    }

    /// A sample rate of zero (an engine that reported nothing) or below must degrade, never trap or hang.
    func testAZeroOrNegativeSampleRateDoesNotTrap() {
        let clip = tone(50)
        for badRate in [0, -24_000] {
            let out = ClipHead.conditioned(clip, sampleRate: badRate)
            XCTAssertLessThanOrEqual(out.count, clip.count, "\(badRate)")
            XCTAssertFalse(out.isEmpty, "\(badRate)")
            if let onset = ClipHead.onset(of: clip, sampleRate: badRate) {
                XCTAssertTrue((0 ..< clip.count).contains(onset), "\(badRate)")
            }
        }
    }
}
