import SwiftUI
import UIKit

/// The services a word popover needs (M11 §2), carried by the SwiftUI environment so the shared row view gains no
/// parameters and every hosted test row gets an honest, inert default: no speaker, no voice, no dictionary,
/// iOS 17 copy — without touching a framework. `AppEnvironment` builds the production one and `RootView` applies
/// it outermost, after `.fullScreenCover`, so the tutorial inherits it.
struct WordLookup {
    var speaker: WordSpeaker?
    /// Whether this iPhone has a voice for a language code.
    var hasVoice: @MainActor (String) -> Bool
    /// Whether this iPhone's dictionaries have an entry for a word.
    var hasDefinition: @MainActor (String) -> Bool
    /// Apple's on-device translator for a language code → English; never triggers a download.
    var translatorAvailability: @Sendable (String) async -> WordTranslatorAvailability

    static var unavailable: WordLookup {
        WordLookup(speaker: nil, hasVoice: { _ in false }, hasDefinition: { _ in false },
                   translatorAvailability: { _ in .unavailableOnThisiOS })
    }

    /// The production services: the speaker's voice list (read once), the iPhone's dictionaries, the probe.
    @MainActor
    static func production(speaker: WordSpeaker) -> WordLookup {
        WordLookup(
            speaker: speaker,
            hasVoice: { language in
                SystemSpeaker.selectVoice(identifier: nil, language: language, voices: speaker.availableVoices()) != nil
            },
            hasDefinition: { term in UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) },
            translatorAvailability: { language in await WordTranslatorProbe.availability(language: language) }
        )
    }
}

private struct WordLookupKey: EnvironmentKey {
    static var defaultValue: WordLookup { .unavailable }
}

extension EnvironmentValues {
    var wordLookup: WordLookup {
        get { self[WordLookupKey.self] }
        set { self[WordLookupKey.self] = newValue }
    }
}
