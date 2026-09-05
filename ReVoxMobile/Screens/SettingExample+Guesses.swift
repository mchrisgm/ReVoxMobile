import Foundation

/// M11 (§3): the copy and the sample row of the Unsure phrases setting.
extension SettingExamples {
    static func keepGuesses(_ on: Bool) -> String {
        on ? "An unsure phrase stays in the session, greyed and marked Unsure, so you can read what ReVox thought it heard."
           : "An unsure phrase is shown on the Live screen only. History keeps the phrases ReVox was sure of."
    }

    /// The Spanish sample row as a guess: what the Live screen and History show for an unsure phrase.
    static let guessRow = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, time: sampleTime,
                                            kind: .entry(language: "es", original: "", english: spanishEnglish), isGuess: true)
}
