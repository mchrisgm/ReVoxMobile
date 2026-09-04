import Foundation
import ReVoxCore
import WhisperKit          // `Constants.languages` is WhisperKit's list of the languages Whisper knows

/// The one list of languages the app offers, built once (§8.5). The source-language picker adds "Auto-detect";
/// the two-way pickers of §8.2 always name a concrete language, so they read `concrete`.
enum LanguageCatalog {
    static let autoDetectTitle = "Auto-detect"

    static let options: [LanguageOption] = languageOptions(codes: Set(Constants.languages.values), locale: .current)

    static let concrete: [LanguageOption] = options.filter { $0.code != nil }

    /// "Auto-detect" first, then the codes by localized display name (the code when the locale has no name).
    static func languageOptions(codes: Set<String>, locale: Locale) -> [LanguageOption] {
        let named = codes.map { code -> LanguageOption in
            let name = locale.localizedString(forLanguageCode: code) ?? code
            return LanguageOption(code: code, displayName: name)
        }
        .sorted { lhs, rhs in
            if lhs.displayName == rhs.displayName { return (lhs.code ?? "") < (rhs.code ?? "") }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return [LanguageOption(code: nil, displayName: autoDetectTitle)] + named
    }

    /// The name to show for a stored code; `nil` is whatever the caller calls "no choice yet".
    static func displayName(_ code: String?, whenNil: String) -> String {
        guard let code else { return whenNil }
        return options.first { $0.code == code }?.displayName ?? code
    }
}
