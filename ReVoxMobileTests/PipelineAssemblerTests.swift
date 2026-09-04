import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class PipelineAssemblerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxAssembler-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSessionMetadataMirrorsSettingsAndTheEffectiveVoice() {
        var settings = Settings()
        settings.language = "pt"
        settings.model = "base"
        settings.captureMode = "microphone"
        let startedAt = Date(timeIntervalSince1970: 1_756_800_000)
        let metadata = PipelineAssembler.sessionMetadata(for: settings, startedAt: startedAt, voice: "cosette")
        XCTAssertEqual(metadata, SessionMetadata(startedAt: startedAt, captureMode: .microphone, pinnedLanguage: "pt", modelID: "base", voice: "cosette", joinedInProgress: false))
        XCTAssertEqual(PipelineAssembler.sessionMetadata(for: settings, startedAt: startedAt, voice: "system").voice, "system")
    }

    func testBuildConfiguresTheSessionThenFailsOnAMissingVADBundle() async throws {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        let container = try TranscriptContainer.make(inMemory: true)
        let layout = ModelLayout(root: root)
        let speakers = SpeakerBundle(
            speaker: SystemSpeaker(voiceIdentifier: nil, synthesize: { _ in [] }),
            playerFactory: { _, onSpeaking in AudioPlayer(controller: controller, onSpeaking: onSpeaking) },
            voiceName: { "system" }
        )
        do {
            _ = try await PipelineAssembler.build(settings: Settings(), layout: layout, sessionController: controller,
                                                  transcriptContainer: container, speakers: speakers, progress: { _ in })
            XCTFail("expected vadLoadFailed")
        } catch let error as PipelineBuildError {
            if case .vadLoadFailed = error {} else { XCTFail("expected vadLoadFailed, got \(error)") }
            XCTAssertEqual(String(describing: error), "Voice detector failed to load. Re-download it in Models.")
        }
        XCTAssertEqual(seam.calls, ["makeEngine", "setCategory", "setActive(true)"], "the session is configured in the foreground before any model load")
        XCTAssertEqual(seam.masks.first, AudioSessionController.microphoneMask)
    }

    func testWhisperLoadFailureIsReportedWithTheModelName() {
        let error = PipelineBuildError.whisperLoadFailed(model: .small, reason: "missing files")
        XCTAssertEqual(String(describing: error), "Couldn't load small. Re-download small in Models. (missing files)")
    }

    func testTimedTranslatorForwardsToTheAdapter() async throws {
        let engine = WhisperEngine(
            load: { _ in 50_257 },
            detect: { _ in ("es", 0) },
            transcribe: { _, _ in [WhisperSegmentSnapshot(text: "Hi", noSpeechProbability: 0, tokenLogProbs: [WhisperTokenLogProb(token: 1, logProbability: -0.3)])] },
            unload: {}
        )
        let inner = WhisperKitTranslator(engine: engine)
        try await inner.load { _ in }
        let timed = TimedTranslator(inner)
        let detection = try await timed.detectLanguage(in: [0])
        XCTAssertEqual(detection.language, "es")
        XCTAssertEqual(detection.probability, 1)
        let candidate = try await timed.translate([0], language: "es")
        XCTAssertEqual(candidate.segments.first?.text, "Hi")
        XCTAssertEqual(candidate.segments.first?.averageLogProbability ?? 0, -0.3, accuracy: 0.0001)
    }

    func testBuiltPipelineExposesItsSource() {
        // A `BuiltPipeline` is only produced by a successful build (device with models); this proves the type shape.
        let source = MicrophoneCapture(controller: AudioSessionController(session: RecordingAudioSessionSeam()))
        let built = BuiltPipeline(pipeline: nil, source: source)
        XCTAssertNil(built.pipeline)
        XCTAssertTrue(built.source is MicrophoneCapture)
    }
}
