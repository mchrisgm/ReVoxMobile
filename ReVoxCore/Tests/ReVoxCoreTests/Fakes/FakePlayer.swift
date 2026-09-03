import Foundation
@testable import ReVoxCore

/// The Windows `FakePlayer`: records clips, mute and stop; exposes `onSpeaking` so tests fire edges
/// like `players[0].on_speaking(True)`.
actor FakePlayer: AudioPlayer {
    nonisolated let onSpeaking: SpeakingCallback
    nonisolated let startOrder: StartOrderLog?
    private(set) var enqueued: [AudioClip] = []
    private(set) var muted: Bool?
    private(set) var started = false
    private(set) var stopped = false

    init(onSpeaking: @escaping SpeakingCallback, startOrder: StartOrderLog? = nil) {
        self.onSpeaking = onSpeaking
        self.startOrder = startOrder
    }

    func start() async throws {
        startOrder?.record("player")
        started = true
    }

    func enqueue(_ clip: AudioClip) async {
        enqueued.append(clip)
    }

    func setMuted(_ muted: Bool) async {
        self.muted = muted
    }

    func clear() async {
        enqueued.removeAll()
    }

    func stop() async {
        stopped = true
    }

    var isSpeaking: Bool {
        get async { false }
    }
}
