import Foundation

/// Everything the word popover shows and every decision about which source is shown (M11 §2), as a value built
/// by one pure function from plain inputs — the seam the tests read and the view renders.
struct WordPopoverContent: Equatable {
    /// What the translator has said so far.
    enum MeaningResult: Equatable, Sendable {
        case pending
        case text(String)
        case absent
    }

    /// What the Meaning section shows.
    enum Meaning: Equatable {
        case loading
        case found(String)
        case note(String)
    }

    struct Example: Equatable {
        let original: String
        let range: Range<String.Index>
        let english: String
    }

    let word: String
    let languageName: String
    /// `Romanizer.romanize(word)`: nil for a word already in Latin letters.
    let latin: String?
    let hasVoice: Bool
    /// The Say button is live: a voice exists and no microphone run is going.
    let canSpeak: Bool
    /// Under a disabled Say button: why it is disabled.
    let speakDisabledNote: String?
    /// In place of the Say button when there is no voice.
    let voiceNote: String?
    let meaning: Meaning
    let showsDictionaryButton: Bool
    let dictionaryNote: String?
    let example: Example

    static func make(word: String, languageName: String, latin: String?, hasVoice: Bool, isMicrophoneRunning: Bool,
                     hasDefinition: Bool?, translator: WordTranslatorAvailability, meaning: MeaningResult,
                     original: String, range: Range<String.Index>, english: String) -> WordPopoverContent {
        let shown: Meaning
        switch translator {
        case .ready:
            switch meaning {
            case .pending: shown = .loading
            case .text(let text): shown = .found(text)
            case .absent: shown = .note(noMeaningText)
            }
        case .unavailableOnThisiOS: shown = .note(needsIOS18Text)
        case .needsDownload: shown = .note(needsDownloadText(languageName: languageName))
        case .unsupported: shown = .note(unsupportedText(languageName: languageName))
        }
        return WordPopoverContent(
            word: word,
            languageName: languageName,
            latin: latin,
            hasVoice: hasVoice,
            canSpeak: hasVoice && !isMicrophoneRunning,
            speakDisabledNote: hasVoice && isMicrophoneRunning ? microphoneNote : nil,
            voiceNote: hasVoice ? nil : noVoiceNote(languageName: languageName),
            meaning: shown,
            showsDictionaryButton: hasDefinition == true,
            dictionaryNote: hasDefinition == false ? noDictionaryNote(languageName: languageName) : nil,
            example: Example(original: original, range: range, english: english)
        )
    }

    // MARK: Copy (M11 §2)

    static let pronunciationHeader = "Pronunciation"
    static let meaningHeader = "Meaning"
    static let exampleHeader = "In this sentence"
    static func speakTitle(_ word: String) -> String { "Say \(word)" }
    static let speakingTitle = "Speaking…"
    static func speakAccessibilityLabel(word: String, languageName: String) -> String { "Say \(word) in \(languageName)" }
    static func speakHint(languageName: String) -> String { "Speaks the word with this iPhone's \(languageName) voice" }
    /// A spoken word would be heard by the microphone and translated back.
    static let microphoneNote = "Stop listening to hear words through the microphone"
    static func noVoiceNote(languageName: String) -> String {
        "This iPhone has no \(languageName) voice. Add one in Settings › Accessibility › Spoken Content › Voices."
    }
    static let translatingText = "Translating…"
    static let noMeaningText = "No meaning found for this word."
    static let needsIOS18Text = "Meanings for single words need iOS 18. The whole sentence is translated below."
    static func needsDownloadText(languageName: String) -> String {
        "To see what a word means, download \(languageName) for Apple's on-device translator in Settings › Apps › Translate."
    }
    static func unsupportedText(languageName: String) -> String {
        "Apple's on-device translator has no \(languageName), so only the whole sentence is translated."
    }
    static let dictionaryButtonTitle = "Look up in the dictionary"
    static let dictionaryHint = "Opens this iPhone's dictionary at this word"
    /// `dictionaryHasDefinition` is also false for an inflected form the installed dictionary lacks, so the note
    /// never claims a dictionary is missing.
    static func noDictionaryNote(languageName: String) -> String {
        "This word is not in this iPhone's dictionaries. You can add a \(languageName) one in Settings › General › Dictionary."
    }
    static let closeLabel = "Close"
    static func lookUpActionTitle(_ word: String) -> String { "Look up \(word)" }
}
