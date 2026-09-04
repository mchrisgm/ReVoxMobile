import AVFAudio
import Foundation
import os
import ReVoxCore

/// `PlaybackSink` over one `AVAudioPlayerNode` at 24 kHz mono (§6.7). Never calls `play()`: the node is
/// started by `AudioSessionController.guardedPlay()` and re-started the same way after `stop()`.
final class PlayerNodeSink: PlaybackSink, @unchecked Sendable {
    static let nodeSampleRate: Double = 24_000
    /// Fixed gain for pocket-tts's un-normalised samples (§6.7; ASSUMED starting value, calibrated on device
    /// against the system voice at the same voice volume). System-voice clips use 1.0.
    static let pocketTTSEngineGain: Float = 0.7
    private static let measurementLogger = Logger(subsystem: "revox", category: "measurements")

    let playerNode = AVAudioPlayerNode()
    let format = AVAudioFormat(standardFormatWithSampleRate: PlayerNodeSink.nodeSampleRate, channels: 1)!

    private let lock = NSLock()
    private var converters: [Int: AVAudioConverter] = [:]
    let voiceVolume: VoiceVolume
    private var engineGain: Float = 1
    private var scheduledFrameLength: AVAudioFrameCount = 0
    private let onStopped: @Sendable () -> Void
    private let completionQueue = DispatchQueue(label: "revox.playback.completion")

    init(onStopped: @escaping @Sendable () -> Void, voiceVolume: VoiceVolume = VoiceVolume()) {
        self.onStopped = onStopped
        self.voiceVolume = voiceVolume
    }

    func attach(to engine: AVAudioEngine) {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)   // mixer → output format untouched
    }

    // MARK: Gain (§6.7: voiceVolume × engineGain, clamped to ±1 in the float domain)

    func setVoiceVolume(_ volume: Float) {
        voiceVolume.current = volume
    }

    /// 1.0 for system-voice clips, `pocketTTSEngineGain` while pocket-tts speaks (§6.7).
    func setEngineGain(_ gain: Float) {
        lock.lock(); engineGain = max(gain, 0); lock.unlock()
    }

    var gain: Float {
        lock.lock(); defer { lock.unlock() }
        return voiceVolume.current * engineGain
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
        Self.logLevel(of: scaled, gain: currentGain)
        return AVAudioPCMBuffer.mono(samples: scaled, format: format)
    }

    /// Gain calibration (§6.7, §13 Q6): RMS of the scaled clip in dBFS, one line per clip. The record compares a
    /// pocket-tts sample with a system-voice sample at the same voice volume.
    private static func logLevel(of samples: [Float], gain: Float) {
        guard !samples.isEmpty else { return }
        let meanSquare = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        let dbfs = 10 * log10(max(meanSquare, 1e-12))
        measurementLogger.info("playback clip rms_dbfs=\(dbfs, privacy: .public) gain=\(gain, privacy: .public) frames=\(samples.count, privacy: .public)")
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
