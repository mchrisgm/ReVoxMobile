import XCTest
import SwiftUI
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: what the popover says for every source combination, the model that resolves a tapped word, the
/// services it reaches through the environment, and the row's selection hand-off.
@MainActor
final class WordPopoverTests: XCTestCase {
    private let sentence = "¿Dónde está la estación?"
    private let english = "Where is the station?"

    private func lookup(hasVoice: Bool = false, hasDefinition: Bool = false,
                        translator: WordTranslatorAvailability = .unavailableOnThisiOS, speaker: WordSpeaker? = nil) -> WordLookup {
        WordLookup(speaker: speaker, hasVoice: { _ in hasVoice }, hasDefinition: { _ in hasDefinition },
                   translatorAvailability: { _ in translator })
    }

    private func word(_ text: String, in sentence: String, language: String = "es") throws -> OriginalWord {
        try XCTUnwrap(WordSplitter.words(in: sentence, language: language).first { $0.text == text })
    }

    /// "estación" in the Spanish sample sentence, with every input at a sensible default.
    private func content(latin: String? = nil, hasVoice: Bool = true, isMicrophoneRunning: Bool = false, hasDefinition: Bool? = nil,
                         translator: WordTranslatorAvailability = .ready, meaning: WordPopoverContent.MeaningResult = .pending,
                         languageName: String = "Spanish") throws -> WordPopoverContent {
        let station = try word("estación", in: sentence)
        return WordPopoverContent.make(word: station.text, languageName: languageName, latin: latin, hasVoice: hasVoice,
                                       isMicrophoneRunning: isMicrophoneRunning, hasDefinition: hasDefinition, translator: translator,
                                       meaning: meaning, original: sentence, range: station.range, english: english)
    }

    // MARK: The environment value

    /// Every hosted test row gets this: no speaker, no voice, no dictionary, iOS 17 copy — and no framework touched.
    func testTheDefaultLookupIsHonestAndInert() async {
        let lookup = WordLookup.unavailable
        XCTAssertNil(lookup.speaker)
        XCTAssertFalse(lookup.hasVoice("es"))
        XCTAssertFalse(lookup.hasDefinition("estación"))
        let availability = await lookup.translatorAvailability("es")
        XCTAssertEqual(availability, .unavailableOnThisiOS)
    }

    /// The production services: the speaker's cached voice list and the translator probe. The probe never
    /// downloads; the CI simulator runs iOS 18 or later, so the answer is one of the three iOS 18 cases.
    func testTheProductionLookupReadsTheSpeakersVoicesAndTheProbe() async {
        let speaker = WordSpeaker(voices: { AVSpeechSynthesisVoice.speechVoices() }, speak: { _ in }, stop: {})
        let lookup = WordLookup.production(speaker: speaker)
        XCTAssertTrue(lookup.speaker === speaker)
        XCTAssertFalse(lookup.hasVoice("zz"))
        XCTAssertTrue(lookup.hasVoice("en"), "every iPhone speaks English")
        let availability = await lookup.translatorAvailability("es")
        XCTAssertNotEqual(availability, .unavailableOnThisiOS, "the iOS 18 branch answered; which case depends on the simulator's packs")
        let probed = await WordTranslatorProbe.availability(language: "es")
        XCTAssertEqual(probed, availability)
    }

    // MARK: Content

    func testMakeKeepsTheLatinFormOnlyWhenThereIsOne() throws {
        XCTAssertEqual(try content(latin: "ohayou").latin, "ohayou")
        XCTAssertNil(try content(latin: nil).latin)
    }

    func testMakeShowsTheTranslatorsProgressTextAndAbsence() throws {
        XCTAssertEqual(try content(translator: .ready, meaning: .pending).meaning, .loading)
        XCTAssertEqual(try content(translator: .ready, meaning: .text("station")).meaning, .found("station"))
        XCTAssertEqual(try content(translator: .ready, meaning: .absent).meaning, .note(WordPopoverContent.noMeaningText))
        XCTAssertEqual(WordPopoverContent.noMeaningText, "No meaning found for this word.")
    }

    func testMakeExplainsEveryUnavailableTranslator() throws {
        XCTAssertEqual(try content(translator: .unavailableOnThisiOS).meaning, .note(WordPopoverContent.needsIOS18Text))
        XCTAssertEqual(WordPopoverContent.needsIOS18Text, "Meanings for single words need iOS 18. The whole sentence is translated below.")
        XCTAssertEqual(try content(translator: .needsDownload).meaning, .note(WordPopoverContent.needsDownloadText(languageName: "Spanish")))
        XCTAssertEqual(WordPopoverContent.needsDownloadText(languageName: "Spanish"),
                       "To see what a word means, download Spanish for Apple's on-device translator in Settings › Apps › Translate.")
        XCTAssertEqual(try content(translator: .unsupported).meaning, .note(WordPopoverContent.unsupportedText(languageName: "Spanish")))
        XCTAssertEqual(WordPopoverContent.unsupportedText(languageName: "Spanish"),
                       "Apple's on-device translator has no Spanish, so only the whole sentence is translated.")
        // A pending answer is a note, never progress, when no translator will ever answer.
        XCTAssertEqual(try content(translator: .unsupported, meaning: .pending).meaning,
                       .note(WordPopoverContent.unsupportedText(languageName: "Spanish")))
    }

