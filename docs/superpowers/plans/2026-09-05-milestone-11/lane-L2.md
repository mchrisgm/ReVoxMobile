## Lane L2: Unsure phrases and the History bar

Spec §3, §4, §7 row L2. Core first, proven on Linux; then the app, where CI is the compiler and every file is checked here with `swiftc -parse` only. Every code block below was built and run in a scratch copy of `ReVoxCore` (all 287 core tests green) or parsed with `swiftc -parse`; copy it as given. Run every core command from the repo root with `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter <Class>[.<test>]`; parse an app file with `/home/user/swift/usr/bin/swiftc -parse <absolute path>`.

**Files**
- Modify (core): `ReVoxCore/Sources/ReVoxCore/SpeechGate.swift`, `ReVoxCore/Sources/ReVoxCore/TranslationStage.swift`, `ReVoxCore/Sources/ReVoxCore/TranscriptFormatter.swift`, `ReVoxCore/Sources/ReVoxCore/Settings.swift`, `ReVoxCore/Sources/ReVoxCore/PipelineTypes.swift`, `ReVoxCore/Sources/ReVoxCore/TranslationPipeline.swift`, `ReVoxCore/Tests/ReVoxCoreTests/Fakes/FakeTranslator.swift`, `scripts/ci/check-constant-coverage.sh`, `docs/superpowers/specs/2026-09-02-revox-mobile-design.md` (deviation table only: rows W2 and W8)
- Modify (app): `ReVoxMobile/Storage/Entry.swift`, `ReVoxMobile/Storage/TranscriptStore.swift`, `ReVoxMobile/Storage/HistoryActions.swift`, `ReVoxMobile/Storage/TranscriptSearch.swift`, `ReVoxMobile/Screens/SessionSummary.swift`, `ReVoxMobile/Screens/SessionDetailRows.swift`, `ReVoxMobile/Screens/SessionDetailView.swift`, `ReVoxMobile/Screens/SessionRowView.swift`, `ReVoxMobile/Screens/HistoryView.swift`, `ReVoxMobile/Screens/LiveViewModel.swift` (two hunks only)
- Create (app): `ReVoxMobile/Screens/SettingsViewModel+Guesses.swift`, `ReVoxMobile/Screens/GuessesSettingsSection.swift`, `ReVoxMobile/Screens/SettingExample+Guesses.swift`
- Test (core): `ReVoxCore/Tests/ReVoxCoreTests/SpeechGateTests.swift`, `TranslationStageTests.swift`, `TranscriptFormatterTests.swift`, `TranscriptRecorderTests.swift`, `SettingsTests.swift`, `PipelineTypesTests.swift`, `TranslationPipelineTests.swift`
- Test (app): `ReVoxMobileTests/TranscriptStoreTests.swift`, `HistoryActionsTests.swift`, `SessionSummaryTests.swift`, `SessionDetailRowsTests.swift`, `TranscriptSearchTests.swift`, `LiveViewModelTests.swift`; new `ReVoxMobileTests/TranscriptMigrationTests.swift`, `ReVoxMobileTests/GuessHostingTests.swift`
- Not touched (other lanes): `LiveTranscriptRowView.swift`, `SettingsView.swift`, `SettingExample.swift`, `SettingsViewModel.swift`, `ScreenHostingTests.swift`, `ScreenshotTests.swift`, `RowAccessibilityTests.swift`, `SettingsViewModelTests.swift`.

**Interfaces**
- Consumes (seam commit / existing): `LiveTranscriptRow.init(id: UUID = UUID(), time: Date, kind: Kind, isGuess: Bool = false)` with `let isGuess: Bool`; `SettingsViewModel.store: SettingsStore` (internal) and `SettingsStore.update(_ change: (inout Settings) -> Void)`; `SettingExample(symbol: String, text: String, content:)`; `SettingExamples.sampleTime`, `.spanishEnglish`, `.sampleRow(original:)`; `LiveTranscriptRowView(row:now:timeDisplay:showsOriginal:romanizes:)`; `TranscriptContainer.make(inMemory:)`, `TranscriptContainer.storeName`; `SpokenText.clean(_:)`. Nothing from L1/L3/L4 in wave 1.
- Produces: `public enum LanguageOutcome: Sendable, Equatable { case confident, unsure, dropped }`; `public enum GateOutcome: Sendable, Equatable { case confident(Translation), guess(Translation), dropped }`; `SpeechGate.guessLogProbFloor: Float = -2.5`; `SpeechGate.languageOutcome(probability: Float?) -> LanguageOutcome`; `SpeechGate.classify(_ candidate: TranslationCandidate) -> GateOutcome`; `Translation.isGuess: Bool` (init `isGuess: Bool = false`); `TranscriptEntry.isGuess: Bool` (init `isGuess: Bool = false`); `TranscriptFormatter.guessPrefix = "(unsure) "`; `PipelineConfiguration.keepsGuesses: Bool = true` (init `keepsGuesses: Bool = true`); `Settings.keepGuesses: Bool = true` (key `keep_guesses`); `FakeTranslator(language:segments:segmentsPerCall:fail:blocked:)`; `Entry.isGuess: Bool = false` (init `isGuess: Bool = false` before `session`); `SessionSummary.guessCount: Int`, `.previewIsGuess: Bool`, `.guessCountText: String?`, `SessionSummary.guessSymbolName = "questionmark.circle"`; `SessionRowView.guessPreviewPrefix = "Unsure: "`, `SessionRowView.accessibilityText(for: SessionSummary) -> String`; `SettingsViewModel.keepGuesses: Bool`, `.guessesSectionTitle`, `.keepGuessesTitle`, `.keepGuessesHint`, `.keepGuessesHelpText`; `SettingExamples.keepGuesses(_ on: Bool) -> String`, `SettingExamples.guessRow: LiveTranscriptRow`; `struct GuessesSettingsSection: View { @Bindable var model: SettingsViewModel }`.

Commit trailer for every commit (use `git commit -F -` with a heredoc so the two lines end the message):
```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
```

### Task 1: SpeechGate.classify, LanguageOutcome, GateOutcome, guessLogProbFloor, Translation.isGuess

**Files:** Modify `ReVoxCore/Sources/ReVoxCore/SpeechGate.swift`, `scripts/ci/check-constant-coverage.sh`; Test `ReVoxCore/Tests/ReVoxCoreTests/SpeechGateTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `SpeechGateTests.swift`, after `testSegmentsAreStrippedBeforeTheyAreJoined` (the last method of `SpeechGateTests`, before its closing `}`) add:
```swift
    // MARK: Unsure phrases (M11, §3)

    /// Not a Windows constant: the floor under which a low-log-probability segment is noise rather than a guess.
    func testGuessLogProbFloor() {
        XCTAssertEqual(SpeechGate.guessLogProbFloor, -2.5)
        XCTAssertLessThan(SpeechGate.guessLogProbFloor, SpeechGate.averageLogProbMin)
    }

    func testLanguageOutcome() {
        XCTAssertEqual(SpeechGate.languageOutcome(probability: nil), .confident)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: 0.4), .confident)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: 0.39), .unsure)
        XCTAssertEqual(SpeechGate.languageOutcome(probability: .nan), .dropped)
        for probability in [nil, 0.4, 0.39, Float.nan] as [Float?] {
            XCTAssertEqual(SpeechGate.languagePasses(probability: probability),
                           SpeechGate.languageOutcome(probability: probability) == .confident, "\(String(describing: probability))")
        }
    }

    func testALowLogProbPhraseIsAGuessWithItsText() {
        let outcome = SpeechGate.classify(candidate([segment("noise", logProb: -2.0)]))
        XCTAssertEqual(outcome, .guess(Translation(english: "noise", language: "es", isGuess: true)))
    }

    func testAnUnsureLanguageIsAGuessEvenWithConfidentSegments() {
        let unsure = SpeechGate.classify(candidate([segment("text")], probability: 0.2))
        XCTAssertEqual(unsure, .guess(Translation(english: "text", language: "es", isGuess: true)))
        let pinned = SpeechGate.classify(candidate([segment("text")], probability: nil))
        XCTAssertEqual(pinned, .confident(Translation(english: "text", language: "es")))
    }

    /// The confident part alone is emitted, as today; the low part is discarded, never attached greyed.
    func testMixedSegmentsKeepOnlyTheConfidentPart() {
        let mixed = candidate([segment(" Hola."), segment("noise", logProb: -2.0)])
        XCTAssertEqual(SpeechGate.classify(mixed), .confident(Translation(english: "Hola.", language: "es")))
        XCTAssertEqual(SpeechGate.evaluate(mixed), Translation(english: "Hola.", language: "es"))
    }

    func testNoSpeechSegmentsNeverBecomeGuesses() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("ghost", noSpeech: 0.99, logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("ghost", noSpeech: 0.99, logProb: -0.3)])), .dropped)
    }

    /// `WhisperKitTranslator` reports −∞ for a segment with no word tokens: nothing to show, so never a guess.
    func testNoWordTokensIsNotAGuess() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("silent", logProb: -.infinity)])), .dropped)
        let mixed = SpeechGate.classify(candidate([segment("silent", logProb: -.infinity), segment("maybe", logProb: -2.0)]))
        XCTAssertEqual(mixed, .guess(Translation(english: "maybe", language: "es", isGuess: true)))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("odd", logProb: .nan)])), .dropped)
    }

    func testAGuessBelowTheFloorIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("static", logProb: -3.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("static", logProb: (-2.5 as Float).nextDown)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("edge", logProb: -2.5)])),
                       .guess(Translation(english: "edge", language: "es", isGuess: true)), "the floor itself is a guess")
    }

    func testAnEmptyOrWhitespaceGuessIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("   ", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("<|es|>", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([])), .dropped)
    }

    func testAHallucinationPhraseWithLowLogProbIsDropped() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment(" Thanks for watching! ", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("you.", logProb: -2.0)])), .dropped)
        XCTAssertEqual(SpeechGate.classify(candidate([segment("you.")], probability: 0.2)), .dropped)
    }

    func testGuessBoundaries() {
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept", logProb: -1.2)])), .confident(Translation(english: "kept", language: "es")))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept", logProb: (-1.2 as Float).nextDown)])),
                       .guess(Translation(english: "kept", language: "es", isGuess: true)))
        XCTAssertEqual(SpeechGate.classify(candidate([segment("kept")], probability: 0.4)), .confident(Translation(english: "kept", language: "es")))
    }

    func testAGuessIsCleanedAndJoinedLikeAConfidentPhrase() {
        let outcome = SpeechGate.classify(candidate([segment(" Uno ", logProb: -2.0), segment("<|es|> dos", logProb: -2.0)]))
        XCTAssertEqual(outcome, .guess(Translation(english: "Uno dos", language: "es", isGuess: true)))
    }

    /// The case and the payload's flag say the same thing, set in one place.
    func testClassifySetsTheFlagFromTheCase() {
        guard case .guess(let guess) = SpeechGate.classify(candidate([segment("maybe", logProb: -2.0)])) else {
            return XCTFail("expected a guess")
        }
        XCTAssertTrue(guess.isGuess)
        guard case .confident(let sure) = SpeechGate.classify(candidate([segment("sure")])) else {
            return XCTFail("expected a confident phrase")
        }
        XCTAssertFalse(sure.isGuess)
    }

    /// `evaluate` is the confident case of `classify`, by construction: for every table row the two agree.
    func testEvaluateIsTheConfidentCaseOfClassify() {
        let table: [TranslationCandidate] = [
            candidate([segment(" Hola."), segment(" Buenos días.")]),
            candidate([segment("ghost", noSpeech: 0.99)]),
            candidate([segment("noise", logProb: -2.0)]),
            candidate([segment(" Thanks for watching! ")]),
            candidate([segment("text")], probability: 0.2),
            candidate([segment("text")], probability: nil),
            candidate([segment("text")], probability: .nan),
            candidate([segment("   ", logProb: -0.3), segment("gone", logProb: -3)]),
            candidate([segment("\n Uno "), segment("\tdos\r\n"), segment("   ")]),
        ]
        for row in table {
            if let translation = SpeechGate.evaluate(row) {
                XCTAssertEqual(SpeechGate.classify(row), .confident(translation), "\(row)")
            } else if case .confident = SpeechGate.classify(row) {
                XCTFail("classify is confident where evaluate is nil: \(row)")
            }
        }
    }
