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
        let speaker = assembly.speaker
        let runtime = assembly.runtime
        let volume = assembly.voiceVolume
        return SamplePlayer(play: { selection, text in
            let mode = await captureMode()
            try await sessionController.configure(for: mode)                     // foreground, before any audio (§6.8)
            let player = AudioPlayer(controller: sessionController, onSpeaking: { _ in }, voiceVolume: volume)
            runtime.register(player)                                             // status gain: 0.7 for pocket-tts, 1.0 for the system voice (§6.7)
            try await player.start()
            await speaker.prepare(selection)                                     // a load failure becomes a fallback status, never an error (§9)
            let clip: AudioClip
            do {
                clip = try await speaker.synthesize(text)
            } catch {
                await player.stop()
                throw error
            }
            await player.enqueue(clip)
            let seconds = Double(clip.samples.count) / Double(max(clip.sampleRate, 1))
            let deadline = ContinuousClock.now + .seconds(seconds + 5)
            while ContinuousClock.now < deadline {
                let speaking = await player.isSpeaking
                if !speaking { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await player.stop()
            if let engine = await sessionController.engineForGraph() {
                engine.detach(player.sink.playerNode)                            // one node per sample; never accumulate
            }
        })
    }
}