    func testTheSayButtonFollowsTheVoiceAndTheMicrophone() throws {
        let live = try content(hasVoice: true, isMicrophoneRunning: false)
        XCTAssertTrue(live.hasVoice)
        XCTAssertTrue(live.canSpeak)
        XCTAssertNil(live.speakDisabledNote)
        XCTAssertNil(live.voiceNote)
        let listening = try content(hasVoice: true, isMicrophoneRunning: true)
        XCTAssertFalse(listening.canSpeak)
        XCTAssertEqual(listening.speakDisabledNote, WordPopoverContent.microphoneNote)
        XCTAssertEqual(WordPopoverContent.microphoneNote, "Stop listening to hear words through the microphone")
        let silent = try content(hasVoice: false, languageName: "Japanese")
        XCTAssertFalse(silent.canSpeak)
        XCTAssertNil(silent.speakDisabledNote)
        XCTAssertEqual(silent.voiceNote, "This iPhone has no Japanese voice. Add one in Settings › Accessibility › Spoken Content › Voices.")
    }

    /// `hasDefinition` is resolved last and can be slow: neither the button nor the note shows until it is known.
    func testTheDictionaryButtonAndNoteWaitUntilTheAnswerIsKnown() throws {
        let unknown = try content(hasDefinition: nil)
        XCTAssertFalse(unknown.showsDictionaryButton)
        XCTAssertNil(unknown.dictionaryNote)
        let known = try content(hasDefinition: true)
        XCTAssertTrue(known.showsDictionaryButton)
        XCTAssertNil(known.dictionaryNote)
        let missing = try content(hasDefinition: false)
        XCTAssertFalse(missing.showsDictionaryButton)
        XCTAssertEqual(missing.dictionaryNote,
                       "This word is not in this iPhone's dictionaries. You can add a Spanish one in Settings › General › Dictionary.")
    }

    func testTheExampleKeepsTheSentenceAndTheRange() throws {
        let example = try content().example
        XCTAssertEqual(example.original, sentence)
        XCTAssertEqual(String(sentence[example.range]), "estación")
        XCTAssertEqual(example.english, english)
    }

    func testCopyNamesTheWordAndTheLanguage() {
        XCTAssertEqual(WordPopoverContent.pronunciationHeader, "Pronunciation")
        XCTAssertEqual(WordPopoverContent.meaningHeader, "Meaning")
        XCTAssertEqual(WordPopoverContent.exampleHeader, "In this sentence")
        XCTAssertEqual(WordPopoverContent.speakTitle("estación"), "Say estación")
        XCTAssertEqual(WordPopoverContent.speakingTitle, "Speaking…")
        XCTAssertEqual(WordPopoverContent.speakAccessibilityLabel(word: "おはよう", languageName: "Japanese"), "Say おはよう in Japanese")
        XCTAssertEqual(WordPopoverContent.speakHint(languageName: "Spanish"), "Speaks the word with this iPhone's Spanish voice")
        XCTAssertEqual(WordPopoverContent.translatingText, "Translating…")
        XCTAssertEqual(WordPopoverContent.dictionaryButtonTitle, "Look up in the dictionary")
        XCTAssertEqual(WordPopoverContent.dictionaryHint, "Opens this iPhone's dictionary at this word")
        XCTAssertEqual(WordPopoverContent.closeLabel, "Close")
        XCTAssertEqual(WordPopoverContent.lookUpActionTitle("la"), "Look up la")
    }

    // MARK: Model