```
In `TranslationCodableTests.testRoundTripKeepsEveryField` replace the line `XCTAssertEqual(Set(object.keys), ["english", "language", "spokenLanguage", "original"])` with `XCTAssertEqual(Set(object.keys), ["english", "language", "spokenLanguage", "original", "isGuess"])`, and add after that method:
```swift
    /// A record written before M11 has no `isGuess` and decodes as a confident phrase; the flag round-trips.
    func testRecordsWrittenBeforeM11DecodeAsConfident() throws {
        let decoder = JSONDecoder()
        let preM11 = try decoder.decode(Translation.self, from: Data(#"{"english":"hello","language":"es","spokenLanguage":"en","original":""}"#.utf8))
        XCTAssertFalse(preM11.isGuess)
        let null = try decoder.decode(Translation.self, from: Data(#"{"english":"hello","language":"es","isGuess":null}"#.utf8))
        XCTAssertFalse(null.isGuess)
        let guess = Translation(english: "maybe", language: "es", isGuess: true)
        let data = try JSONEncoder().encode(guess)
        XCTAssertEqual(try decoder.decode(Translation.self, from: data), guess)
        XCTAssertNotEqual(guess, Translation(english: "maybe", language: "es"), "the flag is part of equality")
    }
```
- [ ] **Step 2: Run** `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter "SpeechGateTests|TranslationCodableTests"` → compile error (`guessLogProbFloor`, `classify`, `isGuess` undefined).
- [ ] **Step 3: Implement.** In `SpeechGate.swift`, inside `Translation`: after `public var original: String` add
```swift
    /// M11: the gates were unsure (an auto-detected language below `SpeechGate.languageProbMin`, or only text
    /// between `guessLogProbFloor` and `averageLogProbMin`). Shown greyed, never spoken.
    public var isGuess: Bool
```
Replace the init signature `public init(english: String, language: String, spokenLanguage: String = "en", original: String = "") {` with `public init(english: String, language: String, spokenLanguage: String = "en", original: String = "", isGuess: Bool = false) {` and add `self.isGuess = isGuess` after `self.original = original`. Replace `case english, language, spokenLanguage, original` with `case english, language, spokenLanguage, original, isGuess`. In `init(from:)` add after the `original = …` line: `isGuess = try container.decodeIfPresent(Bool.self, forKey: .isGuess) ?? false`. Directly after the closing `}` of `Translation` add:
```swift
/// M11: what the language-probability gate made of a detection.
public enum LanguageOutcome: Sendable, Equatable {
    case confident, unsure, dropped
}

/// M11: what the gates made of a phrase. A `.guess` is shown greyed and never spoken; `.dropped` leaves no trace.
public enum GateOutcome: Sendable, Equatable {
    case confident(Translation)
    case guess(Translation)
    case dropped
}
```
After `public static let languageProbMin: Float = 0.4       // LANGUAGE_PROB_MIN` add:
```swift
    /// M11 (not a Windows constant): a segment whose average log-probability is below this is noise, not a guess.
    /// Between the floor and `averageLogProbMin` it is an unsure part; the escape hatch if unsure rows prove noisy.
    public static let guessLogProbFloor: Float = -2.5
```
Replace the whole of `languagePasses` and `evaluate` (from the doc comment `/// Windows: \`settings.language is None…` through the closing `}` of `evaluate`, i.e. up to but not including `/// Python \`str.strip()\``) with:
```swift
    /// Windows: `settings.language is None and info.language_probability < LANGUAGE_PROB_MIN` → drop. `nil` means
    /// the language was pinned and the gate is skipped. M11: below the minimum is `.unsure` (kept as a guess);
    /// a NaN, which no scorer should produce, is `.dropped` (the pinned deviation of `testANaNLanguageProbabilityIsDropped`).
    public static func languageOutcome(probability: Float?) -> LanguageOutcome {
        guard let probability else { return .confident }
        if probability.isNaN { return .dropped }
        return probability >= languageProbMin ? .confident : .unsure
    }

    /// Unchanged meaning: only a `.confident` detection passes.
    public static func languagePasses(probability: Float?) -> Bool {
        languageOutcome(probability: probability) == .confident
    }

    /// The full Windows sequence: language gate, per-segment gates, join, normalise, hallucination set. Since M11
    /// the confident case of `classify`, so the two can never disagree.
    public static func evaluate(_ candidate: TranslationCandidate) -> Translation? {
        if case .confident(let translation) = classify(candidate) { return translation }
        return nil
    }

    /// M11: the Windows sequence with a third outcome. A segment with no-speech above `noSpeechMax`, empty stripped
    /// text, or a log-probability that is not finite or below `guessLogProbFloor` is skipped; between the floor and
    /// `averageLogProbMin` it is an unsure part; at or above `averageLogProbMin` a confident part. Confident parts
    /// win when any exist (today's output, byte for byte); otherwise the unsure parts form a guess. An unsure
    /// language makes the phrase a guess whatever its parts. The hallucination set drops either.
    public static func classify(_ candidate: TranslationCandidate) -> GateOutcome {
        let languageIsUnsure: Bool
        switch languageOutcome(probability: candidate.languageProbability) {
        case .dropped: return .dropped
        case .unsure: languageIsUnsure = true
        case .confident: languageIsUnsure = false
        }
        var confidentParts: [String] = []
        var unsureParts: [String] = []
        for segment in candidate.segments {
            if segment.noSpeechProbability > noSpeechMax { continue }
            let text = pythonStrip(segment.text)
            if text.isEmpty { continue }
            let logProb = segment.averageLogProbability
            guard logProb.isFinite else { continue }                  // −∞: no word tokens, nothing to show
            if logProb >= averageLogProbMin {
                confidentParts.append(text)
            } else if logProb >= guessLogProbFloor {
                unsureParts.append(text)
            }
        }
        let parts = confidentParts.isEmpty ? unsureParts : confidentParts
        // The only text that leaves this function is what the voice says and what the transcript shows, so the
        // spoken-text guarantee is applied here rather than at each consumer (§5.3).
        let english = SpokenText.clean(parts.joined(separator: " "))
        if hallucinationPhrases.contains(normalize(english)) {
            return .dropped
        }
        let isGuess = languageIsUnsure || confidentParts.isEmpty
        let translation = Translation(english: english, language: candidate.language, isGuess: isGuess)
        return isGuess ? .guess(translation) : .confident(translation)
    }
```
In `scripts/ci/check-constant-coverage.sh`, directly after the line `SpeechGateTests.swift|XCTAssertEqual(SpeechGate.languageProbMin, 0.4)` add the line `SpeechGateTests.swift|XCTAssertEqual(SpeechGate.guessLogProbFloor, -2.5)`.
- [ ] **Step 4: Run** the Step 2 command → 30 tests pass; then `bash scripts/ci/check-constant-coverage.sh` → "All 65 ported constants are asserted".
- [ ] **Step 5: Commit**
```bash
git add ReVoxCore/Sources/ReVoxCore/SpeechGate.swift ReVoxCore/Tests/ReVoxCoreTests/SpeechGateTests.swift scripts/ci/check-constant-coverage.sh
git commit -F - <<'EOF'
feat(core): SpeechGate.classify — confident, guess or dropped, with evaluate derived from it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 2: TranslationStage.route and the deviation table (W2 retired for unsure, W8)

**Files:** Modify `ReVoxCore/Sources/ReVoxCore/TranslationStage.swift`, `docs/superpowers/specs/2026-09-02-revox-mobile-design.md`; Test `ReVoxCore/Tests/ReVoxCoreTests/TranslationStageTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `TranslationStageTests.swift` delete `testRejectsUnsureLanguageWhenAutoDetecting` (the whole method) and replace `testLowProbabilityAcceptedWithPin` with this block (it re-adds that test plus four new ones):
```swift
    /// M11 (W8): an unsure language is decoded and kept as an unspoken guess. Windows dropped it; so did the port
    /// until M11 (deviation W2, which is retired for this case).
    func testAnUnsureLanguageIsDecodedAndKeptAsAnUnspokenGuess() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "text", language: "es", isGuess: true))
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.isSpoken, false, "a guess is never spoken")
        let calls = await translator.calls
        XCTAssertEqual(calls.count, 1, "the translator runs for an unsure language now")
        let translation = try await stage.translate(audio)
        XCTAssertEqual(translation?.isGuess, true)
    }

    /// The one language score that still skips the decode: a NaN cannot be placed above or below any floor.
    func testANaNLanguageScoreIsDroppedBeforeTheTranslatorRuns() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: .nan)
        let translator = FakeTranslator(segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let result = try await stage.route(audio)
        XCTAssertNil(result)
        let calls = await translator.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testALowLogProbPhraseIsAnUnspokenGuess() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(segments: [
            TranslationSegment(text: " maybe", noSpeechProbability: 0.1, averageLogProbability: -2.0),
        ])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "maybe", language: "es", isGuess: true))
        XCTAssertEqual(routed?.route, .toEnglish)
        XCTAssertEqual(routed?.isSpoken, false)
    }

    func testLowProbabilityAcceptedWithPin() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(language: "fr", segments: [segment("text")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        let result = try await stage.translate(audio)
        XCTAssertEqual(result, Translation(english: "text", language: "fr"))
        XCTAssertEqual(result?.isGuess, false)
    }

    /// A pinned language is never detected, so the detector's doubt cannot make it a guess: the phrase is spoken.
    func testAPinnedLanguageNeverYieldsALanguageGuess() async throws {
        let detector = FakeLanguageDetector(language: "de", probability: 0.05)
        let translator = FakeTranslator(language: "fr", segments: [segment(" Yes.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: "fr")
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Yes.", language: "fr"))
        XCTAssertEqual(routed?.isSpoken, true)
        let detections = await detector.calls
        XCTAssertEqual(detections, 0)
    }
```
Directly before `func testAnotherLanguageIsStillTranslatedWhileALanguageIsIgnored()` add (uses the file's private `FakeTranscriber` / `FakeSecondary`):
```swift
    /// M11: an unsure detection may be the language the user asked ReVox to leave alone (the detector scored
    /// English as "de" at 0.3, say), so while a language is ignored it is dropped — with two-way off and on.
    func testAnUnsureDetectionIsDroppedWhileALanguageIsIgnored() async throws {
        for twoWay in [false, true] {
            let detector = FakeLanguageDetector(language: "de", probability: 0.3)
            let translator = FakeTranslator(language: "de", segments: [segment("must not be decoded")])
            let transcriber = FakeTranscriber(segments: [segment("must not be decoded either")])
            let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                         transcriber: transcriber, secondary: FakeSecondary(result: "unused"),
                                         ignoredLanguage: "en", twoWay: twoWay, targetLanguage: "es")
            let routed = try await stage.route(audio)
            XCTAssertNil(routed, "twoWay \(twoWay)")
            let languages = await translator.languages
            XCTAssertEqual(languages, [], "twoWay \(twoWay)")
            let transcribed = await transcriber.calls
            XCTAssertEqual(transcribed, [], "twoWay \(twoWay)")
        }
        // The unsure code equal to the ignored one is dropped too, not handed to the second direction.
        let detector = FakeLanguageDetector(language: "en", probability: 0.2)
        let transcriber = FakeTranscriber(segments: [segment(" Good morning.")])
        let stage = TranslationStage(detector: detector, translator: FakeTranslator(language: "en"), pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "Buenos días."),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertNil(routed)
        let transcribed = await transcriber.calls
        XCTAssertEqual(transcribed, [])
    }

    /// The second direction keeps using `evaluate`: nothing unsure is ever spoken to the other person.
    func testTheSecondDirectionNeverProducesAGuess() async throws {
        let detector = FakeLanguageDetector(language: "en", probability: 0.95)
        let low = TranslationSegment(text: " Good morning.", noSpeechProbability: 0.1, averageLogProbability: -2.0)
        let transcriber = FakeTranscriber(segments: [low])
        let stage = TranslationStage(detector: detector, translator: FakeTranslator(language: "en", segments: [low]), pinnedLanguage: nil,
                                     transcriber: transcriber, secondary: FakeSecondary(result: "Buenos días."),
                                     ignoredLanguage: "en", twoWay: true, targetLanguage: "es")
        let routed = try await stage.route(audio)
        XCTAssertNil(routed, "a low-log-probability transcription is dropped, not guessed")
        let intoEnglish = TranslationStage(detector: detector, translator: FakeTranslator(language: "en", segments: [low]), pinnedLanguage: nil,
                                           ignoredLanguage: "en", twoWay: true, targetLanguage: "en")
        let english = try await intoEnglish.route(audio)
        XCTAssertNil(english, "the English target path uses evaluate too")
    }
```
Directly before `func testATranscribeFailureCostsOnlyTheOriginal()` add:
```swift
    /// Doubtful audio is not decoded a second time: a guess has no original even with Learning on.
    func testALearningGuessIsNotTranscribedTwice() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.2)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed?.translation, Translation(english: "Good morning.", language: "es", original: "", isGuess: true))
        let calls = await transcriber.calls
        XCTAssertEqual(calls, [])
    }

    /// The confident path is exactly what it was before M11.
    func testAConfidentPhraseIsExactlyWhatItWas() async throws {
        let detector = FakeLanguageDetector(language: "es", probability: 0.95)
        let translator = FakeTranslator(language: "es", segments: [segment(" Good morning.")])
        let transcriber = FakeTranscriber(segments: [segment(" Buenos días.")])
        let stage = TranslationStage(detector: detector, translator: translator, pinnedLanguage: nil,
                                     transcriber: transcriber, wantsOriginal: true)
        let routed = try await stage.route(audio)
        XCTAssertEqual(routed, RoutedTranslation(translation: Translation(english: "Good morning.", language: "es", spokenLanguage: "en",
                                                                          original: "Buenos días.", isGuess: false),
                                                 route: .toEnglish, isSpoken: true))
    }
```
- [ ] **Step 2: Run** `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter TranslationStageTests` → `testAnUnsureLanguageIsDecodedAndKeptAsAnUnspokenGuess`, `testALowLogProbPhraseIsAnUnspokenGuess`, `testALearningGuessIsNotTranscribedTwice` fail (route still returns nil / isSpoken true).
- [ ] **Step 3: Implement.** In `TranslationStage.swift` replace the body of `route` — from `var detection: LanguageDetection?` through `return RoutedTranslation(translation: translation, route: .toEnglish, isSpoken: true)` — with:
```swift
        var detection: LanguageDetection?
        var languageIsUnsure = false
        let language: String
        if let pinnedLanguage {
            language = pinnedLanguage
        } else {
            let detected = try await detector.detectLanguage(in: audio)
            switch SpeechGate.languageOutcome(probability: detected.probability) {
            case .dropped: return nil                    // NaN: unscorable, never decoded
            case .unsure: languageIsUnsure = true        // M11 (W8): decoded anyway, kept as an unspoken guess
            case .confident: break
            }
            detection = detected
            language = detected.language
        }

        // M11: an unsure detection may be the language the user asked ReVox to leave alone — the M8 promise is
        // "not translated, not transcribed" — so while one is set the phrase is dropped in both two-way modes.
        if ignoredLanguage != nil, languageIsUnsure { return nil }

        // §8.2: the language the user asked ReVox to leave alone.
        if let ignoredLanguage, language == ignoredLanguage {
            guard twoWay else { return nil }             // not translated, not transcribed
            return try await secondDirection(audio, language: language, probability: detection?.probability)
        }

        var candidate = try await translator.translate(audio, language: language)
        candidate.languageProbability = detection?.probability
        switch SpeechGate.classify(candidate) {
        case .dropped:
            return nil
        case .guess(let translation):
            // No Learning transcribe pass for doubtful audio: the row shows no original, and the voice says nothing.
            return RoutedTranslation(translation: translation, route: .toEnglish, isSpoken: false)
        case .confident(var translation):
            translation.original = await originalIfWanted(audio, language: language, english: translation.english)
            return RoutedTranslation(translation: translation, route: .toEnglish, isSpoken: true)
        }
```
Replace the type doc comment sentence `tests mirror one-to-one. Deviation W2: when the language-probability gate fails the translator is not called.` with `tests mirror one-to-one. Deviation W2 (retired in M11 for an unsure language, W8): only a NaN language score` followed by a new line `/// skips the translator; an unsure one is decoded and kept as a guess.`.
In `docs/superpowers/specs/2026-09-02-revox-mobile-design.md` replace the W2 row (line 45, starting `| W2 |`) with:
```
| W2 | `TranslationStage` skips the translator when the language-probability gate fails (Windows got language and text from one call and discarded the text). Retired in M11 for an unsure score, which is decoded and kept as a guess (W8); only a NaN score still skips the translator. | Saves an encoder pass; the observable outcome (no entry, nothing spoken) is identical. | `TranslationStageTests.testANaNLanguageScoreIsDroppedBeforeTheTranslatorRuns` |
```
and after the W7 row (line 50, starting `| W7 |`) add:
```
| W8 | Unsure-language and low-log-probability phrases are kept as unspoken, greyed guesses instead of being dropped; Windows drops them (M11 `SpeechGate.classify`; a segment below `guessLogProbFloor` −2.5 is still dropped as noise). | Owner request 5 of M11: a phrase ReVox is unsure about should be readable, not lost; `Settings.keepGuesses` decides whether History keeps it. F8/F9 stay identical for confident output. | `TranslationStageTests.testAnUnsureLanguageIsDecodedAndKeptAsAnUnspokenGuess`, `SpeechGateTests.testALowLogProbPhraseIsAGuessWithItsText` |
```
- [ ] **Step 4: Run** the Step 2 command → 28 tests pass.
- [ ] **Step 5: Commit**
```bash
git add ReVoxCore/Sources/ReVoxCore/TranslationStage.swift ReVoxCore/Tests/ReVoxCoreTests/TranslationStageTests.swift docs/superpowers/specs/2026-09-02-revox-mobile-design.md
git commit -F - <<'EOF'
feat(core): an unsure language is decoded and kept as an unspoken guess (W8); dropped while a language is ignored

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 3: TranscriptEntry.isGuess and TranscriptFormatter.guessPrefix

**Files:** Modify `ReVoxCore/Sources/ReVoxCore/TranscriptFormatter.swift`; Test `ReVoxCore/Tests/ReVoxCoreTests/TranscriptFormatterTests.swift`, `ReVoxCore/Tests/ReVoxCoreTests/TranscriptRecorderTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `TranscriptFormatterTests.swift` replace `testTranscriptEntryRoundTripsThroughCodable` with:
```swift
    func testTranscriptEntryRoundTripsThroughCodable() throws {
        let entry = TranscriptEntry(timestamp: start, language: "es", original: "hola", english: "hello")
        let data = try JSONEncoder().encode(entry)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptEntry.self, from: data), entry)
        let guess = TranscriptEntry(timestamp: start, language: "es", original: "", english: "maybe", isGuess: true)
        let guessData = try JSONEncoder().encode(guess)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptEntry.self, from: guessData), guess)
        XCTAssertNotEqual(guess, TranscriptEntry(timestamp: start, language: "es", original: "", english: "maybe"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: guessData) as? [String: Any])
        XCTAssertEqual(object["isGuess"] as? Bool, true)
    }

    /// An entry written before M11 has no `isGuess` and decodes as a confident phrase.
    func testAPreM11EntryDecodesAsConfident() throws {
        let json = Data(#"{"timestamp":0,"language":"es","original":"","english":"hello"}"#.utf8)
        let entry = try JSONDecoder().decode(TranscriptEntry.self, from: json)
        XCTAssertEqual(entry, TranscriptEntry(timestamp: Date(timeIntervalSinceReferenceDate: 0), language: "es", original: "", english: "hello"))
        XCTAssertFalse(entry.isGuess)
    }

    // MARK: Unsure phrases (M11, §3)

    func testGuessPrefixAndLine() {
        XCTAssertEqual(TranscriptFormatter.guessPrefix, "(unsure) ")
        let formatter = TranscriptFormatter(timeZone: utc)
        let guess = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hello", isGuess: true)
        XCTAssertEqual(formatter.line(for: guess), "[22:13:21] [es] \n  → (unsure) hello\n")
        let sure = TranscriptEntry(timestamp: start.addingTimeInterval(1), language: "es", original: "hola", english: "hello")
        XCTAssertEqual(formatter.line(for: sure), "[22:13:21] [es] hola\n  → hello\n", "a confident line is unchanged")
    }

    /// The golden items plus a guess between the two consecutive markers: the guess resets the collapse, so both
    /// markers print, and the guess line carries the prefix. Everything else is the golden text, byte for byte.
    func testGoldenExportWithAGuessBetweenMarkers() {
        let formatter = TranscriptFormatter(timeZone: utc)
        let items: [TranscriptItem] = [
            .dropMarker(start.addingTimeInterval(1)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(1.5), language: "es", original: "", english: "hello", isGuess: true)),
            .dropMarker(start.addingTimeInterval(2)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3), language: "fr", original: "", english: "yes")),
            .dropMarker(start.addingTimeInterval(4)),
            .entry(TranscriptEntry(timestamp: start.addingTimeInterval(3_600 + 5), language: "es", original: "", english: "hello there")),
        ]
        let expected = """
        # ReVox session 2023-11-14T22:13:20
        [22:13:21] … (skipped: falling behind)
        [22:13:21] [es]\u{20}
          → (unsure) hello
        [22:13:22] … (skipped: falling behind)
        [22:13:23] [fr]\u{20}
          → yes
        [22:13:24] … (skipped: falling behind)
        [23:13:25] [es]\u{20}
          → hello there

        """
        let text = formatter.export(startedAt: start, items: items)
        XCTAssertEqual(text, expected)
        XCTAssertEqual(Array(text.utf8), Array(expected.utf8))
        XCTAssertEqual(text.components(separatedBy: "skipped: falling behind").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: TranscriptFormatter.guessPrefix).count - 1, 1)
    }
```
In `TranscriptRecorderTests.swift`, directly before `func testCloseIdempotent()` add:
```swift
    /// M11: a guess is an entry like any other to the recorder — stored with its flag, and it resets the drop flag.
    func testAGuessEntryIsRecordedAndResetsTheDropFlag() async {
        let recorder = makeRecorder()
        await recorder.addDropMarker(at: start.addingTimeInterval(1))
        await recorder.add(TranscriptEntry(timestamp: start.addingTimeInterval(2), language: "es", original: "", english: "maybe", isGuess: true))
        await recorder.addDropMarker(at: start.addingTimeInterval(3))
        let items = await recorder.items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1], .entry(TranscriptEntry(timestamp: start.addingTimeInterval(2), language: "es", original: "", english: "maybe", isGuess: true)))
        let text = await recorder.exportText()
        XCTAssertTrue(text.contains("  → (unsure) maybe\n"))
        XCTAssertEqual(text.components(separatedBy: "skipped: falling behind").count - 1, 2)
    }
```
- [ ] **Step 2: Run** `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter "TranscriptFormatterTests|TranscriptRecorderTests"` → compile error (`isGuess:`, `guessPrefix`).
- [ ] **Step 3: Implement.** In `TranscriptFormatter.swift` replace the whole `TranscriptEntry` struct with:
```swift
public struct TranscriptEntry: Sendable, Equatable, Codable {
    public var timestamp: Date
    public var language: String
    public var original: String          // "" unless Learning mode kept the words as spoken (M9; "" on Windows)
    public var english: String
    /// M11: the gates were unsure. Greyed in Live and History, "(unsure) " in the export, never spoken.
    public var isGuess: Bool

    public init(timestamp: Date, language: String, original: String, english: String, isGuess: Bool = false) {
        self.timestamp = timestamp
        self.language = language
        self.original = original
        self.english = english
        self.isGuess = isGuess
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, language, original, english, isGuess
    }

    /// An entry written before M11 has no `isGuess`; `encode(to:)` stays synthesised and writes every key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        language = try container.decode(String.self, forKey: .language)
        original = try container.decode(String.self, forKey: .original)
        english = try container.decode(String.self, forKey: .english)
        isGuess = try container.decodeIfPresent(Bool.self, forKey: .isGuess) ?? false
    }
}
```
After `public static let dropMarkerText = "… (skipped: falling behind)"      // U+2026` add:
```swift
    /// M11: the start of the English line of a guess. Windows never writes one; a session without guesses exports
    /// byte for byte as before.
    public static let guessPrefix = "(unsure) "
```
Replace `line(for:)` (its doc comment and body) with:
```swift
    /// "[HH:mm:ss] [<lang>] <original>\n  → <english>\n" (two spaces, U+2192, one space); a guess's English line
    /// starts with `guessPrefix`.
    public func line(for entry: TranscriptEntry) -> String {
        let prefix = entry.isGuess ? Self.guessPrefix : ""
        return "[\(stamp(entry.timestamp))] [\(entry.language)] \(entry.original)\n  → \(prefix)\(entry.english)\n"
    }
```
- [ ] **Step 4: Run** the Step 2 command → all pass (`testGoldenExport` untouched and green).
- [ ] **Step 5: Commit**
```bash
git add ReVoxCore/Sources/ReVoxCore/TranscriptFormatter.swift ReVoxCore/Tests/ReVoxCoreTests/TranscriptFormatterTests.swift ReVoxCore/Tests/ReVoxCoreTests/TranscriptRecorderTests.swift
git commit -F - <<'EOF'
feat(core): TranscriptEntry.isGuess and the "(unsure) " export line

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 4: Settings.keepGuesses (`keep_guesses`)

**Files:** Modify `ReVoxCore/Sources/ReVoxCore/Settings.swift`; Test `ReVoxCore/Tests/ReVoxCoreTests/SettingsTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `SettingsTests.testEncodedKeysAreWindowsSnakeCase` change the key list's last element from `"\"capture_mode\""` to `"\"capture_mode\"", "\"keep_guesses\""`. In `testExplicitNullsKeepTheOptionalsEmptyAndTheDefaultsForTheRest` replace `"two_way_language": null}"#` with `"two_way_language": null, "keep_guesses": null}"#`. After that method add:
```swift
    // MARK: Unsure phrases (M11)

    func testTheM11FieldDefaultsToKeepingGuesses() {
        XCTAssertTrue(Settings().keepGuesses, "History matches what Live showed unless the user turns it off")
    }

    func testTheM11FieldRoundTripsThroughSnakeCase() throws {
        var settings = Settings()
        settings.keepGuesses = false
        let data = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["keep_guesses"] as? Bool, false)
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: data), settings)
        XCTAssertNotEqual(settings, Settings(), "the field is part of equality")
    }

    /// A settings file written before M11 has no `keep_guesses` and keeps the default.
    func testASettingsFileFromBeforeM11Decodes() throws {
        let json = Data(#"{"model":"small","language":null,"voice":"alba","ducking":true,"learning":true}"#.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertTrue(settings.keepGuesses)
        XCTAssertTrue(settings.learning)
        XCTAssertEqual(SettingsCodec.decode(Data(#"{"keep_guesses": false}"#.utf8)).keepGuesses, false)
    }
```
- [ ] **Step 2: Run** `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter SettingsTests` → compile error (`keepGuesses`).
- [ ] **Step 3: Implement.** In `Settings.swift` after `public var timeDisplay: String = TimeDisplay.age.rawValue` add:
```swift
    /// M11: keep the phrases the gates were unsure about in History and the export. They are always shown on the
    /// Live screen and never spoken; this only decides whether the session keeps them. Applied at the next Start.
    public var keepGuesses: Bool = true
```
After `case timeDisplay = "time_display"` add `case keepGuesses = "keep_guesses"`. After `timeDisplay = try container.decodeIfPresent(String.self, forKey: .timeDisplay) ?? timeDisplay` add `keepGuesses = try container.decodeIfPresent(Bool.self, forKey: .keepGuesses) ?? keepGuesses`. After `try container.encode(timeDisplay, forKey: .timeDisplay)` add `try container.encode(keepGuesses, forKey: .keepGuesses)`.
- [ ] **Step 4: Run** the Step 2 command → all pass; `bash scripts/ci/check-constant-coverage.sh` still green (no asserted line moved).
- [ ] **Step 5: Commit**
```bash
git add ReVoxCore/Sources/ReVoxCore/Settings.swift ReVoxCore/Tests/ReVoxCoreTests/SettingsTests.swift
git commit -F - <<'EOF'
feat(core): Settings.keepGuesses (keep_guesses), default on

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 5: PipelineConfiguration.keepsGuesses, PipelineActor.record, FakeTranslator(segmentsPerCall:)

**Files:** Modify `ReVoxCore/Sources/ReVoxCore/PipelineTypes.swift`, `ReVoxCore/Sources/ReVoxCore/TranslationPipeline.swift`, `ReVoxCore/Tests/ReVoxCoreTests/Fakes/FakeTranslator.swift`; Test `ReVoxCore/Tests/ReVoxCoreTests/PipelineTypesTests.swift`, `ReVoxCore/Tests/ReVoxCoreTests/TranslationPipelineTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `PipelineTypesTests.swift`, `PipelineConfigurationTests.testDefaults`: after `XCTAssertEqual(configuration.duckingHoldNanoseconds, 250_000_000)` add `XCTAssertTrue(configuration.keepsGuesses, "M11: guesses reach History unless the setting says otherwise")`. In `testConfigurationEqualityCoversTheM8AndM9Fields`, after the final `XCTAssertNotEqual(base, other)` (the `.veryFast` one) add:
```swift
        other = base
        other.keepsGuesses = false
        XCTAssertNotEqual(base, other)
        XCTAssertEqual(PipelineConfiguration(captureMode: .microphone, preset: .balanced, keepsGuesses: false), other)
```
In `TranslationPipelineTests.testHappyPathTranslatesAndSpeaks`, after `XCTAssertEqual(entries.first?.original, "")` add `XCTAssertEqual(entries.first?.isGuess, false)`. Directly before the doc comment of `testTranscriptOnlyEventCarriesTheReason` add:
```swift
    // MARK: Unsure phrases (M11, §3)

    private func guessSegments() -> [TranslationSegment] {
        [TranslationSegment(text: " maybe", noSpeechProbability: 0, averageLogProbability: -2.0)]
    }

    private func confidentSegments() -> [TranslationSegment] {
        [TranslationSegment(text: " sure", noSpeechProbability: 0, averageLogProbability: -0.1)]
    }

    /// The entry that carries `isGuess` in the collected events, if any.
    private func guessEntry(in events: EventCollector) -> TranscriptEntry? {
        for event in events.events {
            if case .entry(let entry) = event, entry.isGuess { return entry }
        }
        return nil
    }

    func testAGuessReachesTheTranscriptAndTheEntryEventButNeverTheVoice() async throws {
        let h = makeHarness(translator: FakeTranslator(segments: guessSegments()))
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let recorded = await eventually { await h.transcript.entries.isEmpty == false }
        XCTAssertTrue(recorded)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.english, "maybe")
        XCTAssertEqual(entries.first?.isGuess, true, "with the default configuration a guess is kept")
        let emitted = await eventually { self.guessEntry(in: h.events) != nil }
        XCTAssertTrue(emitted, "\(h.events.events)")
        _ = await eventually(timeout: 0.5) { await h.speaker.texts.isEmpty == false }
        let spoken = await h.speaker.texts
        XCTAssertTrue(spoken.isEmpty, "a guess is never spoken")
        let enqueued = await h.player?.enqueued ?? []
        XCTAssertTrue(enqueued.isEmpty)
        XCTAssertFalse(h.events.events.contains { if case .transcriptOnly = $0 { return true }; return false },
                       "a guess is not a transcript-only phrase; the Live note must not fire")
        await h.pipeline.stop()
    }

    /// With `keepsGuesses` off the guess still reaches the `.entry` event (the Live screen shows it) but not the
    /// sink; the confident phrase behind it reaches both and is spoken.
    func testWithKeepsGuessesOffAGuessReachesTheEventButNotTheSink() async throws {
        let h = makeHarness(translator: FakeTranslator(segmentsPerCall: [guessSegments(), confidentSegments()]))
        var config = configuration()
        config.keepsGuesses = false
        await h.pipeline.start(config)
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let spoke = await eventually { await h.speaker.texts.isEmpty == false }
        XCTAssertTrue(spoke)
        let spoken = await h.speaker.texts
        XCTAssertEqual(spoken, ["sure"], "only the confident phrase is spoken")
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.map(\.english), ["sure"], "the guess never reached the sink")
        XCTAssertEqual(entries.first?.isGuess, false)
        let guess = guessEntry(in: h.events)
        XCTAssertEqual(guess?.english, "maybe", "the Live screen still gets the guess: \(h.events.events)")
        await h.pipeline.stop()
    }

```
- [ ] **Step 2: Run** `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter "PipelineConfigurationTests|PipelineTypesProtocolTests|TranslationPipelineTests"` → compile error (`keepsGuesses`, `segmentsPerCall`).
- [ ] **Step 3: Implement.** `PipelineTypes.swift`: after `public var wantsOriginal: Bool = false` add
```swift
    /// M11: write guesses to the transcript sink as well as showing them live. Rebuilt at every Start from
    /// `Settings.keepGuesses`, so a cached pipeline still honours the current value.
    public var keepsGuesses: Bool = true
```
change the init's last parameter `wantsOriginal: Bool = false) {` to `wantsOriginal: Bool = false,` + new line `keepsGuesses: Bool = true) {`, and after `self.wantsOriginal = wantsOriginal` add `self.keepsGuesses = keepsGuesses`.
`TranslationPipeline.swift`: after `private var captureGate = CaptureGate()` add
```swift
    /// M11: this run's `PipelineConfiguration.keepsGuesses`; read by `record`.
    private var keepsGuesses = true
```
In `performStart`, after `queue = BoundedSegmentQueue(capacity: configuration.maxPending)` add `keepsGuesses = configuration.keepsGuesses`. Delete `recordTranslation` entirely (the three lines `func recordTranslation(_ result: Translation, run: Int) async { … }` and the blank line after; it has no callers). Replace the doc comment and first lines of `record` — from `/// M8: a phrase the second direction could transcribe` through `events.yield(.entry(entry))` — with:
```swift
    /// M8: a phrase the second direction could transcribe but not translate is kept in the transcript and not
    /// spoken, so a two-way conversation still shows both sides even where no engine can reach the target.
    /// M11: a guess always reaches the `.entry` event (the Live screen shows it), reaches the transcript sink only
    /// while the run keeps guesses, and is never spoken (`isSpoken` is false for every guess).
    func record(_ routed: RoutedTranslation, run: Int) async {
        guard running, run == runID else { return }
        let result = routed.translation
        let entry = TranscriptEntry(timestamp: dependencies.clock(), language: result.language,
                                    original: result.original, english: result.english, isGuess: result.isGuess)
        if keepsGuesses || !entry.isGuess {
            await transcript?.add(entry)
        }
        events.yield(.entry(entry))
```
`FakeTranslator.swift`: replace the type doc comment and the stored properties/init (from `/// The Windows \`FakeTranslator\`` through the closing `}` of `init`) with:
```swift
/// The Windows `FakeTranslator`: a gate that blocks `translate` until opened, a `fail` flag, records of every call.
/// Returns "text-N" for the N-th call unless explicit segments were given. M11: `segmentsPerCall` scripts the
/// segments call by call (consumed in order, then `segments` / "text-N" as before).
actor FakeTranslator: Translator {
    private let language: String
    private let segments: [TranslationSegment]?
    private var segmentsPerCall: [[TranslationSegment]]
    private let fail: Bool
    private var open: Bool
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private(set) var calls: [[Float]] = []
    private(set) var languages: [String] = []

    init(language: String = "es", segments: [TranslationSegment]? = nil, segmentsPerCall: [[TranslationSegment]]? = nil,
         fail: Bool = false, blocked: Bool = false) {
        self.language = language
        self.segments = segments
        self.segmentsPerCall = segmentsPerCall ?? []
        self.fail = fail
        open = !blocked
    }
```
and in `translate` replace the line `let produced = segments ?? [TranslationSegment(text: "text-\(calls.count)", noSpeechProbability: 0, averageLogProbability: 0)]` with:
```swift
        let produced: [TranslationSegment]
        if !segmentsPerCall.isEmpty {
            produced = segmentsPerCall.removeFirst()
        } else {
            produced = segments ?? [TranslationSegment(text: "text-\(calls.count)", noSpeechProbability: 0, averageLogProbability: 0)]
        }
```
- [ ] **Step 4: Run** the Step 2 command → all pass; then the whole core: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore` → all pass (287 tests).
- [ ] **Step 5: Commit**
```bash
git add ReVoxCore/Sources/ReVoxCore/PipelineTypes.swift ReVoxCore/Sources/ReVoxCore/TranslationPipeline.swift ReVoxCore/Tests/ReVoxCoreTests/Fakes/FakeTranslator.swift ReVoxCore/Tests/ReVoxCoreTests/PipelineTypesTests.swift ReVoxCore/Tests/ReVoxCoreTests/TranslationPipelineTests.swift
git commit -F - <<'EOF'
feat(core): keepsGuesses — a guess reaches the Live event always, the sink only when kept, the voice never

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 6: Entry.isGuess with the on-disk migration test, TranscriptStore

**Files:** Modify `ReVoxMobile/Storage/Entry.swift`, `ReVoxMobile/Storage/TranscriptStore.swift`; Test create `ReVoxMobileTests/TranscriptMigrationTests.swift`, modify `ReVoxMobileTests/TranscriptStoreTests.swift`. CI is the compiler: `swiftc -parse` only.

- [ ] **Step 1: Write the failing tests.** Create `ReVoxMobileTests/TranscriptMigrationTests.swift`:
```swift
import XCTest
import SwiftData
@testable import ReVoxMobile

/// The schema as it was before M11 (§6.10): the same two entities, `Entry` without `isGuess`. Nested in a
/// `VersionedSchema` so the entity names ("Session", "Entry") match the app's and the store's.
enum PreM11Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Session.self, Entry.self] }

    @Model
    final class Session {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var endedAt: Date?
        var captureMode: String
        var pinnedLanguage: String?
        var modelID: String
        var voice: String
        var joinedInProgress: Bool
        @Relationship(deleteRule: .cascade, inverse: \Entry.session) var entries: [Entry]

        init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, captureMode: String, pinnedLanguage: String?,
             modelID: String, voice: String, joinedInProgress: Bool, entries: [Entry] = []) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.captureMode = captureMode
            self.pinnedLanguage = pinnedLanguage
            self.modelID = modelID
            self.voice = voice
            self.joinedInProgress = joinedInProgress
            self.entries = entries
        }
    }

    @Model
    final class Entry {
        var timestamp: Date
        var language: String
        var original: String
        var english: String
        var isDropMarker: Bool
        var session: Session?

        init(timestamp: Date, language: String, original: String, english: String, isDropMarker: Bool, session: Session? = nil) {
            self.timestamp = timestamp
            self.language = language
            self.original = original
            self.english = english
            self.isDropMarker = isDropMarker
            self.session = session
        }
    }
}

/// M11 adds `Entry.isGuess`. Every TestFlight iPhone has an on-disk "ReVoxTranscripts" store whose rows lack it,
/// and `AppEnvironment.live()` opens that store with a bare `try` at launch — so the lightweight migration is
/// proved here on a real file rather than on the first TestFlight run: a store written with the pre-M11 schema
/// is reopened with the app's schema and every old row reads back as a confident phrase. The in-memory
/// containers of the other tests never exercise this path.
///
/// If a 17.0/17.1 tester ever reports a launch failure here, the fallback is `var isGuess: Bool?` read as `== true`.
@MainActor
final class TranscriptMigrationTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appendingPathComponent("\(TranscriptContainer.storeName).store") }

    /// Writes a pre-M11 store and lets its container go out of scope before the app's schema opens the file.
    private func seedPreM11Store() throws {
        let schema = Schema(versionedSchema: PreM11Schema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let session = PreM11Schema.Session(startedAt: start, endedAt: start.addingTimeInterval(30), captureMode: "microphone",
                                           pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        let rows = [
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(1), language: "es", original: "", english: "hola", isDropMarker: false),
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(2), language: "", original: "", english: "", isDropMarker: true),
            PreM11Schema.Entry(timestamp: start.addingTimeInterval(3), language: "ja", original: "おはよう", english: "Good morning.", isDropMarker: false),
        ]
        for row in rows {
            row.session = session
            context.insert(row)
        }
        try context.save()
    }

    func testAStoreFromBeforeM11OpensWithTheAppSchemaAndItsRowsAreConfident() throws {
        try seedPreM11Store()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), "the pre-M11 store is on disk")

        let schema = Schema([Session.self, Entry.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].modelID, "small")
        let rows = sessions[0].entries.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(rows.map(\.english), ["hola", "", "Good morning."])
        XCTAssertEqual(rows.map(\.isDropMarker), [false, true, false])
        XCTAssertEqual(rows.map(\.isGuess), [false, false, false], "the lightweight migration filled the new column with the default")
        XCTAssertEqual(rows[2].original, "おはよう")

        // The migrated store takes new rows with the flag and reads them back.
        let guess = Entry(timestamp: start.addingTimeInterval(4), language: "es", original: "", english: "quizás", isDropMarker: false, isGuess: true)
        guess.session = sessions[0]
        context.insert(guess)
        try context.save()
        let reread = try ModelContext(container).fetch(FetchDescriptor<Entry>(predicate: #Predicate<Entry> { $0.isGuess }))
        XCTAssertEqual(reread.map(\.english), ["quizás"])
    }
}
```
In `TranscriptStoreTests.swift` replace `testExportTextEqualsFormatterOverPersistedEntries` with:
```swift
    func testExportTextEqualsFormatterOverPersistedEntries() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "es", original: "", english: "hola"))
        await store.addDropMarker(at: startedAt.addingTimeInterval(2))
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(2.5), language: "es", original: "", english: "quizás", isGuess: true))
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(3), language: "es", original: "", english: "adiós"))
        await store.close()

        let expected = await store.exportText()
        let session = try fetchSessions()[0]
        let rebuilt = TranscriptFormatter().export(startedAt: session.startedAt, items: TranscriptStore.items(from: entries(of: session)))
        XCTAssertEqual(rebuilt, expected, "the recorder's export and the Entry-based export agree, guess included")
        XCTAssertTrue(expected.hasPrefix(TranscriptFormatter.headerPrefix))
        XCTAssertTrue(expected.contains("  → hola\n"))
        XCTAssertTrue(expected.contains("  → \(TranscriptFormatter.guessPrefix)quizás\n"), "M11: the guess line carries the prefix")
        XCTAssertEqual(expected.components(separatedBy: TranscriptFormatter.dropMarkerText).count - 1, 1)
    }

    /// M11: a guess persists with its flag and reads back through a second context; a confident row stays false.
    func testAGuessIsPersistedWithItsFlag() async throws {
        let store = TranscriptStore(modelContainer: container, metadata: metadata())
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "es", original: "", english: "maybe", isGuess: true))
        await store.add(TranscriptEntry(timestamp: startedAt.addingTimeInterval(2), language: "es", original: "", english: "sure"))
        await store.flush()
        let rows = entries(of: try fetchSessions()[0])
        XCTAssertEqual(rows.map(\.english), ["maybe", "sure"])
        XCTAssertEqual(rows.map(\.isGuess), [true, false])
        XCTAssertEqual(rows.map(\.isDropMarker), [false, false])
        let items = TranscriptStore.items(from: rows)
        XCTAssertEqual(items.first, .entry(TranscriptEntry(timestamp: startedAt.addingTimeInterval(1), language: "es", original: "", english: "maybe", isGuess: true)))
    }
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/TranscriptMigrationTests.swift && /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/TranscriptStoreTests.swift` → both parse; on CI they would fail to compile until Step 3 (`Entry` has no `isGuess:`).
- [ ] **Step 3: Implement.** In `Entry.swift` replace from `    var isDropMarker: Bool` through the closing `}` of `init` with:
```swift
    var isDropMarker: Bool
    /// M11: a phrase the gates were unsure about; greyed in Session detail, "(unsure) " in the export. The default
    /// is what SwiftData's lightweight migration writes into every row of a store from before M11
    /// (`TranscriptMigrationTests`), so no `VersionedSchema` or migration plan is needed.
    var isGuess: Bool = false
    var session: Session?

    init(timestamp: Date, language: String, original: String, english: String, isDropMarker: Bool, isGuess: Bool = false, session: Session? = nil) {
        self.timestamp = timestamp
        self.language = language
        self.original = original
        self.english = english
        self.isDropMarker = isDropMarker
        self.isGuess = isGuess
        self.session = session
    }
```
In `TranscriptStore.swift`, in `add`, replace `let row = Entry(timestamp: entry.timestamp, language: entry.language, original: entry.original, english: entry.english, isDropMarker: false)` with:
```swift
        let row = Entry(timestamp: entry.timestamp, language: entry.language, original: entry.original, english: entry.english,
                        isDropMarker: false, isGuess: entry.isGuess)
```
and in `items(from:)` replace `return .entry(TranscriptEntry(timestamp: row.timestamp, language: row.language, original: row.original, english: row.english))` with:
```swift
            return .entry(TranscriptEntry(timestamp: row.timestamp, language: row.language, original: row.original, english: row.english,
                                          isGuess: row.isGuess))
```
- [ ] **Step 4: Run** `for f in ReVoxMobile/Storage/Entry.swift ReVoxMobile/Storage/TranscriptStore.swift; do /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/$f; done` → both parse.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Storage/Entry.swift ReVoxMobile/Storage/TranscriptStore.swift ReVoxMobileTests/TranscriptMigrationTests.swift ReVoxMobileTests/TranscriptStoreTests.swift
git commit -F - <<'EOF'
feat(app): Entry.isGuess with the pre-M11 on-disk migration proved; the store carries the flag

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 7: HistoryActions.merge keeps the flag; search never returns a guess

**Files:** Modify `ReVoxMobile/Storage/HistoryActions.swift`, `ReVoxMobile/Storage/TranscriptSearch.swift`; Test `ReVoxMobileTests/HistoryActionsTests.swift`, `ReVoxMobileTests/TranscriptSearchTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `HistoryActionsTests.testMergeMakesOneSessionInTimeOrderAndRemovesTheOriginals` replace the comment line `// A drop marker in the middle session, and an end time only on the last, to prove both survive.` with `// A drop marker in the middle session, an unsure phrase in the first (M11), and an end time only on the` + newline `// last, to prove all three survive.`; after `context.insert(marker)` add:
```swift
        let guess = Entry(timestamp: sessions[0].startedAt.addingTimeInterval(1.5), language: "es", original: "", english: "unsure 0", isDropMarker: false, isGuess: true)
        guess.session = sessions[0]
        context.insert(guess)
```
then change `XCTAssertEqual(after.entries, 7, "6 lines plus the marker, copied, and the originals' rows cascaded away")` to `XCTAssertEqual(after.entries, 8, "6 lines plus the marker and the guess, copied, and the originals' rows cascaded away")`; change the `lines.map(\.english)` expectation to `["line 0.1", "unsure 0", "line 0.2", "line 1.1", "", "line 1.2", "line 2.1", "line 2.2"]`; after `XCTAssertEqual(lines.filter(\.isDropMarker).count, 1)` add `XCTAssertEqual(lines.filter(\.isGuess).map(\.english), ["unsure 0"], "M11: merging keeps the flag")`; change `XCTAssertEqual(merged.entries.count, 7)` to `XCTAssertEqual(merged.entries.count, 8)`.
In `TranscriptSearchTests.seed()`, before `try context.save()` add:
```swift
        let guess = Entry(timestamp: older.startedAt.addingTimeInterval(0.7), language: "es", original: "",
                          english: "good morning guessed", isDropMarker: false, isGuess: true)
        guess.session = older
        context.insert(guess)
```
and extend the `seed()` doc comment with `/// M11: the row at offset 0.7 is a guess in the same position, and \`!entry.isGuess\` is load-bearing the same way.`; after `seed()` add:
```swift
    /// M11: a guess is never a hit, and never the earliest matching line of its session.
    func testUnsurePhrasesAreNeverSearchHits() throws {
        let guessed = try TranscriptSearch.hits(query: "guessed", in: ModelContext(container))
        XCTAssertTrue(guessed.hits.isEmpty, "a guess never matches, even when its text contains the query")
        let morning = try TranscriptSearch.hits(query: "morning", in: ModelContext(container))
        XCTAssertEqual(morning.hits.count, 2)
        XCTAssertEqual(morning.hits[1].matchingLine, "good morning everyone",
                       "the guess sorts before the first confident match of its session and is skipped")
        let descriptor = FetchDescriptor<Entry>(predicate: TranscriptSearch.fallbackPredicate(query: "guessed"))
        let fallback = try ModelContext(container).fetch(descriptor)
        XCTAssertTrue(fallback.isEmpty, "the fallback predicate excludes guesses too")
    }
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/HistoryActionsTests.swift && /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/TranscriptSearchTests.swift` → parse; on CI `testUnsurePhrasesAreNeverSearchHits` and the merge assertion would fail until Step 3.
- [ ] **Step 3: Implement.** `HistoryActions.merge`: replace `english: row.english, isDropMarker: row.isDropMarker)` with `english: row.english, isDropMarker: row.isDropMarker, isGuess: row.isGuess)`. `TranscriptSearch.swift`: in both predicates replace `!entry.isDropMarker && entry.english` with `!entry.isDropMarker && !entry.isGuess && entry.english`, and append to the enum's doc comment: ` M11: a guess` / `/// is never a hit — a hit is shown out of context as plain text, and a guess is text ReVox does not vouch for.`
- [ ] **Step 4: Run** `for f in ReVoxMobile/Storage/HistoryActions.swift ReVoxMobile/Storage/TranscriptSearch.swift; do /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/$f; done` → parse.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Storage/HistoryActions.swift ReVoxMobile/Storage/TranscriptSearch.swift ReVoxMobileTests/HistoryActionsTests.swift ReVoxMobileTests/TranscriptSearchTests.swift
git commit -F - <<'EOF'
feat(app): merge keeps the unsure flag; search never returns a guess

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 8: SessionSummary, SessionDetailRows, the Unsure header row, the guess preview

**Files:** Modify `ReVoxMobile/Screens/SessionSummary.swift`, `ReVoxMobile/Screens/SessionDetailRows.swift`, `ReVoxMobile/Screens/SessionDetailView.swift`, `ReVoxMobile/Screens/SessionRowView.swift`; Test `ReVoxMobileTests/SessionSummaryTests.swift`, `ReVoxMobileTests/SessionDetailRowsTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `SessionSummaryTests.swift`, directly before `func testCountsExcludeDropMarkersAndFirstLineIsTheEarliestEntry()` add:
```swift
    /// M11: the same shape with the guess flag instead of the drop flag.
    private func sessionWithGuesses(_ entries: [(offset: TimeInterval, english: String, isGuess: Bool)]) throws -> Session {
        let session = Session(startedAt: start, captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        for entry in entries {
            let row = Entry(timestamp: start.addingTimeInterval(entry.offset), language: "es", original: "", english: entry.english,
                            isDropMarker: false, isGuess: entry.isGuess)
            row.session = session
            context.insert(row)
        }
        try context.save()
        return session
    }

```
and directly before `func testDurationTextFormats()` add:
```swift
    // MARK: Unsure phrases (M11)

    func testGuessesCountAsEntriesButNeverAsThePreviewWhileAConfidentLineExists() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "maybe", true), (2, "first", false), (3, "perhaps", true)]))
        XCTAssertEqual(summary.entryCount, 3)
        XCTAssertEqual(summary.entryCountText, "3 entries")
        XCTAssertEqual(summary.guessCount, 2)
        XCTAssertEqual(summary.guessCountText, "2 unsure phrases")
        XCTAssertEqual(summary.firstEnglishLine, "first", "the earliest confident line, not the earliest line")
        XCTAssertEqual(summary.previewText, "first")
        XCTAssertFalse(summary.previewIsGuess)
        XCTAssertFalse(SessionRowView.accessibilityText(for: summary).contains(SessionRowView.guessPreviewPrefix))
    }

    func testASessionOfOnlyGuessesPreviewsAGuessAndSaysSo() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "maybe", true)]))
        XCTAssertEqual(summary.guessCountText, "1 unsure phrase")
        XCTAssertEqual(summary.previewText, "maybe")
        XCTAssertTrue(summary.previewIsGuess)
        XCTAssertTrue(SessionRowView.accessibilityText(for: summary).hasSuffix(". Unsure: maybe."))
        XCTAssertEqual(SessionRowView.guessPreviewPrefix, "Unsure: ")
        XCTAssertEqual(SessionSummary.guessSymbolName, "questionmark.circle")
    }

    func testASessionWithoutGuessesHasNoUnsureRow() throws {
        let summary = SessionSummary(session: try sessionWithGuesses([(1, "sure", false)]))
        XCTAssertEqual(summary.guessCount, 0)
        XCTAssertNil(summary.guessCountText, "no guesses, no row")
        XCTAssertFalse(summary.previewIsGuess)
        XCTAssertTrue(SessionRowView.accessibilityText(for: summary).hasSuffix(". sure."))
    }

