import Foundation
import NaturalLanguage

/// One tappable word of a Learning row's original line (M11 §2). `id` is the word's index in the sentence, so a
/// repeated word ("la … la") is two chips with their own identity; `range` indexes the sentence it came from,
/// for the popover's highlighted example.
struct OriginalWord: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let range: Range<String.Index>
}

/// Splits a sentence into the words a reader can tap (M11 §2). `NLTokenizer` is what segments Japanese, Chinese
/// and Thai without spaces; punctuation and whitespace never become chips. App target only — NaturalLanguage is
/// not on Linux, and ReVoxCore stays Foundation-only.
enum WordSplitter {
    /// Cleared, not evicted: a session is a few hundred distinct sentences, and the cache exists to stop the
    /// 1 s TimelineView ticks re-tokenising, not to survive a long day.
    static let cacheLimit = 512
    /// Scripts written right to left, whose chips the left-to-right `WordFlowLayout` cannot lay out yet: the row
    /// shows their original as plain text (M11 §2).
    static let rightToLeftLanguages: Set<String> = ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"]

    @MainActor private static var cache: [String: [OriginalWord]] = [:]

    /// A token is kept only when it holds a letter or a digit, so "¿", "," and "。" never become chips.
    static func words(in text: String, language: String) -> [OriginalWord] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(nlLanguage(for: language))
        var words: [OriginalWord] = []
        for range in tokenizer.tokens(for: text.startIndex..<text.endIndex) {
            let token = String(text[range])
            guard token.rangeOfCharacter(from: .alphanumerics) != nil else { continue }
            words.append(OriginalWord(id: words.count, text: token, range: range))
        }
        return words
    }

    /// WhisperKit's two-letter codes are ISO 639-1; NLLanguage names Chinese by script and Javanese by "jv".
    static func nlLanguage(for whisperCode: String) -> NLLanguage {
        switch whisperCode.lowercased() {
        case "zh": return .simplifiedChinese
        case "yue": return .traditionalChinese
        case "jw": return NLLanguage(rawValue: "jv")
        default: return NLLanguage(rawValue: whisperCode.lowercased())
        }
    }

    /// The same mapping as a string, handed to `Locale.Language(identifier:)` for Apple's on-device translator.
    static func translatorCode(for whisperCode: String) -> String {
        switch whisperCode.lowercased() {
        case "zh": return "zh-Hans"
        case "yue": return "zh-Hant"
        case "jw": return "jv"
        default: return whisperCode.lowercased()
        }
    }

    static func isRightToLeft(_ whisperCode: String) -> Bool {
        rightToLeftLanguages.contains(whisperCode.lowercased())
    }

    /// Memoised per (language, sentence) on the main actor: the row body under the TimelineView is a dictionary hit.
    @MainActor
    static func cachedWords(in text: String, language: String) -> [OriginalWord] {
        let key = "\(language)\u{1F}\(text)"
        if let hit = cache[key] { return hit }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        let split = words(in: text, language: language)
        cache[key] = split
        return split
    }

    /// Test seams.
    @MainActor static var cacheCount: Int { cache.count }
    @MainActor static func resetCache() { cache.removeAll() }
}
