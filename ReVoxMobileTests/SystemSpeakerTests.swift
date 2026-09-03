import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class SystemSpeakerTests: XCTestCase {
    private func buffer(samples: [Float], rate: Double) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        return try XCTUnwrap(AVAudioPCMBuffer.mono(samples: samples, format: format))
    }

    func testWhitespaceReturnsEmptyClipWithoutEngine() async throws {
        let calls = LockedBox(0)
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { _ in calls.mutate { $0 += 1 }; return [] })
        let clip = try await speaker.synthesize("   \n\t")
        XCTAssertTrue(clip.isEmpty)
        XCTAssertEqual(calls.value, 0)
        let empty = try await speaker.synthesize("")
        XCTAssertTrue(empty.isEmpty)
    }

    func testBuffersAreConcatenatedIntoOneClipAtTheVoiceRate() async throws {
        let first = try buffer(samples: [0.1, 0.2, 0.3], rate: 22_050)
        let second = try buffer(samples: [0.4, 0.5], rate: 22_050)
        let terminator = try buffer(samples: [], rate: 22_050)
        let texts = LockedBox<[String]>([])
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { utterance in
            texts.mutate { $0.append(utterance.speechString) }
            return [first, second, terminator]
        })
        let clip = try await speaker.synthesize("Hello there")
        XCTAssertEqual(clip.sampleRate, 22_050)
        XCTAssertEqual(clip.samples.count, 5)
        XCTAssertEqual(clip.samples[0], 0.1, accuracy: 0.0001)
        XCTAssertEqual(clip.samples[4], 0.5, accuracy: 0.0001)
        XCTAssertEqual(texts.value, ["Hello there"])
        XCTAssertEqual(speaker.sampleRate, 24_000, "nominal; the player converts every clip by its own rate")
    }

    func testStereoOrIntegerBuffersAreConvertedToMonoFloat() throws {
        let stereo = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 4))
        buffer.frameLength = 4
        for i in 0..<4 {
            buffer.floatChannelData![0][i] = 0.2
            buffer.floatChannelData![1][i] = 0.4
        }
        let clip = try SystemSpeaker.clip(from: [buffer])
        XCTAssertEqual(clip.samples.count, 4)
        XCTAssertEqual(clip.samples[0], 0.3, accuracy: 0.01, "channels averaged")

        let int16 = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let intBuffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: int16, frameCapacity: 2))
        intBuffer.frameLength = 2
        intBuffer.int16ChannelData![0][0] = 16_384
        intBuffer.int16ChannelData![0][1] = -16_384
        let intClip = try SystemSpeaker.clip(from: [intBuffer])
        XCTAssertEqual(intClip.sampleRate, 16_000)
        XCTAssertEqual(intClip.samples[0], 0.5, accuracy: 0.01)
        XCTAssertEqual(intClip.samples[1], -0.5, accuracy: 0.01)
    }

    func testNoBuffersIsAnEmptyClipNotAnError() async throws {
        let speaker = SystemSpeaker(voiceIdentifier: nil, synthesize: { _ in [] })
        let clip = try await speaker.synthesize("Hi")
        XCTAssertTrue(clip.isEmpty)
    }

    func testVoiceSelectionPrefersTheIdentifierThenEnglish() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let english = voices.first { $0.language.hasPrefix("en") }
        if let english {
            XCTAssertEqual(SystemSpeaker.selectVoice(identifier: english.identifier, voices: voices)?.identifier, english.identifier)
            XCTAssertNotNil(SystemSpeaker.selectVoice(identifier: "com.example.missing", voices: voices), "falls back to en-US")
        }
        // The second branch of §6.6 is `AVSpeechSynthesisVoice(language: "en-US")`, which does not consult the
        // list it was handed, so an empty list still resolves to the en-US voice every simulator and device has.
        XCTAssertNotNil(SystemSpeaker.selectVoice(identifier: "com.example.missing", voices: []),
                        "the en-US fallback does not depend on the passed list")
    }

    func testTimeoutFormula() {
        XCTAssertEqual(SpeechWriteCollector.timeout(forCharacterCount: 10), 3, accuracy: 0.0001)     // max(3, 4 × 10/15 = 2.67)
        XCTAssertEqual(SpeechWriteCollector.timeout(forCharacterCount: 150), 40, accuracy: 0.0001)   // 4 × 150/15
    }
}
