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

    /// The voice for one phrase (M8). English keeps the user's chosen voice; any other language ignores it — that
    /// identifier names an English voice, and an English voice reading French is worse than saying nothing. An
    /// exact `fr-FR` match wins over a `fr-CA` one, and a better-quality voice wins over a compact one.
    static func selectVoice(identifier: String?, language: String, voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        guard !isEnglish(language) else { return selectVoice(identifier: identifier, voices: voices) }
        let base = language.lowercased()
        let matching = voices.filter { $0.language.lowercased() == base || $0.language.lowercased().hasPrefix(base + "-") }
        guard !matching.isEmpty else { return nil }
        return matching.max { lhs, rhs in rank(lhs, base: base) < rank(rhs, base: base) }
    }

    /// Higher is better: exact code first, then voice quality.
    private static func rank(_ voice: AVSpeechSynthesisVoice, base: String) -> Int {
        let exact = voice.language.lowercased() == base ? 10 : 0
        return exact + voice.quality.rawValue
    }

    static func isEnglish(_ language: String) -> Bool {
        let lowered = language.lowercased()
        return lowered == "en" || lowered.hasPrefix("en-") || lowered.hasPrefix("en_")
    }

    /// Whether this iPhone can say anything at all in `language` — read by the two-way picker so the user learns
    /// about a missing voice while choosing, not by hearing silence mid-conversation (§8.2).
    static func hasVoice(for language: String) -> Bool {
        selectVoice(identifier: nil, language: language, voices: AVSpeechSynthesisVoice.speechVoices()) != nil
    }

    func synthesize(_ text: String) async throws -> AudioClip {
        try await synthesize(text, language: "en")
    }

    /// A phrase in `language` (M8). No voice for a non-English language is silence, not an error: the phrase is
    /// already in the transcript, and a thrown error here would stop the run.
    func synthesize(_ text: String, language: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 1
        if collector != nil {
            guard let voice = Self.selectVoice(identifier: voiceIdentifier, language: language,
                                               voices: AVSpeechSynthesisVoice.speechVoices()) else {
                if Self.isEnglish(language) { throw SpeakerError.noVoice }
                return AudioClip(samples: [], sampleRate: sampleRate)
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
            } else if buffer.format.sampleRate == rate, let mono = PCMConverterDriver.averagedMonoSamples(buffer) {
                samples.append(contentsOf: mono)   // channels averaged as Windows does (P7), no rate change
            } else {
                guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
                    throw SpeakerError.synthesisFailed("unsupported voice buffer format \(buffer.format)")
                }
                // A synthesiser buffer is a finished piece of speech: flush rather than hold its tail back.
                samples.append(contentsOf: try PCMConverterDriver.convertToMono(buffer, with: converter, endOfStream: true))
            }
        }
        return AudioClip(samples: samples, sampleRate: Int(rate))
    }
}
