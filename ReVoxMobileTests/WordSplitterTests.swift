import XCTest
import NaturalLanguage
@testable import ReVoxMobile

/// M11 §2: the words a Learning row offers for tapping. CJK boundaries are Apple's and are never pinned; the
/// tests hold the invariants — no punctuation, nothing lost, ranges that index the sentence.
final class WordSplitterTests: XCTestCase {
    func testSpanishSplitsOnSpacesAndDropsPunctuation() {
        XCTAssertEqual(WordSplitter.words(in: "¿Dónde está la estación?", language: "es").map(\.text), ["Dónde", "está", "la", "estación"])
        XCTAssertEqual(WordSplitter.words(in: "Buenos días.", language: "es").map(\.text), ["Buenos", "días"])
    }

    func testRangesIndexTheSentenceAndIdsAreTheWordOrder() {
        let sentence = "Buenos días, gracias por acompañarnos hoy."
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.map(\.id), Array(0..<words.count))
        XCTAssertEqual(words.count, 6)
        for word in words {
            XCTAssertEqual(String(sentence[word.range]), word.text)
        }
    }

    func testCJKIsSplitWithoutSpacesAndWithoutPunctuation() {
        let japanese = WordSplitter.words(in: "こんにちは、世界！", language: "ja")
        XCTAssertFalse(japanese.isEmpty)
        XCTAssertFalse(japanese.contains { $0.text.contains("、") || $0.text.contains("！") })
        XCTAssertEqual(japanese.map(\.text).joined(), "こんにちは世界")
        XCTAssertEqual(WordSplitter.words(in: "你好世界", language: "zh").map(\.text).joined(), "你好世界")
        XCTAssertEqual(WordSplitter.words(in: "東京タワー", language: "ja").map(\.text).joined(), "東京タワー")
    }

    func testMixedScriptsKeepEveryPart() {
        let words = WordSplitter.words(in: "Tokyo 東京", language: "ja").map(\.text)
        XCTAssertEqual(words.first, "Tokyo")
        XCTAssertEqual(words.dropFirst().joined(), "東京")
    }

    func testEmptyAndBlankGiveNoWords() {
        XCTAssertEqual(WordSplitter.words(in: "", language: "es"), [])
        XCTAssertEqual(WordSplitter.words(in: "   ", language: "es"), [])
        XCTAssertEqual(WordSplitter.words(in: "…", language: "es"), [])
    }

    func testWhisperCodesMapToNaturalLanguageAndTheTranslator() {
        XCTAssertEqual(WordSplitter.nlLanguage(for: "zh"), .simplifiedChinese)
        XCTAssertEqual(WordSplitter.nlLanguage(for: "yue"), .traditionalChinese)
        XCTAssertEqual(WordSplitter.nlLanguage(for: "jw"), NLLanguage(rawValue: "jv"))
        XCTAssertEqual(WordSplitter.nlLanguage(for: "es"), .spanish)
        XCTAssertEqual(WordSplitter.translatorCode(for: "zh"), "zh-Hans")
        XCTAssertEqual(WordSplitter.translatorCode(for: "yue"), "zh-Hant")
        XCTAssertEqual(WordSplitter.translatorCode(for: "jw"), "jv")
        XCTAssertEqual(WordSplitter.translatorCode(for: "es"), "es")
    }

    func testRightToLeftLanguagesAreNamed() {
        XCTAssertEqual(WordSplitter.rightToLeftLanguages, ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"])
        XCTAssertTrue(WordSplitter.isRightToLeft("ar"))
        XCTAssertTrue(WordSplitter.isRightToLeft("he"))
        XCTAssertFalse(WordSplitter.isRightToLeft("es"))
    }

    /// The cache is process-global and the hosting tests fill it too, so the test resets it first and reads
    /// counts only after that reset.
    @MainActor
    func testTheCacheAnswersTheSecondCallWithoutTokenisingAndClearsAtTheLimit() {
        WordSplitter.resetCache()
        XCTAssertEqual(WordSplitter.cacheCount, 0)
        let first = WordSplitter.cachedWords(in: "Buenos días.", language: "es")
        let second = WordSplitter.cachedWords(in: "Buenos días.", language: "es")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, WordSplitter.words(in: "Buenos días.", language: "es"))
        XCTAssertEqual(WordSplitter.cacheCount, 1, "one distinct (language, sentence)")
        _ = WordSplitter.cachedWords(in: "Buenos días.", language: "pt")
        XCTAssertEqual(WordSplitter.cacheCount, 2, "the language is part of the key")
        for index in 0..<(WordSplitter.cacheLimit - 2) {
            _ = WordSplitter.cachedWords(in: "frase \(index)", language: "es")
        }
        XCTAssertEqual(WordSplitter.cacheCount, WordSplitter.cacheLimit)
        _ = WordSplitter.cachedWords(in: "una más", language: "es")
        XCTAssertEqual(WordSplitter.cacheCount, 1, "cleared at the limit, then the new sentence")
        XCTAssertEqual(WordSplitter.cacheLimit, 512)
        WordSplitter.resetCache()
    }
}