```
In `SessionDetailRowsTests.testRowsFollowTimestampOrderAndMapMarkers` change the first row to `Entry(timestamp: start.addingTimeInterval(5), language: "de", original: "", english: "later", isDropMarker: false, isGuess: true),` and after the `mapped.map(\.kind)` assertion add `XCTAssertEqual(mapped.map(\.isGuess), [false, false, true], "M11: the flag rides along")`. In `testSingleRowMapping` after `XCTAssertEqual(row.kind, .entry(language: "fr", english: "yes"))` add `XCTAssertFalse(row.isGuess)`, and after `XCTAssertEqual(marker.kind, .dropMarker)` add:
```swift
        let guess = SessionDetailRows.row(for: Entry(timestamp: start, language: "fr", original: "", english: "maybe", isDropMarker: false, isGuess: true))
        XCTAssertEqual(guess.kind, .entry(language: "fr", english: "maybe"))
        XCTAssertTrue(guess.isGuess, "M11: History greys a guess as Live did")
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/SessionSummaryTests.swift && /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/SessionDetailRowsTests.swift` → parse; would not compile on CI until Step 3.
- [ ] **Step 3: Implement.** `SessionSummary.swift`: after `static let noEntriesText = "Nothing translated"` add
```swift
    /// M11: the symbol beside an unsure phrase — the History row's preview and the Settings example.
    static let guessSymbolName = "questionmark.circle"
