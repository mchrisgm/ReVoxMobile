import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SpeakerAssemblyTests: XCTestCase {
    /// Samples the effective speaker's status *inside* `start`, which is the only way to prove the ordering:
    /// `AssembledPipeline` must prepare the speaker before the core pipeline starts, because `SpeakerBundle.voiceName()`
    /// is read inside the transcript factory that `TranslationPipeline.start` invokes — a preparation that ran after
    /// `start` would record the previous session's voice in `SessionMetadata.voice` (§6.10).
    private final class OrderRecordingPipeline: LivePipeline, @unchecked Sendable {
        let statusAtStart = LockedBox<[SpeakerStatus]>([])
        let startedWith = LockedBox<[PipelineConfiguration]>([])
        let muted = LockedBox<[Bool]>([])
        let stopCount = LockedBox<Int>(0)
        let gapCount = LockedBox<Int>(0)
        private let speaker: EffectiveSpeaker

        init(speaker: EffectiveSpeaker) {
            self.speaker = speaker
        }

        var events: AsyncStream<PipelineEvent> { AsyncStream { $0.finish() } }

        func start(_ configuration: PipelineConfiguration) async {
            let status = await speaker.status
            statusAtStart.mutate { $0.append(status) }
            startedWith.mutate { $0.append(configuration) }
        }

        func stop() async {
            stopCount.mutate { $0 += 1 }
        }

        func setMuted(_ muted: Bool) async {
            self.muted.mutate { $0.append(muted) }
        }

        func noteCaptureGap() async {
            gapCount.mutate { $0 += 1 }
        }
    }

    private var root: URL!
    private var layout: ModelLayout!
    private var store: SettingsStore!
    private var defaults: UserDefaults!
    private var manager: ModelManager!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxSpeakerAssembly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
        defaults = UserDefaults(suiteName: "ReVoxSpeakerAssembly-\(UUID().uuidString)")
        let installer = ModelInstaller(layout: layout, steps: FakeInstallSteps().steps(layout: layout), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        manager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { false }, availableBytes: { 50_000_000_000 }, host: FakeInstallHost())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeAssembly(relay: SpeakerStatusRelay? = nil, volume: VoiceVolume = VoiceVolume()) -> SpeakerAssembly {
        // `nil`, not `SpeakerStatusRelay()`: a default argument is evaluated in the caller's nonisolated context
        // and the relay is main-actor isolated — the same rule that broke LiveViewModel's init.
        SpeakerAssembly(layout: layout, settings: store, manager: manager, relay: relay ?? SpeakerStatusRelay(),
                        voiceVolume: volume)
    }

    func testSelectionFollowsInstallStateAndSettings() async throws {
        let assembly = makeAssembly()
        var selection = await assembly.selection()
        XCTAssertEqual(selection, .systemNotDownloaded(identifier: nil), "alba is selected but pocket-tts is not installed")

        try FakeInstallSteps.fabricatePocketTTS(in: layout)
        manager.refreshInstalledStates()
        selection = await assembly.selection()
        XCTAssertEqual(selection, .systemNotDownloaded(identifier: nil), "installed but not verified is not ready (§6.9)")

        VerifiedLoadRecord(defaults: defaults).record(.pocketTTS)
        selection = await assembly.selection()
        XCTAssertEqual(selection, .pocketTTS(voice: "alba", fallbackIdentifier: nil))

        store.update { $0.voice = "system"; $0.systemVoiceIdentifier = "com.example.voice" }
        selection = await assembly.selection()
        XCTAssertEqual(selection, .system(identifier: "com.example.voice"))
    }

    func testBundleRegistersPlayersAndAppliesTheStatusGain() throws {
        let volume = VoiceVolume(0.5)
        let assembly = makeAssembly(volume: volume)
        let controller = AudioSessionController(session: RecordingAudioSessionSeam())
        let bundle = assembly.bundle(controller: controller)
        XCTAssertTrue(bundle.speaker is EffectiveSpeaker)
        XCTAssertEqual(bundle.voiceName(), "system")

        // `AudioPlayer` is ambiguous for *type* lookup in this module (`ReVoxCore.AudioPlayer` is the protocol,
        // `ReVoxMobile.AudioPlayer` the class), so the cast names the module.
        let registered = try XCTUnwrap(bundle.playerFactory(24_000, { _ in }) as? ReVoxMobile.AudioPlayer)
        XCTAssertTrue(registered.voiceVolume === volume, "the shared box reaches every player")
        XCTAssertEqual(registered.sink.gain, 0.5, accuracy: 0.0001, "voiceVolume × 1.0 for the system voice")

        assembly.runtime.update(.pocketTTS(voice: "alba"))
        XCTAssertEqual(registered.sink.gain, 0.35, accuracy: 0.0001, "voiceVolume × 0.7 once pocket-tts speaks")
        XCTAssertEqual(bundle.voiceName(), "alba")
        XCTAssertEqual(assembly.runtime.status, .pocketTTS(voice: "alba"))
    }

    func testWrappedPipelinePreparesTheSpeakerBeforeStart() async {
        let relay = SpeakerStatusRelay()
        let assembly = makeAssembly(relay: relay)
        store.update { $0.voice = "system" }
        let stub = OrderRecordingPipeline(speaker: assembly.speaker)
        let wrapped = assembly.wrap(stub)
        await wrapped.start(PipelineConfiguration(captureMode: .microphone, preset: .balanced, pinnedLanguage: nil))
        XCTAssertEqual(stub.startedWith.value.count, 1)
        XCTAssertEqual(stub.statusAtStart.value, [.systemSelected],
                       "the speaker was already prepared when the core pipeline's start ran, not afterwards")
        let status = await assembly.speaker.status
        XCTAssertEqual(status, .systemSelected, "prepared with the session's selection")
        await waitUntil("relay") { relay.status == .systemSelected }
        XCTAssertEqual(assembly.runtime.status, .systemSelected)
        await wrapped.setMuted(true)
        await wrapped.stop()
        XCTAssertEqual(stub.muted.value, [true])
        XCTAssertEqual(stub.stopCount.value, 1)
    }
}
