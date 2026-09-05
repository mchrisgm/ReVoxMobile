import XCTest
@testable import ReVoxCore

/// M11 §5: the benchmark's accuracy score.
final class WordErrorRateTests: XCTestCase {
    private let reference = "Good morning, where is the train station?"

    func testIdenticalTextIsZero() {
        XCTAssertEqual(WordErrorRate.rate(reference: reference, hypothesis: reference), 0)
        XCTAssertEqual(WordErrorRate.accuracy(reference: reference, hypothesis: reference), 1)
    }

    func testEmptyHypothesisIsOne() {
        XCTAssertEqual(WordErrorRate.rate(reference: reference, hypothesis: ""), 1)
        XCTAssertEqual(WordErrorRate.accuracy(reference: reference, hypothesis: ""), 0)
    }

    /// The reference has seven words, so one substitution is one seventh.
    func testOneSubstitutionInSevenWordsIsOneSeventh() {
        XCTAssertEqual(WordErrorRate.words(reference).count, 7)
        XCTAssertEqual(WordErrorRate.rate(reference: reference, hypothesis: "Good morning, where is the bus station?"), 1.0 / 7.0, accuracy: 0.0001)
    }

    func testInsertionsCanExceedOneAndAccuracyClampsAtZero() {
        let rate = WordErrorRate.rate(reference: "hello", hypothesis: "well hello there friend")
        XCTAssertEqual(rate, 3)
        XCTAssertEqual(WordErrorRate.accuracy(reference: "hello", hypothesis: "well hello there friend"), 0)
    }

    func testNormalisationDropsCaseAndPunctuation() {
        XCTAssertEqual(WordErrorRate.words("¿Dónde está la estación?"), ["dónde", "está", "la", "estación"])
        XCTAssertEqual(WordErrorRate.words("  Station?  "), ["station"])
        XCTAssertEqual(WordErrorRate.rate(reference: "Station?", hypothesis: "station"), 0)
        XCTAssertEqual(WordErrorRate.rate(reference: "¿Dónde está la estación?", hypothesis: "donde esta la estacion"), 0.75,
                       "accents are kept, so three of the four words differ")
    }

    func testEmptyReference() {
        XCTAssertEqual(WordErrorRate.rate(reference: "", hypothesis: ""), 0)
        XCTAssertEqual(WordErrorRate.rate(reference: "?!", hypothesis: ""), 0, "punctuation only is an empty reference")
        XCTAssertEqual(WordErrorRate.rate(reference: "", hypothesis: "you"), 1)
    }

    func testEditDistanceIsLevenshtein() {
        XCTAssertEqual(WordErrorRate.editDistance(["a", "b", "c"], ["a", "c"]), 1)
        XCTAssertEqual(WordErrorRate.editDistance([], ["a", "b"]), 2)
        XCTAssertEqual(WordErrorRate.editDistance(["a", "b"], []), 2)
        XCTAssertEqual(WordErrorRate.editDistance(["a", "b", "c"], ["a", "x", "c"]), 1)
        XCTAssertEqual(WordErrorRate.editDistance(["a", "b", "c"], ["c", "b", "a"]), 2)
    }
}
