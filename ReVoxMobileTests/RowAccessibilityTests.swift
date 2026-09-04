import XCTest
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
}
