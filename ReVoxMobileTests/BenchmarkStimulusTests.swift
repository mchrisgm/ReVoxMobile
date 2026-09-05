import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// M11 §5: the sentence choice, the English fallback and the clip → 16 kHz step, without a real voice.
final class BenchmarkStimulusTests: XCTestCase {
    private func tone(seconds: Double, rate: Int) -> [Float] {
        (0 ..< Int(seconds * Double(rate))).map { Float(sin(Double($0) * 2 * .pi * 440 / Double(rate))) * 0.5 }
    }

    private func buffer(_ samples: [Float], rate: Int) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 1))
        return try XCTUnwrap(AVAudioPCMBuffer.mono(samples: samples, format: format))
    }

    func testClipsAtTheCommonVoiceRatesBecomeSixteenKilohertz() throws {
        for rate in [22_050, 24_000, 48_000] {
            let samples = try BenchmarkStimulusFactory.samples16k(from: AudioClip(samples: tone(seconds: 1, rate: rate), sampleRate: rate))
            XCTAssertLessThanOrEqual(abs(samples.count - 16_000), 16, "\(rate) Hz → 16 kHz within ±16 samples")
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.1, "not silent at \(rate) Hz")
        }
    }

    func testSixteenKilohertzPassesThrough() throws {
        let samples = tone(seconds: 0.5, rate: 16_000)
        XCTAssertEqual(try BenchmarkStimulusFactory.samples16k(from: AudioClip(samples: samples, sampleRate: 16_000)), samples)
        let stimulus = BenchmarkStimulus(sentence: BenchmarkSentences.spanish, samples: samples)
        XCTAssertEqual(stimulus.audioSeconds, 0.5)
    }

    func testFactoryFallsBackToEnglishWhenTheiPhoneHasNoPreferredVoice() async throws {
        let voice = try buffer(tone(seconds: 1, rate: 22_050), rate: 22_050)
        let spoken = LockedBox<[String]>([])
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { utterance in
            spoken.mutate { $0.append(utterance.speechString) }
            return [voice]
        })
        let factory = BenchmarkStimulusFactory(speaker: speaker, hasVoice: { _ in false })
        let stimulus = try await factory.make()
        XCTAssertEqual(stimulus.sentence, BenchmarkSentences.english)
        XCTAssertEqual(spoken.value, [BenchmarkSentences.english.text])
        XCTAssertLessThanOrEqual(abs(stimulus.samples.count - 16_000), 16)
    }

    func testFactoryFallsBackToEnglishWhenTheClipIsEmpty() async throws {
        let voice = try buffer(tone(seconds: 1, rate: 24_000), rate: 24_000)
        let spoken = LockedBox<[String]>([])
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { utterance in
            spoken.mutate { $0.append(utterance.speechString) }
            return utterance.speechString == BenchmarkSentences.spanish.text ? [] : [voice]   // silence for Spanish
        })
        let factory = BenchmarkStimulusFactory(speaker: speaker, hasVoice: { _ in true })
        let stimulus = try await factory.make()
        XCTAssertEqual(stimulus.sentence, BenchmarkSentences.english)
        XCTAssertEqual(spoken.value, [BenchmarkSentences.spanish.text, BenchmarkSentences.english.text])
    }

    func testFactoryThrowsNoSpeechWhenEvenEnglishIsSilent() async throws {
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { _ in [] })
        let factory = BenchmarkStimulusFactory(speaker: speaker, hasVoice: { $0 == "es" })
        do {
            _ = try await factory.make()
            XCTFail("expected noSpeech")
        } catch {
            XCTAssertEqual(error as? BenchmarkError, .noSpeech)
        }
        XCTAssertEqual(BenchmarkError.noSpeech.description,
                       "The iPhone's voice produced no audio for the sentence. Check Settings › Accessibility › Spoken Content › Voices and try again.")
    }
}
