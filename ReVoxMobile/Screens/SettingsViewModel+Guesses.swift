import Foundation
import ReVoxCore

/// M11 (§3): the Unsure phrases setting, in its own file so the milestone's lanes land without editing
/// `SettingsViewModel.swift` (`store` is internal for exactly this).
extension SettingsViewModel {
    /// `Settings.keepGuesses`; read by `LiveViewModel.configuration` at the next Start.
    var keepGuesses: Bool {
        get { store.settings.keepGuesses }
        set { store.update { $0.keepGuesses = newValue } }
    }

    static let guessesSectionTitle = "Unsure phrases"
    static let keepGuessesTitle = "Keep unsure phrases in History"
    static let keepGuessesHint = "Keeps phrases ReVox was unsure about in History as well as on the Live screen"
    static let keepGuessesHelpText = "When ReVox is not sure of the language or the words, the phrase is shown greyed and marked Unsure on the Live screen and is never spoken aloud. With this on, those phrases are also kept in History and in the exported file, marked (unsure). A change takes effect the next time you tap Start."
}
