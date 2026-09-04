import XCTest
@testable import ReVoxMobile

final class SelfCaptureProbeTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(SelfCaptureProbe.voiceThresholdLevel, 0.01)
        XCTAssertEqual(SelfCaptureProbe.windowFrames, 32_000)
        XCTAssertEqual(BroadcastTuning.captureLatencyFrames, 0, "ASSUMED until measured on device (row 7)")
        XCTAssertEqual(BroadcastTuning.measurementSource, "docs/measurements/m5-broadcast-capture.md row 7")
    }

    func testMeasuresTheVoiceTailAfterTheFalseEdge() {
        var probe = SelfCaptureProbe()
        XCTAssertNil(probe.observe(chunkEndingAt: 512, rms: 0.3, peak: 0.5), "nothing armed")
        probe.speakingChanged(true, atPosition: 1_000)
        XCTAssertNil(probe.observe(chunkEndingAt: 1_512, rms: 0.2, peak: 0.4))
        XCTAssertNil(probe.observe(chunkEndingAt: 2_024, rms: 0.25, peak: 0.6))
        probe.speakingChanged(false, atPosition: 9_000)
        XCTAssertNil(probe.observe(chunkEndingAt: 9_512, rms: 0.2, peak: 0.3), "still voice, inside the window")
        XCTAssertNil(probe.observe(chunkEndingAt: 12_200, rms: 0.05, peak: 0.1))
        XCTAssertNil(probe.observe(chunkEndingAt: 12_712, rms: 0.001, peak: 0.002), "silence: not counted")
        XCTAssertNil(probe.observe(chunkEndingAt: 40_999, rms: 0.0, peak: 0.0), "window not over yet")
        let measurement = probe.observe(chunkEndingAt: 41_512, rms: 0.0, peak: 0.0)
        XCTAssertEqual(measurement, SelfCaptureProbe.Measurement(edgePosition: 9_000, lastVoiceEnd: 12_200, peakWhileSpeaking: 0.6, peakAfterEdge: 0.3))
        XCTAssertEqual(measurement?.tailFrames, 3_200)
        XCTAssertNil(probe.observe(chunkEndingAt: 42_024, rms: 0.5, peak: 0.5), "disarmed after the measurement")
    }

    func testNoVoiceAfterTheEdgeGivesAZeroTailAndTheSpeakingPeak() {
        var probe = SelfCaptureProbe()
        probe.speakingChanged(true, atPosition: 0)
        _ = probe.observe(chunkEndingAt: 512, rms: 0.0005, peak: 0.001)          // ReVox's voice is not in the ring at all
        probe.speakingChanged(false, atPosition: 4_000)
        let measurement = probe.observe(chunkEndingAt: 36_001, rms: 0, peak: 0)
        XCTAssertEqual(measurement?.tailFrames, 0)
        XCTAssertEqual(measurement?.peakWhileSpeaking, 0.001)
        XCTAssertEqual(measurement?.peakAfterEdge, 0)
    }

    func testRetriggerDuringTheWindowRestartsTheMeasurement() {
        var probe = SelfCaptureProbe()
        probe.speakingChanged(true, atPosition: 0)
        probe.speakingChanged(false, atPosition: 5_000)
        _ = probe.observe(chunkEndingAt: 5_512, rms: 0.2, peak: 0.2)
        probe.speakingChanged(true, atPosition: 6_000)                            // next phrase started inside the window
        XCTAssertNil(probe.observe(chunkEndingAt: 40_000, rms: 0, peak: 0), "the first window was abandoned")
        probe.speakingChanged(false, atPosition: 41_000)
        XCTAssertNil(probe.observe(chunkEndingAt: 41_512, rms: 0.2, peak: 0.2))
        XCTAssertEqual(probe.observe(chunkEndingAt: 73_512, rms: 0, peak: 0)?.edgePosition, 41_000)
    }
}
