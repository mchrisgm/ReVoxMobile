import AVFAudio
import Foundation
import Observation

/// Says one word in its language (M11 §2): the popover's Say button. Its own `AVSpeechSynthesizer` with
/// `usesApplicationAudioSession = false`, so it mixes with whatever is playing, needs no session configuration
/// and never touches the resident mask, the ducking cycle or the pipeline's player. The synthesizer is built on
/// the first word, so a launch (and every test environment) pays nothing for it.
///
/// Silent while a microphone run is going: the word would come out of the speaker, be heard by the microphone,
/// segmented and translated — a feedback row every time. During an Other-apps run the ring carries other apps'
/// audio, not the speaker, so the word is allowed.
@MainActor
@Observable
final class WordSpeaker {
    typealias Speak = @MainActor (AVSpeechUtterance) -> Void
    typealias Stop = @MainActor () -> Void

    private(set) var isSpeaking = false

    private let isMicrophoneRunningNow: @MainActor () -> Bool
    private let loadVoices: @MainActor () -> [AVSpeechSynthesisVoice]
    private let injectedSpeak: Speak?
    private let injectedStop: Stop?
    @ObservationIgnored private var synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var cachedVoices: [AVSpeechSynthesisVoice]?

    /// `speak` and `stop` nil = the real synthesizer; the tests inject recorders. `voices` is read once and kept.
    init(isMicrophoneRunning: @escaping @MainActor () -> Bool = { false },
         voices: @escaping @MainActor () -> [AVSpeechSynthesisVoice] = { AVSpeechSynthesisVoice.speechVoices() },
         speak: Speak? = nil, stop: Stop? = nil) {
        self.isMicrophoneRunningNow = isMicrophoneRunning
        self.loadVoices = voices
        self.injectedSpeak = speak
        self.injectedStop = stop
    }

    var isMicrophoneRunning: Bool { isMicrophoneRunningNow() }

    /// The installed voices, listed once per speaker: the first `speechVoices()` of a launch takes hundreds of
    /// milliseconds, and the popover asks on every tap.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        if let cachedVoices { return cachedVoices }
        let voices = loadVoices()
        cachedVoices = voices
        return voices
    }

    /// Pure: the utterance for one word, or nil when the text is blank, the language is English (an English row
    /// never shows chips, so nothing may ask) or this iPhone has no voice for the language.
    static func utterance(for word: String, language: String, voices: [AVSpeechSynthesisVoice]) -> AVSpeechUtterance? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SystemSpeaker.isEnglish(language) else { return nil }
        guard let voice = SystemSpeaker.selectVoice(identifier: nil, language: language, voices: voices) else { return nil }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.volume = 1
        return utterance
    }

    /// Stops anything in flight first. False, and nothing said, while a microphone run is going or when there is
    /// no utterance for the word.
    @discardableResult
    func speak(_ word: String, language: String) -> Bool {
        guard !isMicrophoneRunning else { return false }
        guard let utterance = Self.utterance(for: word, language: language, voices: availableVoices()) else { return false }
        stop()
        if let injectedSpeak {
            injectedSpeak(utterance)
        } else {
            synthesizerForSpeaking().speak(utterance)
        }
        return true
    }

    func stop() {
        if let injectedStop {
            injectedStop()
        } else {
            synthesizer?.stopSpeaking(at: .immediate)
        }
    }

    /// The delegate's edges, and the test seam for them.
    func noteStarted() { isSpeaking = true }
    func noteFinished() { isSpeaking = false }

    private func synthesizerForSpeaking() -> AVSpeechSynthesizer {
        if let synthesizer { return synthesizer }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.usesApplicationAudioSession = false
        let delegate = Delegate(owner: self)
        synthesizer.delegate = delegate
        self.delegate = delegate
        self.synthesizer = synthesizer
        return synthesizer
    }

    /// Not main-actor isolated (a nested type does not inherit the class's isolation); every edge hops to the owner.
    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        weak var owner: WordSpeaker?

        init(owner: WordSpeaker) {
            self.owner = owner
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteStarted() }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteFinished() }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            let owner = self.owner
            Task { @MainActor in owner?.noteFinished() }
        }
    }
}
