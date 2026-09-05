import XCTest
import SwiftUI
import UIKit
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: the word chips, the popover and the dictionary sheet lay out in a `UIHostingController` at the
/// default and the largest accessibility text sizes, with the inert default lookup and with injected services.
/// SwiftUI has no unit-test renderer, so this proves the views build and do not trap on first layout — the bar
/// `ScreenHostingTests` holds every other screen to.
@MainActor
final class LearningHostingTests: XCTestCase {
    private let sentence = "Buenos días, gracias por acompañarnos hoy."
    private let english = "Good morning, thank you for joining us today."

    func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    // MARK: WordFlowLayout

    /// `PillFlowLayout`'s greedy in-order packing, copied with no gap: three 100 pt chips are 300 pt, a fourth
    /// needs 400 and wraps; an over-wide chip still gets a row of its own; a row is as tall as its tallest chip.
    func testWordFlowLayoutPacksLikeThePillLayoutWithNoGap() {
        func size(_ width: CGFloat, _ height: CGFloat = 44) -> CGSize { CGSize(width: width, height: height) }
        XCTAssertEqual(WordFlowLayout.spacing, 0)
        XCTAssertEqual(WordFlowLayout.rowSpacing, -12, "44 pt targets, lines 32 pt apart")
        XCTAssertEqual(WordFlowLayout.height(of: [.init(items: [0], height: 44), .init(items: [1], height: 44)]), 76)
        XCTAssertEqual(WordFlowLayout.height(of: [.init(items: [0], height: 44)]), 44)
        XCTAssertEqual(WordFlowLayout.height(of: []), 0)
        let rows = WordFlowLayout.rows(sizes: [size(100), size(100), size(100), size(100)], available: 320)
        XCTAssertEqual(rows.map(\.items), [[0, 1, 2], [3]])
        XCTAssertEqual(rows.map(\.height), [44, 44])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50), size(500), size(50)], available: 300).map(\.items), [[0], [1], [2]])
        XCTAssertEqual(WordFlowLayout.rows(sizes: [size(50, 44), size(50, 60)], available: 300)[0].height, 60)
        XCTAssertEqual(WordFlowLayout.rows(sizes: [], available: 300), [])
        XCTAssertEqual(WordFlowLayout.width(for: .unspecified, sizes: [size(100), size(100)]), 200)
        XCTAssertEqual(WordFlowLayout.width(for: ProposedViewSize(width: 150, height: nil), sizes: [size(100), size(100)]), 150)
    }

    func testWordFlowLayoutHostsInsideABaselineAlignedRow() {
        host(WordFlowLayout {
            Text("Buenos").font(.body)
            Text("días").font(.body)
        })
        host(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("10:41:07").font(.caption.monospacedDigit())
            WordFlowLayout {
                ForEach(0..<12, id: \.self) { index in
                    Text("palabra\(index)").font(.body).frame(minHeight: 44)
                }
            }
        }
        .frame(width: 390))
    }

    private func lookup(hasVoice: Bool, hasDefinition: Bool, translator: WordTranslatorAvailability, speaker: WordSpeaker? = nil) -> WordLookup {
        WordLookup(speaker: speaker, hasVoice: { _ in hasVoice }, hasDefinition: { _ in hasDefinition },
                   translatorAvailability: { _ in translator })
    }

    // MARK: WordPopoverView and DictionaryView

    /// Every source combination the popover can show, at the default size and at `.accessibility5`, where the
    /// content adapts to a sheet. `translationRequest` is nil in every hosted model, so no translation task is
    /// ever attached on the CI simulator.
    func testWordPopoverViewHostsEveryState() async throws {
        let gracias = try XCTUnwrap(WordSplitter.words(in: sentence, language: "es").first { $0.text == "gracias" })
        func model(_ lookup: WordLookup) -> WordPopoverModel {
            WordPopoverModel(word: gracias, language: "es", original: sentence, english: english, lookup: lookup)
        }
        // iOS 17 copy, the default lookup: no speaker, no voice, no dictionary.
        host(WordPopoverView(model: model(.unavailable)))
        for translator in [WordTranslatorAvailability.needsDownload, .unsupported] {
            let unavailable = model(lookup(hasVoice: false, hasDefinition: false, translator: translator))
            await unavailable.load()
            XCTAssertNil(unavailable.translationRequest)
            host(WordPopoverView(model: unavailable))
        }
        // No voice, a dictionary entry: the voice note and the Look up button.
        let noVoice = model(lookup(hasVoice: false, hasDefinition: true, translator: .unavailableOnThisiOS))
        await noVoice.load()
        host(WordPopoverView(model: noVoice, onLookUp: { _ in }, onClose: {}))
        // Ready and answered, with a live Say button.
        let speaker = WordSpeaker(voices: { [] }, speak: { _ in }, stop: {})
        let ready = model(lookup(hasVoice: true, hasDefinition: false, translator: .ready, speaker: speaker))
        await ready.load()
        ready.receiveMeaning("thank you")
        XCTAssertNil(ready.translationRequest)
        host(WordPopoverView(model: ready))
        host(WordPopoverView(model: ready).environment(\.dynamicTypeSize, .accessibility5))
        speaker.noteStarted()
        host(WordPopoverView(model: ready))                       // "Speaking…"
        speaker.noteFinished()
        // Say disabled while a microphone run is going.
        let listening = WordSpeaker(isMicrophoneRunning: { true }, voices: { [] }, speak: { _ in }, stop: {})
        let disabled = model(lookup(hasVoice: true, hasDefinition: false, translator: .ready, speaker: listening))
        await disabled.load()
        disabled.receiveMeaning(nil)
        XCTAssertEqual(disabled.content.speakDisabledNote, WordPopoverContent.microphoneNote)
        host(WordPopoverView(model: disabled))
        XCTAssertEqual(WordPopoverView.idealWidth, 300)
        XCTAssertEqual(WordPopoverView.maximumWidth, 360)
        XCTAssertEqual(WordPopoverView.buttonHeight, 44)
    }

    func testTheHighlightedSentenceKeepsEveryCharacter() throws {
        let words = WordSplitter.words(in: sentence, language: "es")
        for word in words {
            let example = WordPopoverContent.Example(original: sentence, range: word.range, english: english)
            host(WordPopoverView.highlightedSentence(example))
        }
        XCTAssertEqual(words.map(\.text), ["Buenos", "días", "gracias", "por", "acompañarnos", "hoy"])
    }

    func testDictionaryViewHosts() {
        host(DictionaryView(term: "station"))
        XCTAssertEqual(DictionaryTerm(term: "station").id, "station")
    }

    // MARK: OriginalWordsLine

    /// The chips with and without a selection, at the default and the largest accessibility size, one- and
    /// two-character Japanese chips with no minimum width, the line inside the row's baseline-aligned HStack as
    /// the row view places it (wave 2), and the custom-action modifier on a combined element.
    func testOriginalWordsLineHostsWithAndWithoutASelection() throws {
        let words = WordSplitter.words(in: sentence, language: "es")
        XCTAssertEqual(words.count, 6)
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil)))
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil))
            .environment(\.dynamicTypeSize, .accessibility5))
        let selected = WordPopoverModel(word: words[1], language: "es", original: sentence, english: english, lookup: .unavailable)
        host(OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(selected)))
        let tokyo = "東京タワーに行きます"
        let japanese = WordSplitter.words(in: tokyo, language: "ja")
        XCTAssertFalse(japanese.isEmpty)
        host(OriginalWordsLine(original: tokyo, language: "ja", english: "I am going to Tokyo Tower.", words: japanese, lookup: .constant(nil)))
        host(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("10:41:07").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text("es").font(.caption2.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                OriginalWordsLine(original: sentence, language: "es", english: english, words: words, lookup: .constant(nil))
                Text(english).font(.body)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 390))
        host(Text(sentence)
            .accessibilityElement(children: .combine)
            .modifier(WordLookUpActions(words: words, language: "es", original: sentence, english: english, lookup: .constant(nil))))
        XCTAssertEqual(OriginalWordsLine.chipMinimumHeight, 44)
        XCTAssertEqual(OriginalWordsLine.chipCornerRadius, 6)
        XCTAssertEqual(OriginalWordsLine.selectedFillOpacity, 0.22)
    }
}