```
replace `    let dropCount: Int` + `    let firstEnglishLine: String?` with
```swift
    let dropCount: Int
    /// M11: how many entries the gates were unsure about. They count as entries — the user chose to keep them.
    let guessCount: Int
    let firstEnglishLine: String?
    /// M11: true when the preview line is a guess, which happens only when the session holds nothing confident.
    let previewIsGuess: Bool
```
replace `        firstEnglishLine = entries.first?.english` with
```swift
        guessCount = entries.filter(\.isGuess).count
        let preview = entries.first { !$0.isGuess } ?? entries.first
        firstEnglishLine = preview?.english
        previewIsGuess = preview?.isGuess ?? false
```
and before `    var previewText: String { firstEnglishLine ?? Self.noEntriesText }` add
```swift
    /// M11: the unsure phrases as a count for the Session detail header; nil when there were none, so the row is absent.
    var guessCountText: String? {
        switch guessCount {
        case 0: return nil
        case 1: return "1 unsure phrase"
        default: return "\(guessCount) unsure phrases"
        }
    }

```
`SessionDetailRows.row(for:)` becomes:
```swift
    static func row(for entry: Entry) -> LiveTranscriptRow {
        LiveTranscriptRow(time: entry.timestamp,
                          kind: entry.isDropMarker ? .dropMarker : .entry(language: entry.language, original: entry.original, english: entry.english),
                          isGuess: entry.isGuess)   // M11: History greys a guess exactly as Live did
    }
