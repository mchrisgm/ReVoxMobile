import SwiftUI
import Translation

/// Whether Apple's on-device translator can give the meaning of a single word (M11 §2).
enum WordTranslatorAvailability: Equatable, Sendable {
    /// iOS 17: the framework is not there, and nothing here touches it.
    case unavailableOnThisiOS
    /// iOS 18, the pair is supported but not downloaded; a word tap never triggers the download prompt.
    case needsDownload
    case unsupported
    case ready
}

/// Translates one word to English through a self-contained `translationTask` on the popover content (M11 §2):
/// source = the row's language, target = English. `nil` word = no task, on iOS 18 too. The two-way bridge and
/// its serving are never involved.
struct WordTranslation: ViewModifier {
    let word: String?
    let language: String
    let onResult: @MainActor (String?) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(AppleWordTranslation(word: word, language: language, onResult: onResult))
        } else {
            content
        }
    }
}

@available(iOS 18, *)
private struct AppleWordTranslation: ViewModifier {
    let word: String?
    let language: String
    let onResult: @MainActor (String?) -> Void

    /// `Configuration` is `Equatable`, so SwiftUI starts one task per word and ends it when the word goes nil.
    private var configuration: TranslationSession.Configuration? {
        guard let word, !word.isEmpty else { return nil }
        return TranslationSession.Configuration(source: Locale.Language(identifier: WordSplitter.translatorCode(for: language)),
                                                target: Locale.Language(identifier: "en"))
    }

    func body(content: Content) -> some View {
        content.translationTask(configuration) { session in
            guard let word else { return }
            // Only a `.ready` (installed) pair ever gets here, so `prepareTranslation()` and its download prompt are not needed.
            let translated = try? await session.translate(word).targetText
            await onResult(translated)
        }
    }
}

/// Answers without ever downloading: `LanguageAvailability` on iOS 18, a constant on iOS 17.
enum WordTranslatorProbe {
    static func availability(language: String) async -> WordTranslatorAvailability {
        if #available(iOS 18, *) {
            return await AppleWordTranslatorProbe.availability(language: language)
        }
        return .unavailableOnThisiOS
    }
}

@available(iOS 18, *)
private enum AppleWordTranslatorProbe {
    static func availability(language: String) async -> WordTranslatorAvailability {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: WordSplitter.translatorCode(for: language)),
            to: Locale.Language(identifier: "en")
        )
        switch status {
        case .installed: return .ready
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
