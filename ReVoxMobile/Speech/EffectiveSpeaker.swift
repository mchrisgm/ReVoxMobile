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
                setStatus(.pocketTTS(voice: voice))
            } catch {
                pocketTTS = nil   // dropped so ARC can release the models (§6.5)
                setStatus(.fallback(.loadFailed(String(describing: error))))
            }
        }
    }

    func synthesize(_ text: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        if let pocketTTS, status.usesPocketTTS {
            do {
                return try await pocketTTS.synthesize(text)
            } catch {
                self.pocketTTS = nil
                setStatus(.fallback(.synthesisFailed(String(describing: error))))
            }
        }
        let systemSpeaker: SystemSpeaker
        if let system {
            systemSpeaker = system
        } else {
            systemSpeaker = makeSystem(nil)
            system = systemSpeaker
        }
        return try await systemSpeaker.synthesize(text)
    }

    /// Memory pressure (§9): drop the manager; the system voice speaks until the next `prepare`.
    func unloadPocketTTS() {
        guard pocketTTS != nil else { return }
        pocketTTS = nil
        setStatus(.fallback(.memoryPressure))
    }

    private func setStatus(_ new: SpeakerStatus) {
        guard new != status else { return }
        status = new
        onStatusChanged(new)
    }
}
