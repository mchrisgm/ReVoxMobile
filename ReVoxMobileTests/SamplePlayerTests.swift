import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// "Play sample" (§8.4) over a real `AVAudioEngine` that is never started (the seam's fake engine answers
/// `start()`), a system voice whose synthesis can be made to fail, and a pocket-tts engine that never loads.
/// One node per sample: whatever exit the sequence takes, the player node must not stay attached to the engine,
/// or every sample tap adds a node that the next session's engine start then renders — and `AudioPlayerTests`
/// records what accumulated nodes did to the simulator's audio subsystem in cleanup.
@MainActor
final class SamplePlayerTests: XCTestCase {
    private final class Voices: @unchecked Sendable {
        private let lock = NSLock()
        private var spoken: [String] = []
        private var failing = false

        var texts: [String] { lock.lock(); defer { lock.unlock() }; return spoken }
        var failSynthesis: Bool {
            get { lock.lock(); defer { lock.unlock() }; return failing }
            set { lock.lock(); failing = newValue; lock.unlock() }
        }

        func speaker() -> EffectiveSpeaker {
            EffectiveSpeaker(
                makePocketTTS: { voice in
                    PocketTTSSpeaker(voice: voice, engine: PocketTTSSpeaker.Engine(
                        initialize: { throw SpeakerError.synthesisFailed("no ANE") },
                        setVoice: { _ in },
                        synthesize: { _, _ in [] }
                    ))
                },
                makeSystem: { [self] identifier in
                    SystemSpeaker(voiceIdentifier: identifier, synthesize: { [self] utterance in
                        lock.lock(); spoken.append(utterance.speechString); let fail = failing; lock.unlock()
                        if fail { throw SpeakerError.synthesisFailed("sample refused") }
                        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
                        return [AVAudioPCMBuffer.mono(samples: [0.1, 0.2, 0.3], format: format)!]
                    })
                }
            )
        }
    }

    private var liveEngine: AVAudioEngine!
    private var fakeEngine: FakeEngineSeam!
    private var seam: RecordingAudioSessionSeam!
    private var controller: AudioSessionController!
    private var voices: Voices!
    private var sample: SamplePlayer!

    override func setUp() {
        liveEngine = AVAudioEngine()
        let fake = FakeEngineSeam()
        fake.engine = liveEngine
        fakeEngine = fake
        seam = RecordingAudioSessionSeam()
        seam.engineFactory = { fake }
        controller = AudioSessionController(session: seam)
        voices = Voices()
        sample = SamplePlayer.make(sessionController: controller, speaker: voices.speaker(), runtime: SpeakerAssembly.Runtime(),
                                   voiceVolume: VoiceVolume(), captureMode: { .microphone })
    }

    override func tearDown() {
        // The same teardown as `AudioPlayerTests`: give the CoreAudio resources of a real engine back.
        liveEngine.stop()
    }

    private var attachedPlayerNodes: Int {
        liveEngine.attachedNodes.filter { $0 is AVAudioPlayerNode }.count
    }

    func testARefusedEngineStartDetachesTheNodeAndRethrows() async {
        fakeEngine.startFails = true
        do {
            try await sample.play(.system(identifier: nil), "Hello")
            XCTFail("the engine refusal must reach the Voices screen")
        } catch {
            XCTAssertTrue(seam.calls.contains("setCategory"), "the session was configured first (§6.8)")
        }
        XCTAssertEqual(attachedPlayerNodes, 0, "the node attached by start() is detached again on the throw")
        XCTAssertEqual(voices.texts, [], "nothing was synthesised")
    }

    func testAFailedSynthesisDetachesTheNodeAndRethrows() async {
        voices.failSynthesis = true
        do {
            try await sample.play(.system(identifier: nil), "Hello")
            XCTFail("the synthesis failure must reach the Voices screen")
        } catch {
            XCTAssertEqual(error as? SpeakerError, .synthesisFailed("sample refused"))
        }
        XCTAssertEqual(attachedPlayerNodes, 0)
        XCTAssertEqual(voices.texts, ["Hello"])
        XCTAssertGreaterThanOrEqual(fakeEngine.stopCount, 1, "the player was stopped, which stops the engine")
    }

    /// The happy path, with a whitespace phrase so the clip is empty and the wait for playback ends at once.
    func testACompletedSampleStopsThePlayerAndDetachesTheNode() async throws {
        try await sample.play(.system(identifier: nil), "   ")
        XCTAssertEqual(attachedPlayerNodes, 0)
        XCTAssertEqual(fakeEngine.startCount, 1)
        XCTAssertGreaterThanOrEqual(fakeEngine.stopCount, 1)
        XCTAssertEqual(voices.texts, [], "whitespace touches no engine (the Speaker contract)")
    }

    /// Three samples in a row, whatever their outcome, leave the engine as they found it.
    func testRepeatedSamplesNeverAccumulateNodes() async {
        _ = try? await sample.play(.system(identifier: nil), "   ")
        voices.failSynthesis = true
        _ = try? await sample.play(.system(identifier: nil), "One")
        voices.failSynthesis = false
        _ = try? await sample.play(.pocketTTS(voice: "alba", fallbackIdentifier: nil), "   ")   // pocket-tts refuses to load: a fallback, not an error
        XCTAssertEqual(attachedPlayerNodes, 0)
    }
}
