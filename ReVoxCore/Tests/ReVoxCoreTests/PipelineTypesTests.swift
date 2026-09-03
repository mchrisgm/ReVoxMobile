import XCTest
@testable import ReVoxCore

/// Mirrors `tests/capture/test_base.py::test_fake_backend_reads_fed_chunks`.
final class FakeAudioSourceTests: XCTestCase {
    func testReadsFedChunks() async throws {
        let source = FakeAudioSource()
        let stream = source.frames()
        try await source.start(.microphone)
        XCTAssertEqual(source.started, [.microphone])
        let chunk = [Float](repeating: 1, count: 160)
        source.feed(chunk)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, CapturedAudio(samples: chunk, endPosition: 160))
        let position = await source.capturePosition()
        XCTAssertEqual(position, 160)
        await source.stop()
        let afterStop = await iterator.next()
        XCTAssertNil(afterStop)                               // the stream finishes on stop()
        XCTAssertTrue(source.stopped)
        XCTAssertEqual(source.framesCalls, 1)
    }

    func testFreshStreamPerFramesCall() async {
        let source = FakeAudioSource()
        let first = source.frames()
        let second = source.frames()
        var firstIterator = first.makeAsyncIterator()
        let firstEnded = await firstIterator.next()
        XCTAssertNil(firstEnded)                              // the previous stream is finished
        source.feed([Float](repeating: 0.5, count: 10), endingAt: 1_000)
        var secondIterator = second.makeAsyncIterator()
        let delivered = await secondIterator.next()
        XCTAssertEqual(delivered?.endPosition, 1_000)
        XCTAssertEqual(source.framesCalls, 2)
        source.setCapturePosition(5_000)
        let position = await source.capturePosition()
        XCTAssertEqual(position, 5_000)
    }
}

final class PipelineConfigurationTests: XCTestCase {
    func testDefaults() {
        let configuration = PipelineConfiguration(captureMode: .microphone, preset: .balanced)
        XCTAssertNil(configuration.pinnedLanguage)
        XCTAssertEqual(configuration.maxPending, 3)
        XCTAssertEqual(configuration.captureGateHoldFrames, 4_800)
        XCTAssertEqual(configuration.captureLatencyFrames, 0)
        XCTAssertTrue(configuration.duckingEnabled)
        XCTAssertEqual(configuration.duckingHoldNanoseconds, 250_000_000)
        XCTAssertEqual(CaptureMode.allCases, [.microphone, .broadcast])
        XCTAssertEqual(CaptureMode.broadcast.rawValue, "broadcast")
    }

    func testAudioClipIsEmpty() {
        XCTAssertTrue(AudioClip(samples: [], sampleRate: 24_000).isEmpty)
        XCTAssertFalse(AudioClip(samples: [0], sampleRate: 24_000).isEmpty)
    }
}
