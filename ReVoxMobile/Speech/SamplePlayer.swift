import AVFAudio
import Foundation
import ReVoxCore

/// "Play sample" on the Voices screen (§8.4): the phrase goes through the same `EffectiveSpeaker`, `AudioPlayer`,
/// gain and session as a translation session, so the user hears exactly what translation will use. Idle only:
/// the view model refuses while the pipeline runs, because this path starts and stops the mode's engine.
struct SamplePlayer: Sendable {
    var play: @Sendable (_ selection: SpeakerSelection, _ text: String) async throws -> Void

    static func production(sessionController: AudioSessionController, assembly: SpeakerAssembly,
                           captureMode: @escaping @MainActor () -> CaptureMode) -> SamplePlayer {
        make(sessionController: sessionController, speaker: assembly.speaker, runtime: assembly.runtime,
             voiceVolume: assembly.voiceVolume, captureMode: captureMode)
    }

    /// The production sequence over its parts, so the tests drive it with a fake speaker and a fake engine.
    static func make(sessionController: AudioSessionController, speaker: EffectiveSpeaker, runtime: SpeakerAssembly.Runtime,
                     voiceVolume: VoiceVolume, captureMode: @escaping @MainActor () -> CaptureMode) -> SamplePlayer {
        SamplePlayer(play: { selection, text in
            let mode = await captureMode()
            try await sessionController.configure(for: mode)                     // foreground, before any audio (§6.8)
            let player = AudioPlayer(controller: sessionController, onSpeaking: { _ in }, voiceVolume: voiceVolume)
            runtime.register(player)                                             // status gain: 0.7 for pocket-tts, 1.0 for the system voice (§6.7)
            // One node per sample, never accumulated: on *every* exit — the engine refusing to start, the
            // synthesis throwing, or the clip having played — the player is stopped and its node detached. A
            // node left behind by a throw is rendered by every later engine start of that mode.
            let release: @Sendable () async -> Void = {
                await player.stop()
                if let engine = await sessionController.engineForGraph(), player.sink.playerNode.engine === engine {
                    engine.detach(player.sink.playerNode)
                }
            }
            do {
                try await player.start()
                await speaker.prepare(selection)                                 // a load failure becomes a fallback status, never an error (§9)
                let clip = try await speaker.synthesize(text)
                await player.enqueue(clip)
                let seconds = Double(clip.samples.count) / Double(max(clip.sampleRate, 1))
                let deadline = ContinuousClock.now + .seconds(seconds + 5)
                while ContinuousClock.now < deadline {
                    let speaking = await player.isSpeaking
                    if !speaking { break }
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            } catch {
                await release()
                throw error
            }
            await release()
        })
    }
}