```
`SessionDetailView.swift`: after the `if let skipped = summary.dropCountText { … }` block add
```swift
                if let unsure = summary.guessCountText {
                    headerRow("Unsure", value: unsure)     // M11: explains the greyed rows below
                }
```
`SessionRowView.swift`: after `static let dateStyle = …` add
```swift
    /// M11: said before a preview that is a guess — the italic and the symbol are the visible cue, this is the spoken one.
    static let guessPreviewPrefix = "Unsure: "
```
replace the preview `Text(summary.previewText) … .foregroundStyle(summary.firstEnglishLine == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))` (four lines) with `previewLine`, replace `.accessibilityLabel(accessibilityText)` with `.accessibilityLabel(Self.accessibilityText(for: summary))`, and replace `private var accessibilityText: String { … }` with:
```swift
    /// M11: a session that holds only guesses previews one — secondary italic with the Unsure symbol inline, so it
    /// is never mistaken for a confident line. A confident preview is exactly what it was.
    @ViewBuilder
    private var previewLine: some View {
        if summary.previewIsGuess {
            (Text(Image(systemName: SessionSummary.guessSymbolName)) + Text(" \(summary.previewText)"))
                .font(.body.italic())
                .lineLimit(2)
                .foregroundStyle(.secondary)
        } else {
            Text(summary.previewText)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(summary.firstEnglishLine == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
    }

    /// The row's one VoiceOver sentence; pure, so the tests read it without a host.
    static func accessibilityText(for summary: SessionSummary) -> String {
        var parts = [
            "Session \(summary.startedAt.formatted(Self.dateStyle))",
            summary.sourceTitle,
            "\(summary.durationText) long",
            summary.entryCountText,
        ]
        if summary.joinedInProgress { parts.append("joined in progress") }
        parts.append(summary.previewIsGuess ? guessPreviewPrefix + summary.previewText : summary.previewText)
        return parts.joined(separator: ". ") + "."
    }
```
- [ ] **Step 4: Run** `for f in SessionSummary SessionDetailRows SessionDetailView SessionRowView; do /home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobile/Screens/$f.swift; done` → parse.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Screens/SessionSummary.swift ReVoxMobile/Screens/SessionDetailRows.swift ReVoxMobile/Screens/SessionDetailView.swift ReVoxMobile/Screens/SessionRowView.swift ReVoxMobileTests/SessionSummaryTests.swift ReVoxMobileTests/SessionDetailRowsTests.swift
git commit -F - <<'EOF'
feat(app): History counts, previews and greys unsure phrases

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 9: LiveViewModel — keepsGuesses in the configuration, the guess row

**Files:** Modify `ReVoxMobile/Screens/LiveViewModel.swift` (two hunks only); Test `ReVoxMobileTests/LiveViewModelTests.swift`.

- [ ] **Step 1: Write the failing tests.** In `LiveViewModelTests.testEntryEventAppendsOnMainActor` after `XCTAssertTrue(model.lastEventHandledOnMainThread)` add `XCTAssertFalse(model.rows[0].isGuess)`, then add after that method:
```swift
    /// M11: a guess appends a greyed row, leaves `detectedLanguage` alone (the language itself is the doubt) and,
    /// like any entry, clears the paused-by-iOS status because audio is demonstrably flowing.
    func testAGuessEntryAppendsAGreyedRowAndLeavesTheDetectedLanguageAlone() async {
        let model = makeModel()
        await model.start()
        await waitUntil { model.state == .running }
        first.emit(.entry(TranscriptEntry(timestamp: Date(), language: "de", original: "", english: "hi")))
        await waitUntil("confident row") { model.rows.count == 1 }
        model.handle(SessionEvent.pausedByIOS)
        XCTAssertEqual(model.sessionStatus, LiveViewModel.pausedByIOSText)
        first.emit(.entry(TranscriptEntry(timestamp: Date(), language: "fr", original: "", english: "maybe", isGuess: true)))
        await waitUntil("guess row") { model.rows.count == 2 }
        XCTAssertEqual(model.rows[1].kind, .entry(language: "fr", english: "maybe"))
        XCTAssertTrue(model.rows[1].isGuess)
        XCTAssertEqual(model.detectedLanguage, "de", "an unsure language does not become the detected one")
        XCTAssertNil(model.sessionStatus, "audio is flowing, so the paused-by-iOS status clears")
    }
```
In `testConfigurationMirrorsSettingsIncludingDucking` after the last line `XCTAssertFalse(LiveViewModel.configuration(settings: settings, captureMode: .microphone).duckingEnabled)` add:
```swift
        XCTAssertTrue(configuration.keepsGuesses, "M11 default: History keeps unsure phrases")
        settings.keepGuesses = false
        XCTAssertFalse(LiveViewModel.configuration(settings: settings, captureMode: .microphone).keepsGuesses)
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/LiveViewModelTests.swift` → parses; on CI the two tests would fail until Step 3.
- [ ] **Step 3: Implement.** In `configuration(settings:captureMode:)` after the line `configuration.wantsOriginal = settings.learning           // M9 Learning mode` add `configuration.keepsGuesses = settings.keepGuesses         // M11: applies at the next Start, like Learning`. In `handle(_ event: PipelineEvent)`, case `.entry`, replace the two lines
```swift
            detectedLanguage = entry.language
            rows.append(LiveTranscriptRow(time: entry.timestamp, kind: .entry(language: entry.language, original: entry.original, english: entry.english)))
```
with
```swift
            if !entry.isGuess { detectedLanguage = entry.language }   // M11: the language itself may be the doubt
            rows.append(LiveTranscriptRow(time: entry.timestamp, kind: .entry(language: entry.language, original: entry.original, english: entry.english),
                                          isGuess: entry.isGuess))
```
Nothing else in the file changes (L1 owns its two-way region).
- [ ] **Step 4: Run** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobile/Screens/LiveViewModel.swift` → parses.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Screens/LiveViewModel.swift ReVoxMobileTests/LiveViewModelTests.swift
git commit -F - <<'EOF'
feat(app): Live shows a guess row and passes keepsGuesses at every Start

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 10: The Unsure phrases setting — view-model extension, example copy, section view, GuessHostingTests

**Files:** Create `ReVoxMobile/Screens/SettingsViewModel+Guesses.swift`, `ReVoxMobile/Screens/SettingExample+Guesses.swift`, `ReVoxMobile/Screens/GuessesSettingsSection.swift`; Test create `ReVoxMobileTests/GuessHostingTests.swift`.

- [ ] **Step 1: Write the failing tests.** Create `ReVoxMobileTests/GuessHostingTests.swift`:
```swift
import XCTest
import SwiftUI
import SwiftData
import ReVoxCore
@testable import ReVoxMobile

/// M11 (§3, §4): the unsure-phrase surfaces and the History edit bar host and lay out, and the setting's binding
/// and copy are exact. Hosting in a `UIHostingController` is the only proof there is for SwiftUI here.
@MainActor
final class GuessHostingTests: XCTestCase {
    private var root: URL!
    private var store: SettingsStore!
    private let said = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxGuesses-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = SettingsStore(fileURL: root.appendingPathComponent(SettingsCodec.fileName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func host<V: View>(_ view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    private var exporter: TranscriptExporter { TranscriptExporter(directory: root.appendingPathComponent("exports", isDirectory: true)) }

    /// A guess row beside a confident one, with and without an original, at the default and the largest size.
    func testAGuessRowHostsAtEverySize() {
        let rows = [
            LiveTranscriptRow(time: said, kind: .entry(language: "es", english: "Where is the station?")),
            LiveTranscriptRow(time: said.addingTimeInterval(4), kind: .entry(language: "fr", english: "Maybe tomorrow."), isGuess: true),
            LiveTranscriptRow(time: said.addingTimeInterval(5), kind: .entry(language: "ja", original: "おはよう", english: "Good morning."), isGuess: true),
        ]
        for size in [DynamicTypeSize.large, .accessibility5] {
            host(List {
                ForEach(rows) { row in
                    LiveTranscriptRowView(row: row, now: said.addingTimeInterval(12), timeDisplay: .both, showsOriginal: true, romanizes: true)
                }
            }
            .environment(\.dynamicTypeSize, size))
        }
        host(List { ForEach(rows) { LiveTranscriptRowView(row: $0) } })
    }

    func testSessionDetailAndTheHistoryRowHostAGuess() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        let session = Session(startedAt: said, endedAt: said.addingTimeInterval(30), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "alba", joinedInProgress: false)
        context.insert(session)
        let guess = Entry(timestamp: said.addingTimeInterval(1), language: "es", original: "", english: "Where is the exit?", isDropMarker: false, isGuess: true)
        guess.session = session
        context.insert(guess)
        try context.save()
        let summary = SessionSummary(session: session)
        XCTAssertEqual(summary.guessCountText, "1 unsure phrase", "the header's Unsure row is present")
        XCTAssertTrue(summary.previewIsGuess)
        host(NavigationStack { SessionDetailView(session: session, exporter: exporter) }.modelContainer(container))
        host(List { SessionRowView(summary: summary) })
        host(List { SessionRowView(summary: summary) }.environment(\.dynamicTypeSize, .accessibility5))
    }

    func testTheSettingsSectionHostsAndTheBindingWritesTheStore() {
        let model = SettingsViewModel(store: store, mute: PlaybackMute(), voiceVolume: VoiceVolume(), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(model.keepGuesses, "default on")
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } })
        model.keepGuesses = false
        XCTAssertFalse(store.settings.keepGuesses)
        XCTAssertFalse(SettingsStore(fileURL: store.fileURL).settings.keepGuesses, "written to disk")
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } })
        host(NavigationStack { Form { GuessesSettingsSection(model: model) } }.environment(\.dynamicTypeSize, .accessibility5))
    }

    func testTheCopyIsExact() {
        XCTAssertEqual(SettingsViewModel.guessesSectionTitle, "Unsure phrases")
        XCTAssertEqual(SettingsViewModel.keepGuessesTitle, "Keep unsure phrases in History")
        XCTAssertEqual(SettingsViewModel.keepGuessesHint, "Keeps phrases ReVox was unsure about in History as well as on the Live screen")
        XCTAssertEqual(SettingsViewModel.keepGuessesHelpText,
                       "When ReVox is not sure of the language or the words, the phrase is shown greyed and marked Unsure on the Live screen and is never spoken aloud. With this on, those phrases are also kept in History and in the exported file, marked (unsure). A change takes effect the next time you tap Start.")
        XCTAssertEqual(SettingExamples.keepGuesses(true),
                       "An unsure phrase stays in the session, greyed and marked Unsure, so you can read what ReVox thought it heard.")
        XCTAssertEqual(SettingExamples.keepGuesses(false),
                       "An unsure phrase is shown on the Live screen only. History keeps the phrases ReVox was sure of.")
        XCTAssertTrue(SettingExamples.guessRow.isGuess)
        XCTAssertFalse(SettingExamples.sampleRow().isGuess)
        XCTAssertEqual(SettingExamples.guessRow.kind, .entry(language: "es", original: "", english: SettingExamples.spanishEnglish))
        XCTAssertNotEqual(SettingExamples.guessRow.id, SettingExamples.sampleRow().id, "its own identity in a Form")
    }
}
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/GuessHostingTests.swift` → parses; would not compile on CI until Step 3.
- [ ] **Step 3: Implement.** Create `ReVoxMobile/Screens/SettingsViewModel+Guesses.swift`:
```swift
import Foundation
import ReVoxCore

