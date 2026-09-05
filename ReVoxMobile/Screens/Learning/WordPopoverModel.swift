import Foundation
import Observation
import ReVoxCore

/// Resolves one tapped word (M11 §2): transliteration, voice, translator availability (async), dictionary
/// availability (last — the slow call, after the popover already has content), then the meaning the view's
/// translation task delivers. Created on tap by the row, held in the row's `@State`, so it survives the
/// TimelineView ticks and row appends; every field write re-derives `content`.
@MainActor
@Observable
final class WordPopoverModel {
    let word: OriginalWord
    let language: String
    let original: String
    let english: String
    private let lookup: WordLookup

    private(set) var latin: String?
    private(set) var hasVoice = false
    /// nil until resolved: neither the dictionary button nor its note shows before then.
    private(set) var hasDefinition: Bool?
    private(set) var translator: WordTranslatorAvailability = .unavailableOnThisiOS
    private(set) var meaning: WordPopoverContent.MeaningResult = .pending
    private(set) var isLoaded = false

    init(word: OriginalWord, language: String, original: String, english: String, lookup: WordLookup) {
        self.word = word
        self.language = language
        self.original = original
        self.english = english
        self.lookup = lookup
    }

    /// nil = no Say button ever (the hosted default).
    var speaker: WordSpeaker? { lookup.speaker }

    var languageName: String { LanguageCatalog.displayName(language, whenNil: language) }

    var isMicrophoneRunning: Bool { lookup.speaker?.isMicrophoneRunning ?? false }

    var content: WordPopoverContent {
        WordPopoverContent.make(word: word.text, languageName: languageName, latin: latin, hasVoice: hasVoice,
                                isMicrophoneRunning: isMicrophoneRunning, hasDefinition: hasDefinition, translator: translator,
                                meaning: meaning, original: original, range: word.range, english: english)
    }

    /// The word to translate: non-nil only while a translation is wanted and outstanding. The view attaches
    /// `WordTranslation(word:)` to it; the answer makes it nil, which ends the task and releases the session.
    var translationRequest: String? {
        isLoaded && translator == .ready && meaning == .pending ? word.text : nil
    }

    func load() async {
        guard !isLoaded else { return }
        latin = Romanizer.romanize(word.text)
        hasVoice = lookup.hasVoice(language)
        translator = await lookup.translatorAvailability(language)
        if translator != .ready { meaning = .absent }
        isLoaded = true
        hasDefinition = lookup.hasDefinition(word.text)
    }

    /// Trimmed non-empty → the meaning; blank → absent. The first answer stands.
    func receiveMeaning(_ text: String?) {
        guard meaning == .pending else { return }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        meaning = trimmed.isEmpty ? .absent : .text(trimmed)
    }

    @discardableResult
    func speak() -> Bool {
        lookup.speaker?.speak(word.text, language: language) ?? false
    }
}
