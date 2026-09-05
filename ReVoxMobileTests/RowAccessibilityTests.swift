import XCTest
import SwiftUI
import ReVoxCore
@testable import ReVoxMobile

/// The pure helpers behind the rows' VoiceOver output (M10 HIG audit): what the leading column, the language
/// badge and the Models row say, kept off the views so they can be read without a host.
@MainActor
final class RowAccessibilityTests: XCTestCase {
    private let said = Date(timeIntervalSince1970: 1_700_000_000)

    func testSpokenAgeSaysTheUnitsInFull() {
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said), "just now")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(0.9)), "just now")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(1)), "1 second ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(12)), "12 seconds ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(60)), "1 minute ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(3 * 60 + 59)), "3 minutes ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(3_600)), "1 hour ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(2 * 3_600 + 60)), "2 hours 1 minute ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(3_600 + 5 * 60)), "1 hour 5 minutes ago")
        XCTAssertEqual(LiveTranscriptRowView.spokenAge(from: said, to: said.addingTimeInterval(-30)), "just now",
                       "a skewed clock never speaks a negative age, as RelativeAge never shows one")
    }

    /// The spoken form and the visible form share their buckets: for every age the numbers agree.
    func testSpokenAgeAgreesWithTheVisibleAge() {
        for seconds in [0, 1, 59, 60, 61, 3_599, 3_600, 3_661, 7_200, 86_399] {
            let now = said.addingTimeInterval(TimeInterval(seconds))
            let visible = RelativeAge.text(from: said, to: now)
            let spoken = LiveTranscriptRowView.spokenAge(from: said, to: now)
            XCTAssertEqual(visible.filter(\.isNumber), spoken.filter(\.isNumber), "\(seconds) s: \"\(visible)\" vs \"\(spoken)\"")
        }
    }

    func testLeadingAccessibilityTextFollowsTheDisplayMode() {
        let now = said.addingTimeInterval(12)
        let clock = LiveTranscriptRowView.leadingText(time: said, now: nil, display: .time)
        XCTAssertEqual(LiveTranscriptRowView.leadingAccessibilityText(time: said, now: now, display: .age), "12 seconds ago")
        XCTAssertEqual(LiveTranscriptRowView.leadingAccessibilityText(time: said, now: now, display: .time), clock)
        XCTAssertEqual(LiveTranscriptRowView.leadingAccessibilityText(time: said, now: now, display: .both), "12 seconds ago, \(clock)")
        XCTAssertEqual(LiveTranscriptRowView.leadingAccessibilityText(time: said, now: nil, display: .age), clock,
                       "History passes no clock and is spoken as the time, like it is shown")
    }

    func testLanguageBadgeSpeaksTheLanguageName() {
        let spanish = LiveTranscriptRowView.languageAccessibilityText("es")
        XCTAssertTrue(spanish.hasPrefix("Language "))
        XCTAssertNotEqual(spanish, "Language es", "the locale's name for the code, not the code spelt out")
        XCTAssertEqual(LiveTranscriptRowView.languageAccessibilityText("zz"), "Language zz", "an unknown code is read as it is")
    }

    func testModelRowSentenceLeavesSelectionToTheTraitAndSpeaksTheClampedPercent() {
        let installed = ModelDownloadState(phase: .installed, fraction: 1, bytesExpected: 1)
        let selected = ModelRow(id: .small, name: "small", sizeText: "487 MB", isRecommended: true, isSuitable: true, warning: nil, note: nil,
                                state: installed, isSelected: true)
        XCTAssertEqual(ModelRowView.accessibilityText(for: selected), "Model small. 487 MB. Installed. Recommended")
        XCTAssertNil(ModelRowView.selectHint(for: selected), "already in use: a tap does nothing, so no hint")

        let idleInstalled = ModelRow(id: .base, name: "base", sizeText: "145 MB", isRecommended: false, isSuitable: true, warning: nil, note: nil,
                                     state: installed, isSelected: false)
        XCTAssertEqual(ModelRowView.selectHint(for: idleInstalled), "Uses this model for the next session")
        XCTAssertEqual(ModelRowView.accessibilityText(for: idleInstalled), "Model base. 145 MB. Installed")

        let downloading = ModelRow(id: .largeV3, name: "large-v3", sizeText: "≈ 948 MB", isRecommended: false, isSuitable: false, warning: nil, note: nil,
                                   state: ModelDownloadState(phase: .downloading(completedFiles: 2, totalFiles: 6), fraction: 0.42, bytesExpected: 1),
                                   isSelected: false)
        XCTAssertEqual(ModelRowView.accessibilityText(for: downloading),
                       "Model large-v3. ≈ 948 MB. Downloading 2 of 6 files. Not recommended for this iPhone. 42 percent")
        XCTAssertNil(ModelRowView.selectHint(for: downloading), "not installed: nothing to select")

        let paused = ModelRow(id: .tiny, name: "tiny", sizeText: "≈ 77 MB", isRecommended: false, isSuitable: true, warning: nil, note: nil,
                              state: ModelDownloadState(phase: .paused, fraction: 0.5, bytesExpected: 1), isSelected: false)
        XCTAssertEqual(ModelRowView.accessibilityText(for: paused), "Model tiny. ≈ 77 MB. Paused",
                       "a paused fraction is not spoken as progress: nothing is moving")
    }

    // MARK: M11 §3: the guess marker

    func testTheGuessMarkerCopyIsExactAndSharesTheHistorySymbol() {
        XCTAssertEqual(LiveTranscriptRowView.guessMarkerText, "Unsure")
        XCTAssertEqual(LiveTranscriptRowView.guessAccessibilityText, "Unsure translation")
        XCTAssertEqual(LiveTranscriptRowView.guessSymbolName, "questionmark.circle")
        XCTAssertEqual(LiveTranscriptRowView.guessSymbolName, SessionSummary.guessSymbolName,
                       "Live, Session detail, the History row and the Settings example show one symbol")
    }

    // MARK: M11 §2: which rows tap words, and the Look up actions

    func testTapsWordsOnlyOnAForeignLeftToRightOriginal() {
        XCTAssertTrue(LiveTranscriptRowView.tapsWords(language: "es", original: "Buenos días.", english: "Good morning."))
        XCTAssertTrue(LiveTranscriptRowView.tapsWords(language: "ja", original: "おはよう", english: "Good morning."))
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "es", original: "", english: "Good morning."), "Learning off: no original")
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "es", original: "Hola", english: "Hola"), "nothing to learn when the two are the same")
        XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: "en", original: "Yes", english: "Sí"), "English rows are never tappable")
        for code in ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"] {
            XCTAssertFalse(LiveTranscriptRowView.tapsWords(language: code, original: "مرحبا", english: "Hello"), "\(code) is right-to-left: plain text for now")
        }
        XCTAssertEqual(LiveTranscriptRowView.rightToLeftLanguages, ["ar", "fa", "he", "ur", "ps", "sd", "ug", "yi"])
        XCTAssertEqual(LiveTranscriptRowView.rightToLeftLanguages, WordSplitter.rightToLeftLanguages, "one list with the splitter")
    }

    func testTheWordActionsNameTheWordAndStopAtTwelve() {
        XCTAssertEqual(LiveTranscriptRowView.wordActionTitle("estación"), "Look up estación")
        XCTAssertEqual(LiveTranscriptRowView.maxWordActions, 12)
        XCTAssertEqual(LiveTranscriptRowView.maxWordActions, OriginalWordsLine.customActionLimit, "the row and the line agree on the cap")
        let sentence = "uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince"
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 15)
        let actions = LiveTranscriptRowView.actionWords(words)
        XCTAssertEqual(actions.count, 12)
        XCTAssertEqual(actions.map(\.text), Array(words.prefix(12)).map(\.text), "the first twelve, in sentence order")
        XCTAssertTrue(LiveTranscriptRowView.actionWords([]).isEmpty)
    }

    /// The row hosts with the inert default lookup (`WordLookup.unavailable`) on both paths — chips for a Spanish
    /// Learning row and for a Japanese guess with an original, plain text for an English row and for a
    /// right-to-left one — at the default and the largest accessibility size.
    func testRowsWithChipsHostAtEverySize() {
        let rows = [
            LiveTranscriptRow(time: said, kind: .entry(language: "es", original: "¿Dónde está la estación?", english: "Where is the station?")),
            LiveTranscriptRow(time: said.addingTimeInterval(1), kind: .entry(language: "ja", original: "おはよう", english: "Good morning."), isGuess: true),
            LiveTranscriptRow(time: said.addingTimeInterval(2), kind: .entry(language: "en", original: "Hello there", english: "Hello there")),
            LiveTranscriptRow(time: said.addingTimeInterval(3), kind: .entry(language: "ar", original: "مرحبا", english: "Hello")),
        ]
        for size in [DynamicTypeSize.large, .accessibility5] {
            host(List {
                ForEach(rows) { row in
                    LiveTranscriptRowView(row: row, now: self.said.addingTimeInterval(12), timeDisplay: .both, showsOriginal: true, romanizes: true)
                }
            }
            .environment(\.dynamicTypeSize, size))
        }
        host(List { ForEach(rows) { LiveTranscriptRowView(row: $0) } })
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }
}
