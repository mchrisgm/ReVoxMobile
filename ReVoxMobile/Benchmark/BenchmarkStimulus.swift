import AVFAudio
import Foundation
import ReVoxCore

/// The sentence the benchmark hears, as 16 kHz mono Float32 (M11 §5).
struct BenchmarkStimulus: Sendable, Equatable {
    let sentence: BenchmarkSentence
    let samples: [Float]

    var audioSeconds: Double { Double(samples.count) / Double(AudioFormat.pipelineSampleRate) }
}

/// Benchmark failures the screen shows (M11 §5).
enum BenchmarkError: Error, Equatable, CustomStringConvertible {
    /// The iPhone's voice produced no audio, even for the English sentence.
    case noSpeech
    /// A second run, a download or a delete while a benchmark runs.
    case busy
    /// Live Start while a benchmark runs (the gated pipeline supplier in `AppEnvironment`).
    case liveBlocked
    /// Every model was skipped; the reason of the first.
    case nothingMeasured(String)

    var description: String {
        switch self {
        case .noSpeech:
            return "The iPhone's voice produced no audio for the sentence. Check Settings › Accessibility › Spoken Content › Voices and try again."
        case .busy:
            return "Finish or cancel the benchmark first"
        case .liveBlocked:
            return "Finish or cancel the benchmark in Settings › Models before starting"
        case .nothingMeasured(let reason):
            return "Nothing measured: \(reason)"
        }
    }
}

/// Speaks the sentence silently — `SystemSpeaker` over `SpeechWriteCollector` in production, any `Speaker` in
/// tests — and converts the clip to the pipeline rate through the production converter. The synthesiser seam is
/// the `Speaker` protocol itself; `hasVoice` picks the sentence.
struct BenchmarkStimulusFactory: Sendable {
    let speaker: any Speaker
    let hasVoice: @Sendable (String) -> Bool

    init(speaker: any Speaker, hasVoice: @escaping @Sendable (String) -> Bool) {
        self.speaker = speaker
        self.hasVoice = hasVoice
    }

    /// No playback and no audio session: `SystemSpeaker(voiceIdentifier: nil)` writes buffers through its collector.
    static func production() -> BenchmarkStimulusFactory {
        BenchmarkStimulusFactory(speaker: SystemSpeaker(voiceIdentifier: nil), hasVoice: { SystemSpeaker.hasVoice(for: $0) })
    }

    /// The first sentence the iPhone can say. A non-English voice that returns silence (what `SystemSpeaker` does
    /// for a language it cannot voice) falls back to English once; silence for English too is `noSpeech`.
    func make() async throws -> BenchmarkStimulus {
        let sentence = BenchmarkSentences.first(spokenBy: hasVoice)
        if let stimulus = try await stimulus(for: sentence) { return stimulus }
        if sentence != BenchmarkSentences.english, let fallback = try await stimulus(for: BenchmarkSentences.english) {
            return fallback
        }
        throw BenchmarkError.noSpeech
    }

    private func stimulus(for sentence: BenchmarkSentence) async throws -> BenchmarkStimulus? {
        let clip: AudioClip
        do {
            clip = try await speaker.synthesize(sentence.text, language: sentence.language)
        } catch SpeakerError.noVoice {
            return nil   // English with no English voice at all: the same "no speech" outcome, not the speaker's text
        }
        guard !clip.isEmpty else { return nil }
        return BenchmarkStimulus(sentence: sentence, samples: try Self.samples16k(from: clip))
    }

    /// The production route from a voice clip to the pipeline format: `AVAudioPCMBuffer.mono` at the clip's own
    /// rate (22 050 for compact voices, never the nominal 24 000), `AVAudioConverter`, one flushed conversion.
    static func samples16k(from clip: AudioClip) throws -> [Float] {
        guard clip.sampleRate != AudioFormat.pipelineSampleRate else { return clip.samples }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(clip.sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer.mono(samples: clip.samples, format: format),
              let converter = AVAudioConverter(from: format, to: PCMConverterDriver.pipelineFormat) else {
            throw PCMConversionError.bufferAllocationFailed
        }
        return try PCMConverterDriver.convertToMono(buffer, with: converter, endOfStream: true)
    }
}
