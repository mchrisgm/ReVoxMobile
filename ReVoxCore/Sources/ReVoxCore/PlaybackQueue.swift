import Foundation

/// Mono Float32 audio at `sampleRate`.
public struct AudioClip: Sendable, Equatable {
    public var samples: [Float]
    public var sampleRate: Int

    public init(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var isEmpty: Bool { samples.isEmpty }
}

public typealias SpeakingCallback = @Sendable (Bool) -> Void

/// The engine half of playback; the app implements it over an `AVAudioPlayerNode`.
public protocol PlaybackSink: Sendable {
    /// Schedules the clip; calls `completion` once the audio has been played back or the sink was stopped.
    func schedule(_ clip: AudioClip, completion: @escaping @Sendable () -> Void)
    /// Stops the current clip immediately (used when muted mid-clip and on stop).
    func stopCurrent()
}

/// Port of `revox/pipeline/playback.py:Player` minus the output stream: queued playback, mute discards (never pauses),
/// speaking-state edges only on change. The Windows 0.25 s slicing is not needed (deviation W7).
public actor PlaybackQueue {
    private let sink: any PlaybackSink
    private let onSpeakingChanged: SpeakingCallback
    public private(set) var isSpeaking = false
    public private(set) var isMuted = false
    private var outstanding = 0
    /// Bumped whenever outstanding clips are discarded so late completions of discarded clips are ignored.
    private var generation: UInt64 = 0
    private var stopped = false

    public init(sink: any PlaybackSink, onSpeakingChanged: @escaping SpeakingCallback) {
        self.sink = sink
        self.onSpeakingChanged = onSpeakingChanged
    }

    /// Empty clips are ignored; muted clips are discarded without touching the sink.
    public func enqueue(_ clip: AudioClip) {
        guard !clip.isEmpty, !isMuted, !stopped else { return }
        outstanding += 1
        setSpeaking(true)
        let scheduledGeneration = generation
        sink.schedule(clip) { [weak self] in
            guard let self else { return }
            Task { await self.clipCompleted(generation: scheduledGeneration) }
        }
    }

    /// true: discard the queue and stop the current clip; speaking → false.
    public func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted {
            discardOutstanding()
        }
    }

    public func clear() {
        discardOutstanding()
    }

    /// Idempotent; stops the sink and reports speaking → false.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        generation += 1
        outstanding = 0
        sink.stopCurrent()
        setSpeaking(false)
    }

    private func clipCompleted(generation completedGeneration: UInt64) {
        guard completedGeneration == generation, outstanding > 0 else { return }
        outstanding -= 1
        if outstanding == 0 {
            setSpeaking(false)
        }
    }

    private func discardOutstanding() {
        generation += 1
        if outstanding > 0 {
            outstanding = 0
            sink.stopCurrent()
        }
        setSpeaking(false)
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeakingChanged(speaking)
    }
}
