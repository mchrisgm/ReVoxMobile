import Foundation
import ReVoxCore

/// The `Speaker` the pipeline holds for the app's lifetime (§6.5, F6, R11): pocket-tts when the session's
/// selection says so and it loads, otherwise the system voice; any pocket-tts failure switches to the system
/// voice for the rest of the session and posts the reason. Never throws on a pocket-tts failure.
actor EffectiveSpeaker: Speaker {
    typealias PocketTTSFactory = @Sendable (_ voice: String) -> PocketTTSSpeaker
    typealias SystemFactory = @Sendable (_ identifier: String?) -> SystemSpeaker
    typealias StatusCallback = @Sendable (SpeakerStatus) -> Void

    /// Nominal (`AudioPlayer` converts every clip by its own rate); equals pocket-tts's 24 kHz.
    nonisolated let sampleRate: Int = PocketTTSSpeaker.sampleRateHz

    private let makePocketTTS: PocketTTSFactory
    private let makeSystem: SystemFactory
    private let onStatusChanged: StatusCallback
    private var pocketTTS: PocketTTSSpeaker?
    /// Built on the first `prepare` (or on demand); `nil` until then so the factory is never called idly.
    private var system: SystemSpeaker?
    private(set) var status: SpeakerStatus = .systemNotDownloaded

    init(makePocketTTS: @escaping PocketTTSFactory, makeSystem: @escaping SystemFactory, onStatusChanged: @escaping StatusCallback = { _ in }) {
        self.makePocketTTS = makePocketTTS
        self.makeSystem = makeSystem
        self.onStatusChanged = onStatusChanged
    }

    /// Called before every `pipeline.start` with the session's selection. A loaded pocket-tts speaker is kept
    /// across sessions (its voice updated through `setVoice`); a dropped one is rebuilt, so a fallback is retried
    /// on the next session. A load failure is a fallback with `.loadFailed`, never an error (§9).
    func prepare(_ selection: SpeakerSelection) async {
        switch selection {
        case .system(let identifier):
            system = makeSystem(identifier)
            setStatus(.systemSelected)
        case .systemNotDownloaded(let identifier):
            system = makeSystem(identifier)
            // "Not downloaded" is also "deleted" and "no longer verified": the files a loaded manager was built
            // from are gone or untrusted, so it is dropped here and rebuilt by the next pocket-tts selection.
            // Keeping it would hold the models resident (§6.5, hundreds of MB) until a memory warning, which
            // is exactly what a user who just deleted the voice expects not to happen.
            if pocketTTS != nil {
                pocketTTS = nil
                Self.logDrop("after the voice was removed")
            }
            setStatus(.systemNotDownloaded)
        case .pocketTTS(let voice, let fallbackIdentifier):
            system = makeSystem(fallbackIdentifier)
            let speaker: PocketTTSSpeaker
            if let existing = pocketTTS {
                speaker = existing
                if await existing.voice != voice {
                    await existing.setVoice(voice)
                }
            } else {
                speaker = makePocketTTS(voice)
                pocketTTS = speaker
            }
            do {
                try await speaker.load()
                // The actor is reentrant, so a memory warning can drop the speaker while this load is awaited.
                // Claim pocket-tts only if the speaker just loaded is still the installed one; otherwise the
                // fallback that dropped it stands, and the status line and the player gain stay truthful.
                if pocketTTS === speaker {
                    setStatus(.pocketTTS(voice: voice))
                }
            } catch {
                pocketTTS = nil   // dropped so ARC can release the models (§6.5)
                Self.logDrop("after load failure")
                setStatus(.fallback(.loadFailed(String(describing: error))))
            }
        }
    }

    func synthesize(_ text: String) async throws -> AudioClip {
        try await synthesize(text, language: "en")
    }

    /// pocket-tts speaks English only (§6.5), so a phrase in any other language goes straight to the system voice
    /// with a voice for that language — and to silence when this iPhone has none (M8, §8.2).
    func synthesize(_ text: String, language: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        guard SystemSpeaker.isEnglish(language) else {
            return try await systemSpeaker().synthesize(text, language: language)
        }
        if let pocketTTS, status.usesPocketTTS {
            do {
                return try await pocketTTS.synthesize(text)
            } catch {
                self.pocketTTS = nil
                Self.logDrop("after synthesis failure")
                setStatus(.fallback(.synthesisFailed(String(describing: error))))
            }
        }
        return try await systemSpeaker().synthesize(text)
    }

    /// The session's system voice, built on demand when `prepare` has not run yet.
    private func systemSpeaker() -> SystemSpeaker {
        if let system { return system }
        let built = makeSystem(nil)
        system = built
        return built
    }

    /// Memory pressure (§9): drop the manager; the system voice speaks until the next `prepare`.
    func unloadPocketTTS() {
        guard pocketTTS != nil else { return }
        pocketTTS = nil
        Self.logDrop("for memory pressure")
        setStatus(.fallback(.memoryPressure))
    }

    private func setStatus(_ new: SpeakerStatus) {
        guard new != status else { return }
        status = new
        onStatusChanged(new)
    }

    /// §13 Q7: whether dropping the manager actually gives the memory back is an open question, so the reading is taken
    /// twice — at the drop and five seconds later, by which time any deferred release has happened.
    private static func logDrop(_ reason: String) {
        MemoryMeter.log("pocket-tts dropped \(reason)")
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            MemoryMeter.log("pocket-tts dropped \(reason), 5 s later")
        }
    }
}
