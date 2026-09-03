import AVFAudio
import Foundation
import ReVoxCore

/// `PlaybackSink` over one `AVAudioPlayerNode` at 24 kHz mono (§6.7). Never calls `play()`: the node is
/// started by `AudioSessionController.guardedPlay()` and re-started the same way after `stop()`.
final class PlayerNodeSink: PlaybackSink, @unchecked Sendable {
    static let nodeSampleRate: Double = 24_000

    let playerNode = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: PlayerNodeSink.nodeSampleRate, channels: 1)!

    private let lock = NSLock()
    private var converters: [Int: AVAudioConverter] = [:]
    private var voiceVolume: Float = 1
    private var engineGain: Float = 1
    private var scheduledFrameLength: AVAudioFrameCount = 0
    private let onStopped: @Sendable () -> Void
    private let completionQueue = DispatchQueue(label: "revox.playback.completion")

    init(onStopped: @escaping @Sendable () -> Void) {
        self.onStopped = onStopped
    }

    func attach(to engine: AVAudioEngine) {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)   // mixer → output format untouched
    }

    // MARK: Gain (§6.7: voiceVolume × engineGain, clamped to ±1 in the float domain)

    func setVoiceVolume(_ volume: Float) {
        lock.lock(); voiceVolume = min(max(volume, 0), 1); lock.unlock()
    }

    /// 1.0 for system-voice clips; M4 sets 0.7 for pocket-tts samples (ASSUMED starting value, calibrated in M4).
    func setEngineGain(_ gain: Float) {
        lock.lock(); engineGain = max(gain, 0); lock.unlock()
    }

    var gain: Float {
        lock.lock(); defer { lock.unlock() }
        return voiceVolume * engineGain
    }

    var lastScheduledFrameLength: AVAudioFrameCount {
        lock.lock(); defer { lock.unlock() }
        return scheduledFrameLength
    }

    // MARK: Buffers

    func makeBuffer(for clip: AudioClip) -> AVAudioPCMBuffer? {
        guard !clip.isEmpty else { return nil }
        let currentGain = gain
        let samples: [Float]
        if clip.sampleRate == Int(Self.nodeSampleRate) {
            samples = clip.samples
        } else {
            guard let converted = try? convert(clip) else { return nil }
            samples = converted
        }
        let scaled = samples.map { min(max($0 * currentGain, -1), 1) }
        return AVAudioPCMBuffer.mono(samples: scaled, format: format)
    }

    private func convert(_ clip: AudioClip) throws -> [Float] {
        guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: Double(clip.sampleRate), channels: 1),
              let input = AVAudioPCMBuffer.mono(samples: clip.samples, format: sourceFormat) else {
            throw PCMConversionError.bufferAllocationFailed
        }
        lock.lock()
        var converter = converters[clip.sampleRate]
        if converter == nil {
            converter = AVAudioConverter(from: sourceFormat, to: format)
            converters[clip.sampleRate] = converter
        }
        lock.unlock()
        guard let converter else { throw PCMConversionError.conversionFailed }
        // A clip is a whole utterance: flush the converter so its tail is played instead of being held
        // back and smeared into the front of the next clip.
        return try PCMConverterDriver.convertToMono(input, with: converter, endOfStream: true)
    }

    // MARK: PlaybackSink

    func schedule(_ clip: AudioClip, completion: @escaping @Sendable () -> Void) {
        guard let buffer = makeBuffer(for: clip) else {
            completion()
            return
        }
        lock.lock(); scheduledFrameLength = buffer.frameLength; lock.unlock()
        let queue = completionQueue
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            queue.async { completion() }   // never on the render callback thread
        }
    }

    /// `playerNode.stop()` only; the controller's guarded call re-plays the node if the engine is running (§6.7).
    func stopCurrent() {
        playerNode.stop()
        onStopped()
    }
}
