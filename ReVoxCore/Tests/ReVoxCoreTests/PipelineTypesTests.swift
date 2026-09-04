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

final class PipelineTypesProtocolTests: XCTestCase {
    private struct PlainSpeaker: Speaker {
        let sampleRate = 16_000
        func synthesize(_ text: String) async throws -> AudioClip {
            AudioClip(samples: [Float(text.count)], sampleRate: sampleRate)
        }
    }

    /// A `Speaker` that only implements the one-language method gets the two-way one for free.
    func testSpeakerDefaultLanguageOverloadForwardsToThePlainOne() async throws {
        let clip = try await PlainSpeaker().synthesize("abc", language: "fr")
        XCTAssertEqual(clip, AudioClip(samples: [3], sampleRate: 16_000))
    }

    func testSpokenPhraseDefaultsToEnglish() {
        XCTAssertEqual(SpokenPhrase(text: "hi"), SpokenPhrase(text: "hi", language: "en"))
        XCTAssertNotEqual(SpokenPhrase(text: "hi"), SpokenPhrase(text: "hi", language: "fr"))
    }

    /// The synthesized `Equatable` must keep covering the M8 and M9 fields: the view model rebuilds the pipeline
    /// when the configuration changes, and a field left out of the comparison would be a change it never sees.
    func testConfigurationEqualityCoversTheM8AndM9Fields() {
        let base = PipelineConfiguration(captureMode: .microphone, preset: .balanced)
        XCTAssertEqual(base, PipelineConfiguration(captureMode: .microphone, preset: .balanced))
        XCTAssertNil(base.ignoredLanguage)
        XCTAssertFalse(base.twoWay)
        XCTAssertNil(base.twoWayLanguage)
        XCTAssertFalse(base.wantsOriginal)
        var other = base
        other.wantsOriginal = true
        XCTAssertNotEqual(base, other)
        other = base
        other.ignoredLanguage = "es"
        XCTAssertNotEqual(base, other)
        other = base
        other.twoWay = true
        XCTAssertNotEqual(base, other)
        other = base
        other.twoWayLanguage = "fr"
        XCTAssertNotEqual(base, other)
        other = base
        other.pinnedLanguage = "fr"
        XCTAssertNotEqual(base, other)
        other = base
        other.preset = .veryFast
        XCTAssertNotEqual(base, other)
    }

    func testDefaultDependenciesBuildARealSegmenterWithThePresetAndNoSecondDirection() {
        let dependencies = PipelineDependencies(
            source: FakeAudioSource(), vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: FakeTranslator(),
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in FakePlayer(onSpeaking: onSpeaking) },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() })
        let segmenter = dependencies.segmenterFactory(EnergyVAD(), .fast) as? Segmenter
        XCTAssertEqual(segmenter?.preset, .fast)
        XCTAssertNil(dependencies.transcriber)
        XCTAssertNil(dependencies.secondaryTranslator)
        XCTAssertLessThan(abs(dependencies.clock().timeIntervalSinceNow), 5)   // the default clock is the wall clock
    }

    func testPipelineEventsCompareByPayload() {
        XCTAssertEqual(PipelineEvent.transcriptOnly(reason: "a"), .transcriptOnly(reason: "a"))
        XCTAssertNotEqual(PipelineEvent.transcriptOnly(reason: "a"), .transcriptOnly(reason: "b"))
        XCTAssertNotEqual(PipelineEvent.speaking(true), .speaking(false))
        XCTAssertEqual(PipelineState(rawValue: "error"), .error)
    }
}
