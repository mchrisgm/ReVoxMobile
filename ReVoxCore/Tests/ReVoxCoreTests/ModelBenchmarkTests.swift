import XCTest
@testable import ReVoxCore

/// M11 §5: the run record, the verdict wording and the share text.
final class ModelBenchmarkTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14T22:13:20Z

    private func result(_ model: WhisperModelID, load: Double = 3, first: Double = 1.2, steady: Double = 0.9, audio: Double = 3.8,
                        wer: Double = 0.125, before: Int = 120, delta: Int = 240, thermal: String = "nominal") -> ModelBenchmarkResult {
        ModelBenchmarkResult(model: model, loadSeconds: load, firstSeconds: first, steadySeconds: steady, audioSeconds: audio,
                             wordErrorRate: wer, residentBeforeMB: before, peakDeltaMB: delta, thermalState: thermal,
                             hypothesis: "Good morning, where is the bus station?")
    }

    private func run(_ results: [ModelBenchmarkResult]) -> BenchmarkRun {
        BenchmarkRun(date: fixedDate, device: "iPhone17,1", iOSVersion: "26.0", memoryTierGB: 8, whisperKitVersion: "1.1.0",
                     sentence: BenchmarkSentences.spanish, results: results)
    }

    // MARK: Sentences

    func testSentencesHaveTheThreePreferredLanguagesAndAnEnglishFallback() {
        XCTAssertEqual(BenchmarkSentences.preferred.map(\.language), ["es", "fr", "de"])
        XCTAssertEqual(BenchmarkSentences.english.language, "en")
        XCTAssertEqual(BenchmarkSentences.spanish.text, "Buenos días, ¿dónde está la estación de tren?")
        XCTAssertEqual(BenchmarkSentences.spanish.reference, "Good morning, where is the train station?")
        XCTAssertEqual(BenchmarkSentences.english.text, BenchmarkSentences.english.reference)
        for sentence in BenchmarkSentences.preferred + [BenchmarkSentences.english] {
            XCTAssertFalse(sentence.reference.isEmpty, sentence.language)
            XCTAssertEqual(WordErrorRate.words(sentence.reference).count, 7, "\(sentence.language): seven reference words, so one error is one seventh")
        }
    }

    func testFirstSpokenPicksTheFirstAvailableElseEnglish() {
        XCTAssertEqual(BenchmarkSentences.first(spokenBy: { $0 == "de" }), BenchmarkSentences.german)
        XCTAssertEqual(BenchmarkSentences.first(spokenBy: { $0 == "fr" || $0 == "de" }), BenchmarkSentences.french)
        XCTAssertEqual(BenchmarkSentences.first(spokenBy: { _ in true }), BenchmarkSentences.spanish)
        XCTAssertEqual(BenchmarkSentences.first(spokenBy: { _ in false }), BenchmarkSentences.english)
    }

    // MARK: Numbers to words

    func testOneDecimalDropsATrailingZero() {
        XCTAssertEqual(BenchmarkVerdict.oneDecimal(4.0), "4")
        XCTAssertEqual(BenchmarkVerdict.oneDecimal(2.06), "2.1")
        XCTAssertEqual(BenchmarkVerdict.oneDecimal(0.45), "0.5")
        XCTAssertEqual(BenchmarkVerdict.oneDecimal(12.34), "12.3")
        XCTAssertEqual(BenchmarkVerdict.twoDecimals(0.08), "0.08")
        XCTAssertEqual(BenchmarkVerdict.twoDecimals(1.25), "1.25")
        XCTAssertEqual(BenchmarkVerdict.twoDecimals(0.142857), "0.14")
        XCTAssertEqual(BenchmarkVerdict.twoDecimals(3), "3.00")
    }

    func testSpeedWording() {
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 0.25), "4× faster than real time")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 0.476), "2.1× faster than real time")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 0.238), "4.2× faster than real time")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 1.0), "as fast as real time")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 1.6), "1.6× slower than real time")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: 0), "not measured")
        XCTAssertEqual(BenchmarkVerdict.speedText(realTimeFactor: .infinity), "not measured")
        XCTAssertEqual(BenchmarkVerdict.spokenSpeedText(realTimeFactor: 0.238), "4.2 times faster than real time")
    }

    func testLoadWording() {
        XCTAssertEqual(BenchmarkVerdict.loadText(seconds: 0.4), "loads in under a second")
        XCTAssertEqual(BenchmarkVerdict.loadText(seconds: 3), "loads in 3 s")
        XCTAssertEqual(BenchmarkVerdict.loadText(seconds: 6.3), "loads in 6 s")
        XCTAssertEqual(BenchmarkVerdict.loadText(seconds: 9.5), "loads in 10 s")
        XCTAssertEqual(BenchmarkVerdict.spokenLoadText(seconds: 3), "loads in 3 seconds")
        XCTAssertEqual(BenchmarkVerdict.spokenLoadText(seconds: 1.2), "loads in 1 second")
        XCTAssertEqual(BenchmarkVerdict.spokenLoadText(seconds: 0.4), "loads in under a second")
    }

    func testAccuracyWording() {
        XCTAssertEqual(BenchmarkVerdict.accuracyText(wordErrorRate: 0), "every word right")
        XCTAssertEqual(BenchmarkVerdict.accuracyText(wordErrorRate: 0.125), "88% of words right")
        XCTAssertEqual(BenchmarkVerdict.accuracyText(wordErrorRate: 1.0 / 7.0), "86% of words right")
        XCTAssertEqual(BenchmarkVerdict.accuracyText(wordErrorRate: 1.2), "0% of words right")
    }

    func testMemoryWording() {
        XCTAssertEqual(BenchmarkVerdict.memoryText(megabytes: 240), "uses 240 MB")
        XCTAssertEqual(BenchmarkVerdict.spokenMemoryText(megabytes: 240), "uses 240 megabytes")
    }

    func testLineIsTheFourPartsJoinedByMiddleDots() {
        XCTAssertEqual(BenchmarkVerdict.line(result(.small, load: 3, steady: 0.9, audio: 3.8, wer: 0.125, delta: 240)),
                       "4.2× faster than real time · loads in 3 s · 88% of words right · uses 240 MB")
        XCTAssertEqual(BenchmarkVerdict.line(.skipped(.medium, reason: BenchmarkSkipReason.tooHot, thermalState: "serious")),
                       "Skipped: iPhone too hot")
    }

    func testSummaryFollowsTheThresholds() {
        let keepsUp = result(.small, load: 3, steady: 0.3, audio: 1)
        XCTAssertEqual(BenchmarkVerdict.summaryText(keepsUp), "Keeps up")
        XCTAssertEqual(BenchmarkVerdict.summarySymbol(keepsUp), "checkmark.circle")
        let tooSlow = result(.medium, load: 3, steady: 0.8, audio: 1)
        XCTAssertEqual(BenchmarkVerdict.summaryText(tooSlow), "Too slow for live use")
        XCTAssertEqual(BenchmarkVerdict.summarySymbol(tooSlow), "tortoise")
        let slowToLoad = result(.medium, load: 12, steady: 0.3, audio: 1)
        XCTAssertEqual(BenchmarkVerdict.summaryText(slowToLoad), "Slow to load")
        XCTAssertEqual(BenchmarkVerdict.summarySymbol(slowToLoad), "hourglass")
        XCTAssertEqual(BenchmarkVerdict.summaryText(result(.base, load: 3, steady: 0.5, audio: 1)), "Too slow for live use", "0.5 exactly is out")
        XCTAssertEqual(BenchmarkVerdict.summaryText(result(.base, load: 10, steady: 0.3, audio: 1)), "Slow to load", "10 s exactly is out")
        let skipped = ModelBenchmarkResult.skipped(.largeV3, reason: BenchmarkSkipReason.cancelled, thermalState: "fair")
        XCTAssertEqual(BenchmarkVerdict.summaryText(skipped), "Skipped: cancelled")
        XCTAssertEqual(BenchmarkVerdict.summarySymbol(skipped), "minus.circle")
    }

    func testSpokenTextSaysTheUnitsInFull() {
        XCTAssertEqual(BenchmarkVerdict.spokenText(result(.small, load: 3, steady: 0.9, audio: 3.8, wer: 0.125, delta: 240)),
                       "small. Keeps up. 4.2 times faster than real time. loads in 3 seconds. 88% of words right. uses 240 megabytes")
        XCTAssertEqual(BenchmarkVerdict.spokenText(.skipped(.medium, reason: BenchmarkSkipReason.tooHot, thermalState: "serious")),
                       "medium. Skipped: iPhone too hot")
    }

    func testSkipReasonTexts() {
        XCTAssertEqual(BenchmarkSkipReason.tooHot, "iPhone too hot")
        XCTAssertEqual(BenchmarkSkipReason.cancelled, "cancelled")
        XCTAssertEqual(BenchmarkSkipReason.couldNotLoad("boom"), "couldn't load: boom")
        XCTAssertEqual(BenchmarkSkipReason.couldNotTranslate("boom"), "couldn't translate: boom")
    }

    func testDateTextIsDayMonthYearInTheGivenTimeZone() {
        XCTAssertEqual(BenchmarkVerdict.dateText(fixedDate, timeZone: TimeZone(identifier: "UTC")!), "14 November 2023")
        XCTAssertEqual(BenchmarkVerdict.dateText(fixedDate, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "15 November 2023")
        XCTAssertEqual(BenchmarkVerdict.dateText(Date(timeIntervalSince1970: 1_788_000_000), timeZone: TimeZone(identifier: "UTC")!), "29 August 2026")
    }

    // MARK: The run

    func testResultForModelAndMeasured() {
        let tooHot = ModelBenchmarkResult.skipped(.medium, reason: BenchmarkSkipReason.tooHot, thermalState: "serious")
        let saved = run([result(.tiny, wer: 0.25), result(.small, wer: 0), tooHot])
        XCTAssertEqual(saved.result(for: .small)?.wordErrorRate, 0)
        XCTAssertNil(saved.result(for: .largeV3))
        XCTAssertEqual(saved.measured.map(\.model), [.tiny, .small])
        XCTAssertTrue(tooHot.isSkipped)
        XCTAssertEqual(tooHot.realTimeFactor, 0, "no audio: zero, never infinite")
    }

    func testRealTimeFactorIsSteadyOverAudio() {
        XCTAssertEqual(result(.tiny, steady: 0.5, audio: 2).realTimeFactor, 0.25)
        XCTAssertEqual(result(.tiny, steady: 0.5, audio: 0).realTimeFactor, 0)
    }

    func testRunRoundTripsThroughJSONWithISO8601Dates() throws {
        let saved = run([result(.tiny, wer: 0.25), .skipped(.medium, reason: BenchmarkSkipReason.couldNotLoad("boom"), thermalState: "fair")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(saved)
        let decoded = try decoder.decode(BenchmarkRun.self, from: data)
        XCTAssertEqual(decoded, saved)
        XCTAssertEqual(decoded.results[1].skippedReason, "couldn't load: boom")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"date\":\"2023-11-14T22:13:20Z\""))
    }

    func testReportTextIsTheMarkdownTable() {
        let saved = run([
            result(.tiny, load: 0.4, first: 0.9, steady: 0.3, audio: 3.8, wer: 1.0 / 7.0, before: 120, delta: 80),
            result(.small, load: 3.0, first: 1.2, steady: 0.9, audio: 3.8, wer: 0, before: 130, delta: 240),
            .skipped(.medium, reason: BenchmarkSkipReason.tooHot, thermalState: "serious"),
        ])
        let expected = """
        # ReVox benchmark · iPhone17,1 · iOS 26.0 · 8 GB · WhisperKit 1.1.0 · 2023-11-14T22:13:20Z

        Sentence (es): Buenos días, ¿dónde está la estación de tren?
        Reference: Good morning, where is the train station?

        | Model | Load s | First s | Steady s | Audio s | RTF | WER | Resident before MB | Peak delta MB | Thermal | Verdict |
        |---|---|---|---|---|---|---|---|---|---|---|
        | tiny | 0.4 | 0.9 | 0.3 | 3.8 | 0.08 | 0.14 | 120 | 80 | nominal | Keeps up |
        | small | 3 | 1.2 | 0.9 | 3.8 | 0.24 | 0.00 | 130 | 240 | nominal | Keeps up |
        | medium | – | – | – | – | – | – | – | – | serious | Skipped: iPhone too hot |

        """
        XCTAssertEqual(BenchmarkReport.markdown(saved), expected)
        XCTAssertEqual(BenchmarkReport.timestamp(fixedDate), "2023-11-14T22:13:20Z")
    }
}
