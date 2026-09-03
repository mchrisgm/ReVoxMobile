import Foundation
@testable import ReVoxCore

/// Records scheduled clips and completes them on demand; `stopCurrent()` fires the pending completions
/// (as `AVAudioPlayerNode.stop()` does). Every stored property is guarded by one `NSLock`.
final class FakePlaybackSink: PlaybackSink, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledClips: [AudioClip] = []
    private var completions: [@Sendable () -> Void] = []
    private var orphaned: [@Sendable () -> Void] = []
    private var stopCalls = 0
    private var deferring = false

    var scheduled: [AudioClip] {
        lock.lock(); defer { lock.unlock() }
        return scheduledClips
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }
        return stopCalls
    }

    var stopped: Bool { stopCount > 0 }

    /// When true, `stopCurrent()` sets the pending completions aside instead of firing them, so a test can
    /// deliver a stale completion later — the ordering a real `AVAudioPlayerNode` produces when a completion
    /// arrives on the audio thread after a new clip has already been scheduled.
    var deferCompletions: Bool {
        get { lock.lock(); defer { lock.unlock() }; return deferring }
        set { lock.lock(); defer { lock.unlock() }; deferring = newValue }
    }

    func schedule(_ clip: AudioClip, completion: @escaping @Sendable () -> Void) {
        lock.lock()
        scheduledClips.append(clip)
        completions.append(completion)
        lock.unlock()
    }

    func stopCurrent() {
        lock.lock()
        stopCalls += 1
        let pending = completions
        completions.removeAll()
        let holdBack = deferring
        if holdBack {
            orphaned.append(contentsOf: pending)
        }
        lock.unlock()
        guard !holdBack else { return }
        for completion in pending {
            completion()
        }
    }

    /// Completes the oldest outstanding clip.
    func completeNext() {
        lock.lock()
        let completion = completions.isEmpty ? nil : completions.removeFirst()
        lock.unlock()
        completion?()
    }

    /// Fires and clears the completions held back by `deferCompletions`.
    func fireOrphaned() {
        lock.lock()
        let pending = orphaned
        orphaned.removeAll()
        lock.unlock()
        for completion in pending {
            completion()
        }
    }
}
