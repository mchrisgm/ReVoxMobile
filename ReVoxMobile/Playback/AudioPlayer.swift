import AVFAudio
import Foundation
import ReVoxCore

/// The app's `ReVoxCore.AudioPlayer`: the core `PlaybackQueue` over `PlayerNodeSink`, engine start through the
/// session controller (§6.7). Mute discards, never pauses (W7); held clips play after the next engine start.
final class AudioPlayer: ReVoxCore.AudioPlayer {
    let sink: PlayerNodeSink
    private let queue: PlaybackQueue
    private let controller: AudioSessionController

    init(controller: AudioSessionController, onSpeaking: @escaping SpeakingCallback) {
        self.controller = controller
        let sink = PlayerNodeSink(onStopped: { [controller] in
            Task { await controller.guardedPlay() }
        })
        self.sink = sink
        self.queue = PlaybackQueue(sink: sink, onSpeakingChanged: onSpeaking)
    }

    /// Attaches the node to the mode's engine (once), installs the play hook and starts the engine.
    func start() async throws {
        if let engine = await controller.engineForGraph(), sink.playerNode.engine == nil {
            sink.attach(to: engine)
        }
        let node = sink.playerNode
        // §6.7 verbatim: the hook is `if engine.isRunning { playerNode.play() }`. The guard is on the node's own
        // engine, so `play()` can never raise `required condition is false: _engine->IsRunning()` however the hook
        // is reached (engine start, interruption end, the re-play after `stopCurrent()`).
        await controller.setPlayHook {
            if node.engine?.isRunning == true { node.play() }
        }
        try await controller.startEngine()
    }

    func enqueue(_ clip: AudioClip) async {
        await queue.enqueue(clip)
    }

    func setMuted(_ muted: Bool) async {
        await queue.setMuted(muted)
    }

    func clear() async {
        await queue.clear()
    }

    func stop() async {
        await queue.stop()
        await controller.setPlayHook(nil)
        await controller.stopEngine()
    }

    var isSpeaking: Bool {
        get async { await queue.isSpeaking }
    }

    func setVoiceVolume(_ volume: Float) {
        sink.setVoiceVolume(volume)
    }
}