/// M11 (§3): the Unsure phrases setting, in its own file so the milestone's lanes land without editing
/// `SettingsViewModel.swift` (`store` is internal for exactly this).
extension SettingsViewModel {
    /// `Settings.keepGuesses`; read by `LiveViewModel.configuration` at the next Start.
    var keepGuesses: Bool {
        get { store.settings.keepGuesses }
        set { store.update { $0.keepGuesses = newValue } }
    }

    static let guessesSectionTitle = "Unsure phrases"
    static let keepGuessesTitle = "Keep unsure phrases in History"
    static let keepGuessesHint = "Keeps phrases ReVox was unsure about in History as well as on the Live screen"
    static let keepGuessesHelpText = "When ReVox is not sure of the language or the words, the phrase is shown greyed and marked Unsure on the Live screen and is never spoken aloud. With this on, those phrases are also kept in History and in the exported file, marked (unsure). A change takes effect the next time you tap Start."
}
```
Create `ReVoxMobile/Screens/SettingExample+Guesses.swift`:
```swift
import Foundation

/// M11 (§3): the copy and the sample row of the Unsure phrases setting.
extension SettingExamples {
    static func keepGuesses(_ on: Bool) -> String {
        on ? "An unsure phrase stays in the session, greyed and marked Unsure, so you can read what ReVox thought it heard."
           : "An unsure phrase is shown on the Live screen only. History keeps the phrases ReVox was sure of."
    }

