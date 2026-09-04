import Foundation
import ReVoxCore
import UIKit

/// What `PipelineAssembler.build` needs from the speaker side, usable off the main actor.
struct SpeakerBundle: Sendable {
    let speaker: any Speaker
    let playerFactory: AudioPlayerFactory
    /// The effective voice name for the session metadata (§6.10), read when the transcript sink is created.
    let voiceName: @Sendable () -> String
}

/// The effective speaker of R11 / §6.5 for the composition root: one `EffectiveSpeaker` for the app's lifetime, the
/// per-session selection, the player factory carrying the shared `VoiceVolume` and the active engine's gain (§6.7),
/// the status relay for the Live line (§8.2) and the memory-warning unload (§9).
@MainActor
final class SpeakerAssembly {
    /// Lock-guarded state read off the main actor: the latest status (session metadata, player gain) and the player
    /// of the current run, so a status change mid-run (a fallback) updates its gain at once.
    final class Runtime: @unchecked Sendable {
        private let lock = NSLock()
        private var latest: SpeakerStatus = .systemNotDownloaded
        private weak var player: AudioPlayer?

        var status: SpeakerStatus { lock.lock(); defer { lock.unlock() }; return latest }

        func update(_ status: SpeakerStatus) {
            lock.lock(); latest = status; let current = player; lock.unlock()
            current?.setEngineGain(status.engineGain)
        }

        func register(_ newPlayer: AudioPlayer) {
            lock.lock(); player = newPlayer; let status = latest; lock.unlock()
            newPlayer.setEngineGain(status.engineGain)
        }
    }

    nonisolated let speaker: EffectiveSpeaker
    nonisolated let runtime: Runtime
    nonisolated let voiceVolume: VoiceVolume
    let relay: SpeakerStatusRelay
    private let settings: SettingsStore
    private let manager: ModelManager
    private let center: NotificationCenter
    private var memoryWarningToken: NSObjectProtocol?

    init(layout: ModelLayout, settings: SettingsStore, manager: ModelManager, relay: SpeakerStatusRelay, voiceVolume: VoiceVolume,
         center: NotificationCenter = .default) {
        let runtime = Runtime()
        // The same base directory as the download and the verified load, so `initialize()` hits the cache (§6.5).
        let fluidBase = layout.fluidBaseDirectory
        let speaker = EffectiveSpeaker(
            makePocketTTS: { voice in PocketTTSSpeaker.make(voice: voice, fluidBaseDirectory: fluidBase) },
            makeSystem: { identifier in SystemSpeaker(voiceIdentifier: identifier) },
            onStatusChanged: { status in
                runtime.update(status)
                relay.post(status)
            }
        )
        self.speaker = speaker
        self.runtime = runtime
        self.voiceVolume = voiceVolume
        self.relay = relay
        self.settings = settings
        self.manager = manager
        self.center = center
        memoryWarningToken = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { await speaker.unloadPocketTTS() }   // §9: drop pocket-tts, speak with the system voice until the next start
        }
    }

    deinit {
        if let memoryWarningToken {
            center.removeObserver(memoryWarningToken)
        }
    }

    /// R11, evaluated on the main actor before every start: pocket-tts when installed, verified and selected.
    func selection() async -> SpeakerSelection {
        let ready = await manager.isPocketTTSReady()
        return SpeakerSelection.choose(settings: settings.settings, pocketTTSReady: ready)
    }

    nonisolated func bundle(controller: AudioSessionController) -> SpeakerBundle {
        let volume = voiceVolume
        let runtime = self.runtime
        return SpeakerBundle(
            speaker: speaker,
            playerFactory: { _, onSpeaking in
                let player = AudioPlayer(controller: controller, onSpeaking: onSpeaking, voiceVolume: volume)
                runtime.register(player)
                return player
            },
            voiceName: { runtime.status.recordedVoiceName }
        )
    }

    /// Wraps a built pipeline so every `start` prepares the speaker with the session's selection first.
    func wrap(_ pipeline: any LivePipeline) -> any LivePipeline {
        AssembledPipeline(pipeline: pipeline, speaker: speaker, selection: { [weak self] in
            guard let self else { return .system(identifier: nil) }
            return await self.selection()
        })
    }
}
