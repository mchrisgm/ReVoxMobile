import XCTest
@testable import ReVoxCore

final class SpokenTextTests: XCTestCase {
    func testAPlainSentenceIsUntouched() {
        XCTAssertEqual(SpokenText.clean("Good morning, everyone!"), "Good morning, everyone!")
        XCTAssertEqual(SpokenText.clean("¿Dónde está la estación?"), "¿Dónde está la estación?")
        XCTAssertEqual(SpokenText.clean("It cost £4.50 — twice."), "It cost £4.50 — twice.")
    }

    /// The shape Whisper's decoder would produce if `skipSpecialTokens` were ever false or a future model
    /// emitted them anyway: the two-letter language tag is the thing the owner must never hear.
    func testWhisperSpecialTokensAreRemovedIncludingTheLanguageTag() {
        XCTAssertEqual(SpokenText.clean("<|startoftranscript|><|es|><|translate|><|notimestamps|> Good morning<|endoftext|>"),
                       "Good morning")
        XCTAssertEqual(SpokenText.clean("<|es|> hola"), "hola")
        XCTAssertEqual(SpokenText.clean("<|0.00|> Hello there<|2.00|>"), "Hello there")
        XCTAssertEqual(SpokenText.clean("<|en|>"), "")
    }

    func testWhitespaceLeftBehindByARemovedTokenIsCollapsed() {
        XCTAssertEqual(SpokenText.clean("<|es|>   hola   <|endoftext|>"), "hola")
        XCTAssertEqual(SpokenText.clean("one\n\ttwo   three"), "one two three")
        XCTAssertEqual(SpokenText.clean("   "), "")
    }

    /// A `<` the speaker should actually say is not a special token and must survive.
    func testABareAngleBracketIsText() {
        XCTAssertEqual(SpokenText.clean("a < b and c > d"), "a < b and c > d")
        XCTAssertEqual(SpokenText.clean("5 <| 6"), "5 <| 6", "an unterminated span is text, not a token")
        XCTAssertEqual(SpokenText.clean("x <|a| y"), "x <|a| y")
    }

    func testTheGateHandsTheSpeakerTheCleanedSentence() {
        let candidate = TranslationCandidate(
            language: "es", languageProbability: 0.9,
            segments: [TranslationSegment(text: "<|es|> Good morning", noSpeechProbability: 0, averageLogProbability: -0.1),
                       TranslationSegment(text: " everyone<|endoftext|>", noSpeechProbability: 0, averageLogProbability: -0.1)]
        )
        XCTAssertEqual(SpeechGate.evaluate(candidate), Translation(english: "Good morning everyone", language: "es"))
    }

    func testAdjacentEmptyAndPipeBearingTokensAreRemoved() {
        XCTAssertEqual(SpokenText.clean("<|es|><|fr|>x"), "x")
        XCTAssertEqual(SpokenText.clean("<||>a"), "a")
        XCTAssertEqual(SpokenText.clean("<|a|b|>c"), "c", "a pipe inside the span does not end it early")
        XCTAssertEqual(SpokenText.clean("<|es|"), "<|es|", "no closing bracket: text")
        XCTAssertEqual(SpokenText.clean("<"), "<")
        XCTAssertEqual(SpokenText.clean(""), "")
    }
}
