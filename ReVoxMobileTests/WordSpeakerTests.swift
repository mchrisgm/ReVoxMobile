import XCTest
import AVFAudio
@testable import ReVoxMobile

/// M11 §2: the popover's Say button. The synthesizer is never built here — `speak` and `stop` are injected
/// recorders — and a language the simulator has no voice for skips, as `SystemSpeakerTests` does.
@MainActor
final class WordSpeakerTests: XCTestCase {
    private final class Recorder {
        var utterances: [String] = []
        var stops = 0
    }

    private func makeSpeaker(microphoneRunning: Bool = false, voices: [AVSpeechSynthesisVoice], recorder: Recorder) -> WordSpeaker {
        WordSpeaker(isMicrophoneRunning: { microphoneRunning }, voices: { voices },
                    speak: { recorder.utterances.append($0.speechString) }, stop: { recorder.stops += 1 })
    }

    private func spanishVoices() throws -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard voices.contains(where: { $0.language.lowercased().hasPrefix("es") }) else {
            throw XCTSkip("this simulator has no Spanish voice installed")
        }
        return voices
    }

    func testAWordWithNoVoiceOrNoTextGivesNoUtterance() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        XCTAssertNil(WordSpeaker.utterance(for: "hola", language: "zz", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "   ", language: "es", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "hola", language: "es", voices: []))
    }

    /// An English row never shows chips (§2), so nothing may ask the speaker for English.
    func testEnglishGivesNoUtterance() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        XCTAssertNil(WordSpeaker.utterance(for: "hello", language: "en", voices: voices))
        XCTAssertNil(WordSpeaker.utterance(for: "hello", language: "en-GB", voices: voices))
    }

    func testAWordInALanguageWithAVoiceIsSaidWithThatVoice() throws {
        let voices = try spanishVoices()
        let utterance = try XCTUnwrap(WordSpeaker.utterance(for: " estación ", language: "es", voices: voices))
        XCTAssertEqual(utterance.speechString, "estación")
        XCTAssertEqual(utterance.voice?.language.lowercased().hasPrefix("es"), true)
        XCTAssertEqual(utterance.volume, 1)
    }

    func testSpeakStopsWhatIsInFlightFirst() throws {
        let voices = try spanishVoices()
        let recorder = Recorder()
        let speaker = makeSpeaker(voices: voices, recorder: recorder)
        XCTAssertTrue(speaker.speak("Buenos", language: "es"))
        XCTAssertTrue(speaker.speak("días", language: "es"))
        XCTAssertEqual(recorder.utterances, ["Buenos", "días"])
        XCTAssertEqual(recorder.stops, 2, "one stop before each word")
        XCTAssertFalse(speaker.speak("hola", language: "zz"))
        XCTAssertEqual(recorder.utterances.count, 2)
        XCTAssertEqual(recorder.stops, 2, "nothing to stop for when there is nothing to say")
    }

    /// A word said through the speaker would be heard by the microphone, segmented and translated back.
    func testAMicrophoneRunDisablesTheSpeaker() throws {
        let voices = try spanishVoices()
        let recorder = Recorder()
        let speaker = makeSpeaker(microphoneRunning: true, voices: voices, recorder: recorder)
        XCTAssertTrue(speaker.isMicrophoneRunning)
        XCTAssertFalse(speaker.speak("Buenos", language: "es"))
        XCTAssertEqual(recorder.utterances, [])
        XCTAssertEqual(recorder.stops, 0)
    }

    /// The first `speechVoices()` of a launch takes hundreds of milliseconds; the list is read once per speaker.
    func testTheVoiceListIsReadOnce() {
        let reads = LockedBox(0)
        let speaker = WordSpeaker(voices: { reads.mutate { $0 += 1 }; return [] }, speak: { _ in }, stop: {})
        _ = speaker.availableVoices()
        _ = speaker.availableVoices()
        XCTAssertFalse(speaker.speak("hola", language: "es"), "no voices, nothing said")
        XCTAssertEqual(reads.value, 1)
    }

    func testSpeakingEdgesFollowTheDelegateHooks() {
        let speaker = WordSpeaker(speak: { _ in }, stop: {})
        XCTAssertFalse(speaker.isSpeaking)
        speaker.noteStarted()
        XCTAssertTrue(speaker.isSpeaking)
        speaker.noteFinished()
        XCTAssertFalse(speaker.isSpeaking)
    }
}