    func testLoadResolvesEverythingAndAsksForATranslationOnlyWhenReady() async throws {
        let morning = try word("おはよう", in: "おはよう", language: "ja")
        let model = WordPopoverModel(word: morning, language: "ja", original: "おはよう", english: "Good morning.",
                                     lookup: lookup(hasVoice: true, hasDefinition: false, translator: .ready))
        XCTAssertNil(model.translationRequest, "nothing is asked before load")
        XCTAssertNil(model.hasDefinition, "unknown until resolved")
        XCTAssertFalse(model.isLoaded)
        await model.load()
        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.latin, "ohayou")
        XCTAssertTrue(model.hasVoice)
        XCTAssertEqual(model.hasDefinition, false)
        XCTAssertEqual(model.translator, .ready)
        XCTAssertEqual(model.translationRequest, "おはよう")
        XCTAssertEqual(model.languageName, "Japanese")
        let content = model.content
        XCTAssertEqual(content.meaning, .loading)
        XCTAssertEqual(content.latin, "ohayou")
        XCTAssertEqual(content.dictionaryNote, WordPopoverContent.noDictionaryNote(languageName: "Japanese"))
        XCTAssertEqual(content.word, "おはよう")
    }

    func testReceiveMeaningEndsTheRequest() async throws {
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: lookup(translator: .ready))
        await model.load()
        model.receiveMeaning(" station ")
        XCTAssertEqual(model.content.meaning, .found("station"))
        XCTAssertNil(model.translationRequest)
        model.receiveMeaning("platform")
        XCTAssertEqual(model.content.meaning, .found("station"), "the first answer stands")
        let blank = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: lookup(translator: .ready))
        await blank.load()
        blank.receiveMeaning("  ")
        XCTAssertEqual(blank.content.meaning, .note(WordPopoverContent.noMeaningText))
        XCTAssertNil(blank.translationRequest)
    }

    func testIOS17NeverRequestsATranslation() async throws {
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english, lookup: .unavailable)
        await model.load()
        XCTAssertNil(model.translationRequest)
        XCTAssertEqual(model.content.meaning, .note(WordPopoverContent.needsIOS18Text))
        XCTAssertFalse(model.content.canSpeak)
        XCTAssertEqual(model.content.voiceNote, WordPopoverContent.noVoiceNote(languageName: "Spanish"))
        XCTAssertNil(model.speaker)
        XCTAssertFalse(model.speak())
        XCTAssertNil(model.content.latin, "Latin script already")
        XCTAssertEqual(String(model.content.example.original[model.content.example.range]), "estación")
    }

    func testTheModelReadsTheMicrophoneFromTheSpeaker() async throws {
        let recorded = LockedBox<[String]>([])
        let running = LockedBox(false)
        let speaker = WordSpeaker(isMicrophoneRunning: { running.value }, voices: { AVSpeechSynthesisVoice.speechVoices() },
                                  speak: { utterance in recorded.mutate { $0.append(utterance.speechString) } }, stop: {})
        let station = try word("estación", in: sentence)
        let model = WordPopoverModel(word: station, language: "es", original: sentence, english: english,
                                     lookup: lookup(hasVoice: true, speaker: speaker))
        await model.load()
        XCTAssertTrue(model.speaker === speaker)
        XCTAssertTrue(model.content.canSpeak)
        running.mutate { $0 = true }
        XCTAssertFalse(model.content.canSpeak)
        XCTAssertEqual(model.content.speakDisabledNote, WordPopoverContent.microphoneNote)
        XCTAssertFalse(model.speak())
        XCTAssertEqual(recorded.value, [])
        running.mutate { $0 = false }
        guard AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.language.lowercased().hasPrefix("es") }) else {
            throw XCTSkip("this simulator has no Spanish voice installed")
        }
        XCTAssertTrue(model.speak())
        XCTAssertEqual(recorded.value, ["estación"])
    }

    // MARK: Selection (the row's tap and its VoiceOver action)

    /// UIKit refuses to present while a dismissal is in flight: an open popover is closed first and the new
    /// model staged on the next run-loop turn, so `lookup` never points at a word with no popover.
    func testSelectingWhileAnotherPopoverIsOpenClosesItFirst() async throws {
        let holder = LockedBox<WordPopoverModel?>(nil)
        let binding = Binding<WordPopoverModel?>(get: { holder.value }, set: { model in holder.mutate { $0 = model } })
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 4)
        OriginalWordsLine.select(words[0], language: "es", original: sentence, english: english, lookup: .unavailable, into: binding)
        XCTAssertEqual(holder.value?.word, words[0], "nothing open: staged at once")
        OriginalWordsLine.select(words[3], language: "es", original: sentence, english: english, lookup: .unavailable, into: binding)
        XCTAssertNil(holder.value, "the open popover is closed first")
        await waitUntil("the new word staged on the next turn") { holder.value?.word == words[3] }
        XCTAssertEqual(holder.value?.language, "es")
        XCTAssertEqual(holder.value?.english, english)
    }

    func testCustomActionsAreCappedAtTwelveWords() {
        let many = WordSplitter.words(in: (1...20).map { "palabra\($0)" }.joined(separator: " "), language: "es")
        XCTAssertEqual(many.count, 20)
        XCTAssertEqual(OriginalWordsLine.actionWords(many).map(\.id), Array(0..<12))
        XCTAssertEqual(OriginalWordsLine.customActionLimit, 12)
        let few = WordSplitter.words(in: "Buenos días.", language: "es")
        XCTAssertEqual(OriginalWordsLine.actionWords(few), few)
        XCTAssertEqual(OriginalWordsLine.actionWords([]), [])
    }
}
