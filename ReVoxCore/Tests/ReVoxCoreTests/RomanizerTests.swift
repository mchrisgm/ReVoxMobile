import XCTest
@testable import ReVoxCore

final class RomanizerTests: XCTestCase {
    func testScriptsAreTransliteratedToLatin() {
        XCTAssertEqual(Romanizer.romanize("こんにちは"), "kon'nichiha")
        XCTAssertEqual(Romanizer.romanize("Привет мир"), "Privet mir")
        XCTAssertEqual(Romanizer.romanize("你好"), "nǐ hǎo")
    }

    func testLatinTextHasNoRomanization() {
        XCTAssertNil(Romanizer.romanize("Good morning."), "the row must not show the same line twice")
        XCTAssertNil(Romanizer.romanize("Buenos días."), "accents are Latin already")
        XCTAssertNil(Romanizer.romanize(""))
        XCTAssertNil(Romanizer.romanize("   "))
    }

    func testMixedTextKeepsTheLatinPart() {
        XCTAssertEqual(Romanizer.romanize("Tokyo 東京"), "Tokyo dōng jīng")
    }
}
