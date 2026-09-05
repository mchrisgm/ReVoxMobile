import SwiftUI

/// M11 (§3): the Unsure phrases section of Settings — the toggle, the greyed sample row as its example and the
/// footer. Its own view, so the Settings screen only has to place it (directly under Source language).
struct GuessesSettingsSection: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Section {
            Toggle(SettingsViewModel.keepGuessesTitle, isOn: $model.keepGuesses)
                .accessibilityHint(SettingsViewModel.keepGuessesHint)
            SettingExample(symbol: SessionSummary.guessSymbolName, text: SettingExamples.keepGuesses(model.keepGuesses)) {
                LiveTranscriptRowView(row: SettingExamples.guessRow)
            }
        } header: {
            Text(SettingsViewModel.guessesSectionTitle)
        } footer: {
            Text(SettingsViewModel.keepGuessesHelpText)
        }
    }
}
