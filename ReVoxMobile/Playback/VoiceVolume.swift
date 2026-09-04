import Foundation

/// The Settings "Voice volume" slider (R11 `voiceVolume`, §8.5) as a lock-guarded box shared by the writer
/// (`SettingsViewModel`) and every `PlayerNodeSink`, which reads it at enqueue time (§6.7). Always 0…1.
final class VoiceVolume: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float

    init(_ initial: Float = 1) {
        value = min(max(initial, 0), 1)
    }

    var current: Float {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = min(max(newValue, 0), 1); lock.unlock() }
    }
}
