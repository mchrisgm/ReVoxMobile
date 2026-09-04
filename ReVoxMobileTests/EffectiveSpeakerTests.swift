import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class EffectiveSpeakerTests: XCTestCase {
    /// Counts pocket-tts engine calls across every `PocketTTSSpeaker` the effective speaker creates.
    private final class PocketRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var initializeCalls = 0
        private var synthesisCalls = 0
        private var voices: [String] = []
        var failInitialize = false
        var failSynthesisOnce = false
        /// When set, `initialize` blocks until it is cleared — a window in which the reentrant actor can accept
        /// another call.
        var holdInitialize: Bool {
            get { lock.lock(); defer { lock.unlock() }; return holding }
            set { lock.lock(); holding = newValue; lock.unlock() }
        }
        private var holding = false

        var initializes: Int { lock.lock(); defer { lock.unlock() }; return initializeCalls }
        var syntheses: Int { lock.lock(); defer { lock.unlock() }; return synthesisCalls }
        var createdVoices: [String] { lock.lock(); defer { lock.unlock() }; return voices }

        func factory() -> EffectiveSpeaker.PocketTTSFactory {
            { [self] voice in
                lock.lock(); voices.append(voice); lock.unlock()
                let engine = PocketTTSSpeaker.Engine(
                    initialize: { [self] in
                        lock.lock(); initializeCalls += 1; let fail = failInitialize; lock.unlock()
                        while holdInitialize {
                            try await Task.sleep(nanoseconds: 5_000_000)
                        }
                        if fail { throw SpeakerError.synthesisFailed("no ANE") }
                    },
                    setVoice: { _ in },
                    synthesize: { [self] _, _ in
                        lock.lock(); synthesisCalls += 1; let fail = failSynthesisOnce; failSynthesisOnce = false; lock.unlock()
                        if fail { throw SpeakerError.synthesisFailed("decoder") }
                        return [Float](repeating: 0.5, count: 2_400)
                    }
                )
                return PocketTTSSpeaker(voice: voice, engine: engine)
            }
        }
    }

    private final class SystemRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requested: [String?] = []
        private var spoken: [String] = []

        var identifiers: [String?] { lock.lock(); defer { lock.unlock() }; return requested }
        var texts: [String] { lock.lock(); defer { lock.unlock() }; return spoken }

        func factory() -> EffectiveSpeaker.SystemFactory {
            { [self] identifier in
                lock.lock(); requested.append(identifier); lock.unlock()
                return SystemSpeaker(voiceIdentifier: identifier, synthesize: { [self] utterance in
                    lock.lock(); spoken.append(utterance.speechString); lock.unlock()
                    let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
                    return [AVAudioPCMBuffer.mono(samples: [0.1, 0.2, 0.3, 0.4, 0.5], format: format)!]
                })
            }
        }
    }

    private func makeSpeaker(pocket: PocketRecorder = PocketRecorder(), system: SystemRecorder = SystemRecorder())
        -> (EffectiveSpeaker, PocketRecorder, SystemRecorder, LockedBox<[SpeakerStatus]>) {
        let statuses = LockedBox<[SpeakerStatus]>([])
        let speaker = EffectiveSpeaker(makePocketTTS: pocket.factory(), makeSystem: system.factory(),
                                       onStatusChanged: { status in statuses.mutate { $0.append(status) } })
        return (speaker, pocket, system, statuses)
    }

    func testSelectionRuleFollowsR11() {
        var settings = Settings()
        XCTAssertEqual(SpeakerSelection.choose(settings: settings, pocketTTSReady: true), .pocketTTS(voice: "alba", fallbackIdentifier: nil))
        XCTAssertEqual(SpeakerSelection.choose(settings: settings, pocketTTSReady: false), .systemNotDownloaded(identifier: nil))
        settings.voice = "system"
        settings.systemVoiceIdentifier = "com.apple.voice.compact.en-US.Samantha"
        XCTAssertEqual(SpeakerSelection.choose(settings: settings, pocketTTSReady: true), .system(identifier: "com.apple.voice.compact.en-US.Samantha"))
        settings.voice = "cosette"
        XCTAssertEqual(SpeakerSelection.choose(settings: settings, pocketTTSReady: true), .pocketTTS(voice: "cosette", fallbackIdentifier: "com.apple.voice.compact.en-US.Samantha"))
    }

    /// M8, §8.2: pocket-tts is English-only, so the second direction never reaches it however healthy it is.
    func testANonEnglishPhraseGoesToTheSystemVoiceEvenWithPocketTTSLoaded() async throws {
        let (speaker, pocket, system, _) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        _ = try await speaker.synthesize("Good morning.")
        XCTAssertEqual(pocket.syntheses, 1, "English is pocket-tts's")
        _ = try await speaker.synthesize("Buenos días.", language: "es")
        XCTAssertEqual(pocket.syntheses, 1, "Spanish never reached pocket-tts")
        XCTAssertEqual(system.texts, ["Buenos días."])
        let status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "alba"), "using the system voice for one phrase is not a fallback")
    }

    func testAnEnglishRegionPhraseStillUsesPocketTTS() async throws {
        let (speaker, pocket, _, _) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        _ = try await speaker.synthesize("Good morning.", language: "en-GB")
        XCTAssertEqual(pocket.syntheses, 1)
    }

    func testPrefersPocketTTSWhenSelectedAndLoadable() async throws {
        let (speaker, pocket, system, statuses) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "javert", fallbackIdentifier: nil))
        let status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "javert"))
        XCTAssertEqual(status.text, "javert (pocket-tts)")
        let clip = try await speaker.synthesize("Hello")
        XCTAssertEqual(clip.sampleRate, 24_000)
        XCTAssertEqual(clip.samples.count, 2_400)
        XCTAssertEqual(pocket.createdVoices, ["javert"])
        XCTAssertEqual(pocket.initializes, 1)
        XCTAssertEqual(system.texts, [], "the system voice is not used")
        XCTAssertEqual(statuses.value, [.pocketTTS(voice: "javert")])
        XCTAssertEqual(speaker.sampleRate, 24_000)
    }

    func testLoadFailureFallsBackToSystemWithStatus() async throws {
        let pocket = PocketRecorder()
        pocket.failInitialize = true
        let (speaker, _, system, statuses) = makeSpeaker(pocket: pocket)
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: "com.example.voice"))
        let status = await speaker.status
        XCTAssertEqual(status, .fallback(.loadFailed("Speech synthesis failed: no ANE")))
        XCTAssertEqual(status.text, SpeakerStatus.failedToLoadText)
        XCTAssertTrue(status.isFallback)
        let clip = try await speaker.synthesize("Hello")
        XCTAssertEqual(clip.sampleRate, 22_050)
        XCTAssertEqual(clip.samples.count, 5)
        XCTAssertEqual(system.identifiers, ["com.example.voice"], "the fallback uses the selected system voice")
        XCTAssertEqual(system.texts, ["Hello"])
        XCTAssertEqual(statuses.value, [.fallback(.loadFailed("Speech synthesis failed: no ANE"))])
    }

    func testSynthesisFailureFallsBackForTheRestOfTheSession() async throws {
        let pocket = PocketRecorder()
        pocket.failSynthesisOnce = true
        let (speaker, _, system, statuses) = makeSpeaker(pocket: pocket)
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        let first = try await speaker.synthesize("One")
        XCTAssertEqual(first.sampleRate, 22_050, "the failed phrase is spoken by the system voice")
        let second = try await speaker.synthesize("Two")
        XCTAssertEqual(second.sampleRate, 22_050)
        XCTAssertEqual(pocket.syntheses, 1, "pocket-tts is not retried within the session")
        XCTAssertEqual(system.texts, ["One", "Two"])
        let status = await speaker.status
        XCTAssertEqual(status, .fallback(.synthesisFailed("Speech synthesis failed: decoder")))
        XCTAssertEqual(status.text, SpeakerStatus.failedToSpeakText)
        XCTAssertEqual(statuses.value, [.pocketTTS(voice: "alba"), .fallback(.synthesisFailed("Speech synthesis failed: decoder"))])
    }

    func testNextSessionRetriesPocketTTSAfterAFallback() async throws {
        let pocket = PocketRecorder()
        pocket.failSynthesisOnce = true
        let (speaker, _, _, _) = makeSpeaker(pocket: pocket)
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        _ = try await speaker.synthesize("One")
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        let status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "alba"))
        let clip = try await speaker.synthesize("Two")
        XCTAssertEqual(clip.sampleRate, 24_000)
        XCTAssertEqual(pocket.createdVoices, ["alba", "alba"], "the dropped speaker is rebuilt")
        XCTAssertEqual(pocket.initializes, 2)
    }

    func testVoiceChangeBetweenSessionsKeepsTheLoadedManager() async throws {
        let (speaker, pocket, _, _) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        await speaker.prepare(.pocketTTS(voice: "azelma", fallbackIdentifier: nil))
        let status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "azelma"))
        XCTAssertEqual(pocket.createdVoices, ["alba"], "setVoice on the loaded speaker, no reload")
        XCTAssertEqual(pocket.initializes, 1)
    }

    func testSystemSelectionsCarryTheirStatus() async throws {
        let (speaker, pocket, system, _) = makeSpeaker()
        await speaker.prepare(.system(identifier: "com.example.voice"))
        var status = await speaker.status
        XCTAssertEqual(status, .systemSelected)
        XCTAssertEqual(status.text, SpeakerStatus.systemText)
        await speaker.prepare(.systemNotDownloaded(identifier: nil))
        status = await speaker.status
        XCTAssertEqual(status, .systemNotDownloaded)
        XCTAssertEqual(status.text, SpeakerStatus.notDownloadedText)
        XCTAssertEqual(SpeakerStatus.notDownloadedText, "System voice — pocket-tts not downloaded")
        let clip = try await speaker.synthesize("Hi")
        XCTAssertEqual(clip.sampleRate, 22_050)
        XCTAssertEqual(system.identifiers, ["com.example.voice", nil])
        XCTAssertEqual(pocket.createdVoices, [], "pocket-tts is never built for a system selection")
    }

    /// `.systemNotDownloaded` means the pocket-tts files are gone or no longer verified — the user deleted the voice
    /// on the Voices screen, or a library bump invalidated the verified load. The loaded manager kept those models
    /// resident (hundreds of MB) for the rest of the app's life, with nothing left to release them but a memory
    /// warning. A selection that says "not installed" drops the loaded speaker; the next pocket-tts selection
    /// rebuilds it from the files that are actually there.
    func testNotDownloadedSelectionDropsTheLoadedPocketTTS() async throws {
        let (speaker, pocket, _, statuses) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        XCTAssertEqual(pocket.initializes, 1)

        await speaker.prepare(.systemNotDownloaded(identifier: nil))
        var status = await speaker.status
        XCTAssertEqual(status, .systemNotDownloaded)
        let clip = try await speaker.synthesize("Hi")
        XCTAssertEqual(clip.sampleRate, 22_050, "the system voice speaks")

        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "alba"))
        XCTAssertEqual(pocket.createdVoices, ["alba", "alba"], "the dropped speaker is rebuilt, not the stale one reused")
        XCTAssertEqual(pocket.initializes, 2)
        XCTAssertEqual(statuses.value, [.pocketTTS(voice: "alba"), .systemNotDownloaded, .pocketTTS(voice: "alba")])
    }

    /// The deliberate opposite: choosing the system voice while pocket-tts stays installed keeps the loaded manager,
    /// so switching back costs no reload (the existing "kept across sessions" rule).
    func testSystemSelectionWithPocketTTSInstalledKeepsTheLoadedManager() async throws {
        let (speaker, pocket, _, _) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        await speaker.prepare(.system(identifier: nil))
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        XCTAssertEqual(pocket.createdVoices, ["alba"])
        XCTAssertEqual(pocket.initializes, 1)
    }

    func testWhitespaceTouchesNeitherEngine() async throws {
        let (speaker, pocket, system, _) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        let clip = try await speaker.synthesize("  \n")
        XCTAssertTrue(clip.isEmpty)
        XCTAssertEqual(pocket.syntheses, 0)
        XCTAssertEqual(system.texts, [])
    }

    func testUnloadPocketTTSSwitchesToSystemUntilTheNextPrepare() async throws {
        let (speaker, pocket, system, statuses) = makeSpeaker()
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        await speaker.unloadPocketTTS()
        var status = await speaker.status
        XCTAssertEqual(status, .fallback(.memoryPressure))
        XCTAssertEqual(status.text, SpeakerStatus.memoryLowText)
        let clip = try await speaker.synthesize("Hi")
        XCTAssertEqual(clip.sampleRate, 22_050)
        XCTAssertEqual(system.texts, ["Hi"])
        await speaker.unloadPocketTTS()   // idempotent
        XCTAssertEqual(statuses.value.count, 2)
        await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil))
        status = await speaker.status
        XCTAssertEqual(status, .pocketTTS(voice: "alba"))
        XCTAssertEqual(pocket.initializes, 2)
    }

    func testStatusTextsGainsAndRecordedVoiceNames() {
        XCTAssertEqual(SpeakerStatus.pocketTTS(voice: "cosette").text, "cosette (pocket-tts)")
        XCTAssertEqual(SpeakerStatus.fallback(.loadFailed("x")).text, "System voice — pocket-tts failed to load")
        XCTAssertEqual(SpeakerStatus.fallback(.synthesisFailed("x")).text, "System voice — pocket-tts failed to speak")
        XCTAssertEqual(SpeakerStatus.fallback(.memoryPressure).text, "System voice — memory low")
        XCTAssertEqual(SpeakerStatus.systemSelected.text, "System voice")
        XCTAssertEqual(SpeakerStatus.pocketTTS(voice: "alba").engineGain, PlayerNodeSink.pocketTTSEngineGain)
        XCTAssertEqual(SpeakerStatus.systemSelected.engineGain, 1)
        XCTAssertEqual(SpeakerStatus.fallback(.memoryPressure).engineGain, 1)
        XCTAssertTrue(SpeakerStatus.pocketTTS(voice: "alba").usesPocketTTS)
        XCTAssertFalse(SpeakerStatus.systemNotDownloaded.usesPocketTTS)
        XCTAssertFalse(SpeakerStatus.systemNotDownloaded.isFallback)
        XCTAssertEqual(SpeakerStatus.pocketTTS(voice: "alba").recordedVoiceName, "alba")
        XCTAssertEqual(SpeakerStatus.fallback(.memoryPressure).recordedVoiceName, "system")
    }

    @MainActor
    func testRelayMirrorsPostedStatusOnTheMainActor() async {
        let relay = SpeakerStatusRelay()
        XCTAssertEqual(relay.status, .systemNotDownloaded)
        XCTAssertEqual(relay.text, SpeakerStatus.notDownloadedText)
        relay.post(.pocketTTS(voice: "alba"))
        await waitUntil("relay updated") { relay.status == .pocketTTS(voice: "alba") }
        XCTAssertEqual(relay.text, "alba (pocket-tts)")
    }

    /// An actor is reentrant: `unloadPocketTTS()` can land while `prepare` is suspended inside `load()`. The
    /// resumed `prepare` must not then claim pocket-tts, or the status line would read "alba (pocket-tts)" and
    /// the player would keep the 0.7 pocket-tts gain while the system voice actually speaks.
    func testMemoryDropDuringTheLoadIsNotOverwrittenByTheResumedPrepare() async throws {
        let pocket = PocketRecorder()
        pocket.holdInitialize = true
        let (speaker, _, system, statuses) = makeSpeaker(pocket: pocket)

        let prepare = Task { await speaker.prepare(.pocketTTS(voice: "alba", fallbackIdentifier: nil)) }
        while pocket.initializes == 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        await speaker.unloadPocketTTS()          // the memory warning lands mid-load
        pocket.holdInitialize = false
        await prepare.value

        let status = await speaker.status
        XCTAssertEqual(status, .fallback(.memoryPressure), "the drop stands; the resumed prepare does not undo it")
        XCTAssertEqual(status.engineGain, 1, "and the player is told the system-voice gain")
        let clip = try await speaker.synthesize("Hi")
        XCTAssertEqual(clip.sampleRate, 22_050, "the system voice speaks, which is what the status says")
        XCTAssertEqual(system.texts, ["Hi"])
        XCTAssertEqual(statuses.value.last, .fallback(.memoryPressure))
    }
}