    /// The Spanish sample row as a guess: what the Live screen and History show for an unsure phrase.
    static let guessRow = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, time: sampleTime,
                                            kind: .entry(language: "es", original: "", english: spanishEnglish), isGuess: true)
}
```
Create `ReVoxMobile/Screens/GuessesSettingsSection.swift`:
```swift
import SwiftUI

/// M11 (§3): the Unsure phrases section of Settings — the toggle, the greyed sample row as its example and the
/// footer. Its own view, so the Settings screen only has to place it (directly under Source language).
struct GuessesSettingsSection: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Section {
            Toggle(SettingsViewModel.keepGuessesTitle, isOn: $model.keepGuesses)
                .accessibilityHint(SettingsViewModel.keepGuessesHint)
            SettingExample(symbol: SessionSummary.guessSymbolName, text: SettingExamples.keepGuesses(model.keepGuesses)) {
                LiveTranscriptRowView(row: SettingExamples.guessRow)
            }
        } header: {
            Text(SettingsViewModel.guessesSectionTitle)
        } footer: {
            Text(SettingsViewModel.keepGuessesHelpText)
        }
    }
}
```
- [ ] **Step 4: Run** `for f in SettingsViewModel+Guesses SettingExample+Guesses GuessesSettingsSection; do /home/user/swift/usr/bin/swiftc -parse "/home/user/ReVoxMobile/ReVoxMobile/Screens/$f.swift"; done` → parse; `python3 scripts/dev/check-core-imports.py --all` → clean.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Screens/SettingsViewModel+Guesses.swift ReVoxMobile/Screens/SettingExample+Guesses.swift ReVoxMobile/Screens/GuessesSettingsSection.swift ReVoxMobileTests/GuessHostingTests.swift
git commit -F - <<'EOF'
feat(app): the Unsure phrases setting — Keep unsure phrases in History, its example and footer

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 11: The History Merge / Delete bar as a safeAreaInset, and the final gates

**Files:** Modify `ReVoxMobile/Screens/HistoryView.swift`; Test `ReVoxMobileTests/GuessHostingTests.swift`.

- [ ] **Step 1: Write the failing test.** In `GuessHostingTests`, after `testTheCopyIsExact` add:
```swift
    /// §4: the edit bar is laid out in the real shape — a NavigationStack inside a TabView — and on its own.
    func testHistoryInEditModeHostsInsideATabView() throws {
        let container = try TranscriptContainer.make(inMemory: true)
        let context = ModelContext(container)
        for offset in [0.0, 120.0] {
            let session = Session(startedAt: said.addingTimeInterval(offset), endedAt: said.addingTimeInterval(offset + 10), captureMode: "microphone", pinnedLanguage: nil, modelID: "small", voice: "system", joinedInProgress: false)
            context.insert(session)
            let entry = Entry(timestamp: said.addingTimeInterval(offset + 1), language: "es", original: "", english: "hola", isDropMarker: false)
            entry.session = session
            context.insert(entry)
        }
        try context.save()
        host(TabView {
            NavigationStack { HistoryView(exporter: exporter, editing: true) }
                .tabItem { Label("History", systemImage: "clock") }
        }.modelContainer(container))
        host(NavigationStack { HistoryView(exporter: exporter, editing: true) }.modelContainer(container))
        host(NavigationStack { HistoryView(initialQuery: "hola", exporter: exporter, editing: true) }.modelContainer(container))   // bar hidden while searching
        XCTAssertEqual(HistoryView.mergeButtonTitle(count: 2), "Merge (2)")
        XCTAssertEqual(HistoryView.deleteButtonTitle(count: 2), "Delete (2)")
    }
