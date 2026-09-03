import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class AudioPlayerTests: XCTestCase {
    private func sine(count: Int, rate: Double, hz: Double = 440) -> [Float] {
        (0..<count).map { Float(sin(2 * Double.pi * hz * Double($0) / rate)) * 0.5 }
    }

    func testMuteWithEngineStoppedDoesNotCrash() async throws {
        // A real engine that is never started; the seam records the session calls instead of touching AVAudioSession.
        let seam = RecordingAudioSessionSeam()
        let liveEngine = AVAudioEngine()
        seam.engineFactory = {
            let fake = FakeEngineSeam()
            fake.engine = liveEngine
            return fake
        }
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        let hookCalls = Counter()
        let player = AudioPlayer(controller: controller, onSpeaking: { _ in })
        await controller.setPlayHook { hookCalls.increment() }
        let graphEngine = await controller.engineForGraph()
        let engine = try XCTUnwrap(graphEngine)
        player.sink.attach(to: engine)

        await player.enqueue(AudioClip(samples: sine(count: 2_400, rate: 24_000), sampleRate: 24_000))
        await player.setMuted(true)          // stopCurrent() → playerNode.stop() only
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(hookCalls.value, 0, "no play() while the engine is stopped")
        let count = await controller.playCount
        XCTAssertEqual(count, 0)
        await player.stop()
    }

    func testPlayOnlyAfterEngineStart() async throws {
        // `player.start()` installs its own play hook (the node's `play()`), so this test counts the controller's
        // `playCount` instead of a hook of its own, and gives the seam a real engine so the node is attached
        // before the hook can fire.
        let seam = RecordingAudioSessionSeam()
        let liveEngine = AVAudioEngine()
        seam.engineFactory = {
            let fake = FakeEngineSeam()
            fake.engine = liveEngine
            return fake
        }
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)
        let engine = try XCTUnwrap(seam.lastEngine)
        let player = AudioPlayer(controller: controller, onSpeaking: { _ in })

        engine.startFails = true
        do {
            try await player.start()
            XCTFail("start should propagate the engine failure")
        } catch {}
        var plays = await controller.playCount
        XCTAssertEqual(plays, 0, "no play() when the engine refused to start")
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(player.sink.playerNode.engine === liveEngine, "start() attached the node before installing the hook")

        engine.startFails = false
        try await player.start()
        plays = await controller.playCount
        XCTAssertEqual(plays, 1, "exactly one play() after a successful start")
        XCTAssertEqual(engine.startCount, 2)
        XCTAssertTrue(engine.isRunning)
        // The hook itself is `if engine.isRunning { play() }` (§6.7): the seam reports a running engine while the
        // real `AVAudioEngine` behind it is not, so the node was left alone and no Objective-C exception was raised.
        XCTAssertFalse(player.sink.playerNode.isPlaying)
        await player.stop()
    }

    func testClipsAtOtherRatesAreConvertedToTheNodeRate() throws {
        let sink = PlayerNodeSink(onStopped: {})
        let buffer = try XCTUnwrap(sink.makeBuffer(for: AudioClip(samples: sine(count: 1_600, rate: 16_000), sampleRate: 16_000)))
        XCTAssertEqual(buffer.format.sampleRate, 24_000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        XCTAssertEqual(Double(buffer.frameLength), 2_400, accuracy: 16)

        let native = try XCTUnwrap(sink.makeBuffer(for: AudioClip(samples: sine(count: 2_400, rate: 24_000), sampleRate: 24_000)))
        XCTAssertEqual(native.frameLength, 2_400)
    }

    func testGainIsVoiceVolumeTimesEngineGainAndClamped() throws {
        let sink = PlayerNodeSink(onStopped: {})
        sink.setVoiceVolume(0.5)
        sink.setEngineGain(0.7)
        XCTAssertEqual(sink.gain, 0.35, accuracy: 0.0001)

        sink.setVoiceVolume(1.0)
        sink.setEngineGain(1.5)
        let buffer = try XCTUnwrap(sink.makeBuffer(for: AudioClip(samples: [0.5, -0.5, 1.0], sampleRate: 24_000)))
        let samples = buffer.monoFloatSamples
        XCTAssertEqual(samples[0], 0.75, accuracy: 0.0001)
        XCTAssertEqual(samples[1], -0.75, accuracy: 0.0001)
        XCTAssertEqual(samples[2], 1.0, accuracy: 0.0001, "clamped to ±1")
    }

    func testEmptyClipIsIgnoredAndNeverScheduled() async {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let player = AudioPlayer(controller: controller, onSpeaking: { _ in })
        await player.enqueue(AudioClip(samples: [], sampleRate: 24_000))
        let speaking = await player.isSpeaking
        XCTAssertFalse(speaking)
        XCTAssertEqual(player.sink.lastScheduledFrameLength, 0)
    }

    /// Streaming keeps the converter's tail for the next buffer; end-of-stream flushes it, so a one-shot clip
    /// keeps its last millisecond instead of leaving it inside the converter (§6.1).
    func testConverterDriverDrainsUntilInputRanDryAndFlushesOnEndOfStream() throws {
        let input = try XCTUnwrap(AVAudioPCMBuffer.mono(samples: sine(count: 4_800, rate: 48_000), format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!))

        let streaming = try XCTUnwrap(AVAudioConverter(from: input.format, to: PCMConverterDriver.pipelineFormat))
        let first = try PCMConverterDriver.convertToMono(input, with: streaming)
        let second = try PCMConverterDriver.convertToMono(input, with: streaming)
        XCTAssertGreaterThan(first.count, 0)
        XCTAssertEqual(Double(first.count + second.count), 3_200, accuracy: 32, "counts \(first.count), \(second.count)")
        XCTAssertEqual(Double(second.count), 1_600, accuracy: 16, "steady state after priming")

        let oneShot = try XCTUnwrap(AVAudioConverter(from: input.format, to: PCMConverterDriver.pipelineFormat))
        let flushed = try PCMConverterDriver.convertToMono(input, with: oneShot, endOfStream: true)
        XCTAssertEqual(Double(flushed.count), 1_600, accuracy: 16, "the flush gives back the whole clip")
        // Reset after the flush: the next clip starts clean rather than carrying this one's tail.
        let again = try PCMConverterDriver.convertToMono(input, with: oneShot, endOfStream: true)
        XCTAssertEqual(Double(again.count), 1_600, accuracy: 16)

        XCTAssertEqual(PCMConverterDriver.outputCapacity(inputFrames: 4_800, inputRate: 48_000, outputRate: 16_000), 1_664)
    }
}
