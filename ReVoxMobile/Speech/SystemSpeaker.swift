import AVFAudio
import Foundation
import ReVoxCore

/// The system voice as a `Speaker` (§6.6, R7). Clips carry the voice's native rate; the player converts.
actor SystemSpeaker: Speaker {
    typealias Synthesis = @Sendable (AVSpeechUtterance) async throws -> [AVAudioPCMBuffer]

    /// Nominal: `AudioPlayer` ignores the factory rate and converts every clip by `clip.sampleRate`.
    nonisolated let sampleRate: Int = 24_000

    private let voiceIdentifier: String?
    private let synthesizeBuffers: Synthesis
    private let collector: SpeechWriteCollector?

    init(voiceIdentifier: String?, synthesize: Synthesis? = nil) {
        self.voiceIdentifier = voiceIdentifier
        if let synthesize {
            self.synthesizeBuffers = synthesize
            self.collector = nil
        } else {
            let collector = SpeechWriteCollector()
            self.collector = collector
            self.synthesizeBuffers = { utterance in await collector.collect(utterance) }
        }
    }

    static func selectVoice(identifier: String?, voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        if let identifier, let voice = voices.first(where: { $0.identifier == identifier }) {
            return voice
        }
        if let english = AVSpeechSynthesisVoice(language: "en-US") {
            return english
        }
        return voices.first { $0.language.hasPrefix("en") }
    }

    func synthesize(_ text: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 1
        if collector != nil {
            guard let voice = Self.selectVoice(identifier: voiceIdentifier, voices: AVSpeechSynthesisVoice.speechVoices()) else {
                throw SpeakerError.noVoice
            }
            utterance.voice = voice
        }
        let buffers = try await synthesizeBuffers(utterance)
        return try Self.clip(from: buffers)
    }

    /// Float32 mono at the first buffer's rate; other formats are converted per buffer.
    static func clip(from buffers: [AVAudioPCMBuffer]) throws -> AudioClip {
        let nonEmpty = buffers.filter { $0.frameLength > 0 }
        guard let first = nonEmpty.first else {
            return AudioClip(samples: [], sampleRate: 24_000)
        }
        let rate = first.format.sampleRate
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else {
            throw SpeakerError.synthesisFailed("cannot describe the voice format")
        }
        var samples: [Float] = []
        for buffer in nonEmpty {
            if buffer.format.commonFormat == .pcmFormatFloat32, !buffer.format.isInterleaved, buffer.format.channelCount == 1, buffer.format.sampleRate == rate {
                samples.append(contentsOf: buffer.monoFloatSamples)
            } else {
                guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
                    throw SpeakerError.synthesisFailed("unsupported voice buffer format \(buffer.format)")
                }
                samples.append(contentsOf: try PCMConverterDriver.convertToMono(buffer, with: converter))
            }
        }
        return AudioClip(samples: samples, sampleRate: Int(rate))
    }
}