```
- [ ] **Step 2: Run** (CI is the compiler: swiftc -parse only) `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobileTests/GuessHostingTests.swift` → parses (it hosts today's toolbar version too; the change in Step 3 is what §4 asks for).
- [ ] **Step 3: Implement.** In `HistoryView.swift` delete the whole `ToolbarItemGroup(placement: .bottomBar) { … }` block from `.toolbar { … }` (from `ToolbarItemGroup(placement: .bottomBar) {` through its closing `}`, the 13 lines ending with `.accessibilityHint("Deletes the selected sessions after a confirmation")` + `}` + `}`), leaving the two `ToolbarItem`s. Then replace the end of `sessionList` — `.onDelete(perform: deleteRows)   // unconfirmed: a common single-row action (§8.6)` + `}` + `}` — with:
```swift
            .onDelete(perform: deleteRows)   // unconfirmed: a common single-row action (§8.6)
        }
        // M11 (§4): the Merge / Delete bar is content in the safe area, not a `.bottomBar` toolbar item. Inside
        // RootView's TabView a bottom bar whose items appear only in edit mode was drawn under the tab bar on the
        // owner's iPhone; an inset is laid out above whatever the tab bar controller has already reserved.
        .safeAreaInset(edge: .bottom) {
            // Hidden while searching: the results list has no selection, so the bar would act on rows the
            // reader cannot see.
            if editMode.isEditing && !isSearching {
                editBar
            }
        }
    }

    /// The M9 bar — same titles, hints and disabled rules — as 44 pt plain buttons over a bar material with a hairline.
    private var editBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button { confirmingMerge = true } label: {
                    Text(Self.mergeButtonTitle(count: selection.count)).frame(minHeight: 44)
                }
                .disabled(selection.count < 2)
                .accessibilityHint("Combines the selected sessions into one, in time order")
                Spacer()
                Button(role: .destructive) { confirmingDeleteSelected = true } label: {
                    Text(Self.deleteButtonTitle(count: selection.count)).frame(minHeight: 44)
                }
                .disabled(selection.isEmpty)
                .accessibilityHint("Deletes the selected sessions after a confirmation")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }
```
- [ ] **Step 4: Run** `/home/user/swift/usr/bin/swiftc -parse /home/user/ReVoxMobile/ReVoxMobile/Screens/HistoryView.swift` → parses. Then the whole gate set: `python3 scripts/dev/check-core-imports.py --all && python3 scripts/dev/check-test-autoclosures.py && python3 scripts/dev/check-tests-are-discoverable.py && bash scripts/ci/check-constant-coverage.sh && /home/user/swift/usr/bin/swift test --package-path ReVoxCore` → all clean, core all green; `grep -rn "recordTranslation" ReVoxCore` → no hits.
- [ ] **Step 5: Commit**
```bash
git add ReVoxMobile/Screens/HistoryView.swift ReVoxMobileTests/GuessHostingTests.swift
git commit -F - <<'EOF'
fix(app): History's Merge / Delete bar is a safe-area inset above the tab bar

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

**Cross-lane needs**
- L5 (wave 2, `SettingsView.swift`): insert `GuessesSettingsSection(model: model)` directly after the Source language `Section` (before "Skip a language" / "Your language").
- L5 (`LiveTranscriptRowView.swift`): the Unsure caption (`questionmark.circle`, "Unsure"), italic secondary English and the "Unsure translation" VoiceOver text of spec §3; `SessionSummary.guessSymbolName` is available to reuse. `RowAccessibilityTests` for those constants are L5's.
- L1 (`SettingsView.swift`, `SettingExample.swift`): the Source language footer and `SettingExamples.sourceLanguageAuto` rewording of spec §1's last table row ("shown greyed and marked Unsure… never spoken"); this lane does not touch either file.
- L5 (`ScreenshotTests.swift`): a guess entry in the `live-running` frame if the README image should show a greyed row; `history-selecting` keeps its name and needs no change.
- L7 (README, spec prose): the "Unsure phrases" feature bullet, the History and Transcripts paragraphs ("(unsure) " lines while the setting keeps them; Windows never writes them), and §5.3/§6.10/§8 prose; this lane only edits the deviation table (W2, W8).
- L4 (`docs/hig-audit/checks.json`): Merge and Delete bar targets (44 pt) if the audit tooling wants rows for them.