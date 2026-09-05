## Lane L3: On-device benchmark and measured recommendations

Work in the lane worktree `/home/user/ReVoxMobile/.claude/worktrees/m11-L3` (branch `m11-L3`, at f35dba3 — L1 and L2 are already merged; none of L3's files changed in those merges). Paths below are relative to that root. Every file this lane creates or modifies already exists as a **verified copy** under `/home/user/ReVoxMobile/.claude/plans/m11-L3/files/<same relative path>` (Swift: `swiftc -parse` clean; ReVoxCore: `swift test` on Linux passes, 318 tests; the four gate scripts pass on a merged copy of HEAD). `/home/user/ReVoxMobile/.claude/plans/m11-L3/plan.md` inlines every file and every diff for reading; `/home/user/ReVoxMobile/.claude/plans/m11-L3/*.diff` are unified diffs against HEAD for the modified files. Each implement step below is therefore "copy the verified file" (`cp`) or "apply the verified diff" (`git apply`), with the load-bearing code quoted.

**Files**

Create (ReVoxCore, Linux-tested):
- `ReVoxCore/Sources/ReVoxCore/WordErrorRate.swift`
- `ReVoxCore/Sources/ReVoxCore/ModelBenchmark.swift`
- `ReVoxCore/Tests/ReVoxCoreTests/WordErrorRateTests.swift`
- `ReVoxCore/Tests/ReVoxCoreTests/ModelBenchmarkTests.swift`

Create (app, `ReVoxMobile/Benchmark/`): `BenchmarkTranslating.swift`, `BenchmarkStimulus.swift`, `BenchmarkRunner.swift`, `BenchmarkStore.swift`, `BenchmarkViewModel.swift`, `BenchmarkView.swift`

Create (docs): `docs/measurements/m11-model-benchmark.md`

Modify: `ReVoxCore/Sources/ReVoxCore/DeviceRecommendation.swift` (append an extension), `ReVoxMobile/Screens/ModelRow.swift`, `ReVoxMobile/Screens/ModelRowView.swift`, `ReVoxMobile/Screens/ModelsViewModel.swift`, `ReVoxMobile/Screens/ModelsView.swift`, `ReVoxMobile/App/AppEnvironment.swift` (benchmark wiring only)

Test files: `ReVoxCore/Tests/ReVoxCoreTests/DeviceRecommendationTests.swift` (extend), `ReVoxMobileTests/Support/FakeBenchmarkSeams.swift` (new), `ReVoxMobileTests/BenchmarkStimulusTests.swift`, `BenchmarkRunnerTests.swift`, `BenchmarkStoreTests.swift`, `BenchmarkViewModelTests.swift`, `BenchmarkHostingTests.swift` (new; hosts `BenchmarkView`, `ModelsView` with the entry row, and asserts the `AppEnvironment` wiring), `ReVoxMobileTests/ModelsViewModelTests.swift` (extend)

**Interfaces**

Consumes (existing code and the seam commit; nothing from other lanes):
- `actor WhisperKitTranslator { init(engine: WhisperEngine); init(layout: ModelLayout, model: WhisperModelID); static let preparingMessage; func load(progress: @escaping @Sendable (String) -> Void) async throws; func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate; func unload() async }` and `struct WhisperEngine { load, detect, transcribe, unload }` (fake per model in tests)
- `public protocol Speaker { func synthesize(_ text: String, language: String) async throws -> AudioClip }`; `actor SystemSpeaker: Speaker { init(voiceIdentifier: String?, synthesize: Synthesis? = nil); static func hasVoice(for language: String) -> Bool }` (the production one uses `SpeechWriteCollector`); `enum SpeakerError { case noVoice }`
- `PCMConverterDriver.pipelineFormat`, `PCMConverterDriver.convertToMono(_:with:endOfStream:)`, `AVAudioPCMBuffer.mono(samples:format:)`, `enum PCMConversionError`
- `enum MemoryMeter { static func residentBytes() -> UInt64? }`; `ProcessInfo.ThermalState`
- `public enum SpeechGate { static func evaluate(_ candidate: TranslationCandidate) -> Translation? }`, `Translation.english`, `TranslationCandidate`, `AudioClip`, `AudioFormat.pipelineSampleRate`, `WhisperModelID` (`displayName`, `rawValue`), `ModelCatalog.whisperModels`, `DeviceRecommendation.forPhysicalMemory(bytes:)`
- `ModelManager { var installedWhisper: [WhisperModelID]; var hasActiveDownload: Bool; func isWhisperReady(_:) async -> Bool; func delete(_:activeModel:) throws }`, `protocol InstallHost { beginBackgroundTask(name:expiration:) -> Int; endBackgroundTask(_:); var isIdleTimerDisabled }`, `LibraryVersions.whisperKit`, `ModelLayout.rootFolderName`, `DeviceInfo.memoryTierGB`, `LanguageCatalog.displayName(_:whenNil:)`, `UserFacingErrorText.describe(_:)`
- `LiveViewModel.releaseCachedPipeline() async`, `EffectiveSpeaker.unloadPocketTTS()` (actor), `SpeakerAssembly.speaker`, `typealias PipelineSupplier`, `LiveViewModel.recover`'s `case nil: banner = .error(String(describing: error))`
- Test support: `LockedBox`, `FakeInstallSteps.fabricateWhisper(_:in:)` / `holdDownloads`, `FakeInstallHost` (`begun`, `ended`, `idleTimerHistory`, `expireAll()`), `VerifiedLoadRecord(defaults:)`, `waitUntil`, `waitFor`, `FakeLivePipeline()`, `Settings()`

Produces (nothing another wave-1 lane needs; wave 2 may use):
- `public enum WordErrorRate { words(_:) -> [String]; editDistance(_:_:) -> Int; rate(reference:hypothesis:) -> Double; accuracy(reference:hypothesis:) -> Double }`
- `public struct BenchmarkSentence { language, text, reference }`, `public enum BenchmarkSentences { spanish, french, german, english, preferred, first(spokenBy:) }`, `public enum BenchmarkSkipReason { tooHot = "iPhone too hot"; cancelled = "cancelled"; couldNotLoad(_:); couldNotTranslate(_:) }`
- `public struct ModelBenchmarkResult: Codable, Identifiable { model, loadSeconds, firstSeconds, steadySeconds, audioSeconds, realTimeFactor, wordErrorRate, residentBeforeMB, peakDeltaMB, thermalState, skippedReason: String?, hypothesis; isSkipped; static func skipped(_:reason:thermalState:) }`
- `public struct BenchmarkRun: Codable { date, device, iOSVersion, memoryTierGB, whisperKitVersion, sentence, results; measured; result(for:) }`
- `public enum BenchmarkVerdict { speedText(realTimeFactor:), loadText(seconds:), accuracyText(wordErrorRate:), memoryText(megabytes:), line(_:), summaryText(_:) ("Keeps up" / "Too slow for live use" / "Slow to load" / "Skipped: …"), summarySymbol(_:), spokenSpeedText, spokenLoadText, spokenMemoryText, spokenText(_:), dateText(_:timeZone:) ("14 November 2023"), oneDecimal, twoDecimals }`, `public enum BenchmarkReport { markdown(_:) -> String; row(_:); timestamp(_:) }`
- `extension DeviceRecommendation { static let maxRealTimeFactor = 0.5; static let maxLoadSeconds = 10.0; static func qualifies(_:) -> Bool; static func bestMeasured(memory:results:) -> WhisperModelID?; static func measured(memory:results:) -> DeviceRecommendation }`
- App: `protocol BenchmarkTranslating` (+ `extension WhisperKitTranslator: BenchmarkTranslating {}`), `struct BenchmarkStimulus`, `enum BenchmarkError { noSpeech, busy, liveBlocked, nothingMeasured(String) }` (`liveBlocked.description == "Finish or cancel the benchmark in Settings › Models before starting"`), `struct BenchmarkStimulusFactory { init(speaker: any Speaker, hasVoice:); static func production(); func make() async throws; static func samples16k(from:) throws }`, `enum BenchmarkProgress`, `struct BenchmarkSeams { static func production(layout:) }`, `struct BenchmarkOutcome`, `actor BenchmarkRunner { static let passes = 2; init(seams:); func run(models:progress:) async throws -> BenchmarkOutcome; static thermalText, isTooHot, seconds }`, `struct BenchmarkHost { device, iOSVersion, memoryTierGB; static current(deviceInfo:processInfo:) }`, `@MainActor @Observable final class BenchmarkStore { init(directory:host:whisperKitVersion:); static folderName = "Benchmarks"; static defaultDirectory(); static fileName(for:); runs; latest; save(_:) }`, `@MainActor @Observable final class BenchmarkViewModel { static title = "Benchmark", linkTitle = "Benchmark this iPhone", linkHint, every screen string; init(store:manager:isPipelineRunning:releasePipeline:runner:host:timeZone:); state: BenchmarkRunState; isRunning; canRun; whyNotText; rows; shareText; resultsFooterText; lastRunText; start(); cancel(); static rows(for:), statusText(_:), footerText(run:languageName:timeZone:), lastRunText(run:timeZone:), stoppedEarlyText(measured:of:) }`, `struct BenchmarkView { @Bindable var model: BenchmarkViewModel }`, `struct BenchmarkRowView`
- `ModelRow.measuredNote: String? = nil` (appended last, defaulted: the 8 memberwise sites keep compiling); `ModelRowView.accessibilityText` appends it after "Recommended"/not-recommended, before the percent (the four verbatim sentences of `RowAccessibilityTests` unchanged)
- `ModelsViewModel.init(manager:settings:deviceInfo:isPipelineRunning:benchmarks: BenchmarkStore? = nil, isBenchmarkRunning: @escaping @MainActor () -> Bool = { false })`; `var benchmark: BenchmarkViewModel?` (ModelsView pushes `BenchmarkView` from it, so `SettingsView`/`LiveView`'s `ModelsView(model:)` are untouched); `recommendation`, `measuredResults`, `measuredRecommendation`, `measuredNote`, `benchmarkFooterText`; `static finishBenchmarkText = "Finish or cancel the benchmark first"`, `notMeasuredFooterText`, `measuredNoteText(date:timeZone:)` ("Measured on this iPhone on 14 November 2023"), `measuredFooterText(date:timeZone:)`
- `AppEnvironment { let benchmarks: BenchmarkStore; let benchmark: BenchmarkViewModel; static func gated(_ supplier: @escaping PipelineSupplier, isBenchmarkRunning: @escaping @MainActor () -> Bool) -> PipelineSupplier; init(…, benchmarkDirectory: URL? = nil) }`
- Test helper `BenchmarkRun.sample(date:device:whisperKitVersion:)` and `FakeBenchmarkSeams` (for L5's screenshot capture of the Benchmark screen)

### Task 1: WordErrorRate (core)

- [ ] Write the failing test: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxCore/Tests/ReVoxCoreTests/WordErrorRateTests.swift ReVoxCore/Tests/ReVoxCoreTests/`. Its load-bearing assertions: `WordErrorRate.words("Good morning, where is the train station?").count == 7`; one substitution → `1.0 / 7.0` (accuracy 0.0001); `rate(reference: "hello", hypothesis: "well hello there friend") == 3` and accuracy 0; `words("¿Dónde está la estación?") == ["dónde", "está", "la", "estación"]`; empty reference → 0 against empty, 1 otherwise; `editDistance(["a","b","c"], ["a","c"]) == 1`, `([], ["a","b"]) == 2`.
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter WordErrorRateTests` — fails to compile (`WordErrorRate` undefined).
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxCore/Sources/ReVoxCore/WordErrorRate.swift ReVoxCore/Sources/ReVoxCore/`. The whole file:

```swift
import Foundation

/// Word error rate for the on-device benchmark (M11 §5): Levenshtein distance over words divided by the number of
/// reference words. Foundation-only, so the score is the same on Linux and on the iPhone.
public enum WordErrorRate {
    /// Lowercased words. Letters, digits and whitespace survive; every other character is dropped, so "station?"
    /// and "¿dónde" compare as "station" and "dónde". Accents are kept: both sides are normalised the same way.
    public static func words(_ text: String) -> [String] {
        let kept = text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        return kept.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Levenshtein distance between two word arrays (insertions, deletions and substitutions cost one each).
    public static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0 ... b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            current[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Edits divided by the reference word count. An empty reference scores 0 against an empty hypothesis and 1
    /// against anything else. Insertions can push the rate above 1.
    public static func rate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let heard = words(hypothesis)
        if expected.isEmpty { return heard.isEmpty ? 0 : 1 }
        return Double(editDistance(expected, heard)) / Double(expected.count)
    }

    /// `max(0, 1 − rate)`: accuracy never goes below zero.
    public static func accuracy(reference: String, hypothesis: String) -> Double {
        max(0, 1 - rate(reference: reference, hypothesis: hypothesis))
    }
}
```
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter WordErrorRateTests` — 7 tests pass.
- [ ] Commit:
```
git add ReVoxCore/Sources/ReVoxCore/WordErrorRate.swift ReVoxCore/Tests/ReVoxCoreTests/WordErrorRateTests.swift
git commit -F - <<'EOF'
feat(core): WordErrorRate — Levenshtein over words for the M11 benchmark

The benchmark scores the gate's English against a fixed reference sentence: lowercase, keep letters, digits and
whitespace, Levenshtein over the word arrays, edits over the reference count. Foundation-only, Linux-tested.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 2: ModelBenchmark.swift — sentences, result, run, verdict wording, report (core)

- [ ] Write the failing test: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxCore/Tests/ReVoxCoreTests/ModelBenchmarkTests.swift ReVoxCore/Tests/ReVoxCoreTests/` (16 tests: sentences es/fr/de + en fallback with seven-word references; `first(spokenBy:)`; `oneDecimal(4.0) == "4"`, `(2.06) == "2.1"`; `speedText(0.238) == "4.2× faster than real time"`, `(1.0) == "as fast as real time"`, `(1.6) == "1.6× slower than real time"`, `(0) == "not measured"`; `loadText(0.4) == "loads in under a second"`, `(9.5) == "loads in 10 s"`; `accuracyText(0.125) == "88 % of words right"`, `(0) == "every word right"`, `(1.2) == "0 % of words right"`; `memoryText(240) == "uses 240 MB"`; `line(...) == "4.2× faster than real time · loads in 3 s · 88 % of words right · uses 240 MB"`; summary/symbol at the thresholds incl. 0.5 and 10 s exactly out; `spokenText == "small. Keeps up. 4.2 times faster than real time. loads in 3 seconds. 88 % of words right. uses 240 megabytes"`; `dateText(1_700_000_000, UTC) == "14 November 2023"`; Codable round trip with `.iso8601`; the exact markdown report for tiny + small + a skipped medium with header `# ReVox benchmark · iPhone17,1 · iOS 26.0 · 8 GB · WhisperKit 1.1.0 · 2023-11-14T22:13:20Z`).
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter ModelBenchmarkTests` — fails to compile.
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxCore/Sources/ReVoxCore/ModelBenchmark.swift ReVoxCore/Sources/ReVoxCore/` (190 lines; the full text is in `plan.md`). The contract it fixes: `ModelBenchmarkResult.init(model:loadSeconds:firstSeconds:steadySeconds:audioSeconds:wordErrorRate:residentBeforeMB:peakDeltaMB:thermalState:skippedReason: = nil, hypothesis: = "")` with `realTimeFactor = audioSeconds > 0 ? steadySeconds / audioSeconds : 0` (never infinite: the run is JSON); `ModelBenchmarkResult.skipped(_:reason:thermalState:)`; `BenchmarkRun(date:device:iOSVersion:memoryTierGB:whisperKitVersion:sentence:results:)`; `BenchmarkVerdict.speedText`: `rtf <= 0 || !finite → "not measured"`, `< 0.95 → "\(oneDecimal(1/rtf))× faster than real time"`, `<= 1.05 → "as fast as real time"`, else `"\(oneDecimal(rtf))× slower than real time"`; `loadText`: `< 0.95 → "loads in under a second"` else `"loads in \(Int(seconds.rounded())) s"`; `accuracyText`: `<= 0 → "every word right"` else `"\(Int((max(0, 1 - wer) * 100).rounded())) % of words right"`; `summaryText`: skipped → `"Skipped: \(reason)"`, `DeviceRecommendation.qualifies → "Keeps up"`, `audioSeconds <= 0 || rtf >= maxRealTimeFactor → "Too slow for live use"`, else `"Slow to load"` (symbols `minus.circle` / `checkmark.circle` / `tortoise` / `hourglass`); `dateText` and `BenchmarkReport.timestamp` use `Calendar(identifier: .gregorian)` components (no `DateFormatter`, as `TranscriptFormatter`); `BenchmarkReport.columns = "| Model | Load s | First s | Steady s | Audio s | RTF | WER | Resident before MB | Peak delta MB | Thermal | Verdict |"`, a skipped row prints dashes and `Skipped: <reason>`.
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter ModelBenchmarkTests` — 16 pass (they reference `DeviceRecommendation.qualifies` and `maxRealTimeFactor`, so add Task 3's extension in the same step if the filter fails on those two names; Task 3 commits it).
- [ ] Commit (after Task 3's implement step, see below) — or commit now together with Task 3; the message for the pair:
```
git add ReVoxCore/Sources/ReVoxCore/ModelBenchmark.swift ReVoxCore/Tests/ReVoxCoreTests/ModelBenchmarkTests.swift
git commit -F - <<'EOF'
feat(core): the benchmark run record, its verdict wording and the shared report

BenchmarkSentence(s) fix the stimuli (Spanish, French, German, an English fallback, seven-word references);
ModelBenchmarkResult and BenchmarkRun are the Codable record one JSON file holds; BenchmarkVerdict turns the
numbers into "4.2× faster than real time · loads in 3 s · 88 % of words right · uses 240 MB" and Keeps up /
Too slow for live use / Slow to load, with spoken twins for VoiceOver; BenchmarkReport.markdown is the text
the share sheet exports, one table row per model, the shape of docs/measurements/m11-model-benchmark.md.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 3: DeviceRecommendation.measured (core)

- [ ] Write the failing tests: `git apply /home/user/ReVoxMobile/.claude/plans/m11-L3/DeviceRecommendationTests.swift.diff` (appends, before the class's closing brace, a `measured(_:wer:rtf:load:)` helper and 8 tests: `XCTAssertEqual(DeviceRecommendation.maxRealTimeFactor, 0.5)`, `XCTAssertEqual(DeviceRecommendation.maxLoadSeconds, 10.0)`; no results → memory for every tier; 8 GiB with tiny WER 0.25 / small 0.125 / medium 0 rtf 0.4 load 8 → medium, `suitable` and `warnings` unchanged; 6 GiB largeV3 WER 0 → still small; rtf 0.5 exactly and load 10 exactly excluded; ties → lower rtf, then catalogue order; nothing qualifying → memory; `qualifies` rejects skipped and zero audio).
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore --filter DeviceRecommendationTests` — fails to compile.
- [ ] Implement: append to `ReVoxCore/Sources/ReVoxCore/DeviceRecommendation.swift` after its final `}` (lines 1–44 unchanged; identical to `git apply /home/user/ReVoxMobile/.claude/plans/m11-L3/DeviceRecommendation.swift.diff`):

```swift

// MARK: - M11 §5: the measured rule

extension DeviceRecommendation {
    /// ASSUMED thresholds (recorded in `docs/measurements/m11-model-benchmark.md`, row 7): a measured model is
    /// recommended only when its steady real-time factor is below this and it loaded within `maxLoadSeconds`.
    public static let maxRealTimeFactor = 0.5
    public static let maxLoadSeconds = 10.0

    /// Measured, with audio, fast enough to keep up and quick enough to load.
    public static func qualifies(_ result: ModelBenchmarkResult) -> Bool {
        !result.isSkipped && result.audioSeconds > 0
            && result.realTimeFactor < maxRealTimeFactor && result.loadSeconds < maxLoadSeconds
    }

    /// Among `results` inside the memory tier's suitable set, the lowest word error rate that qualifies; ties go to
    /// the lower real-time factor, then to catalogue order. `nil` when nothing qualifies. The caller passes only
    /// results for models that are installed now.
    public static func bestMeasured(memory: DeviceRecommendation, results: [ModelBenchmarkResult]) -> WhisperModelID? {
        let order = ModelCatalog.whisperModels.map(\.id)
        let candidates = results.filter { memory.suitable.contains($0.model) && qualifies($0) }
        let best = candidates.min { lhs, rhs in
            if lhs.wordErrorRate != rhs.wordErrorRate { return lhs.wordErrorRate < rhs.wordErrorRate }
            if lhs.realTimeFactor != rhs.realTimeFactor { return lhs.realTimeFactor < rhs.realTimeFactor }
            return (order.firstIndex(of: lhs.model) ?? order.count) < (order.firstIndex(of: rhs.model) ?? order.count)
        }
        return best?.model
    }

    /// The memory tier with `recommended` replaced by the best measured model; the memory tier unchanged when
    /// nothing qualifies. `suitable` and `warnings` always come from memory.
    public static func measured(memory: DeviceRecommendation, results: [ModelBenchmarkResult]) -> DeviceRecommendation {
        guard let best = bestMeasured(memory: memory, results: results) else { return memory }
        return DeviceRecommendation(recommended: best, suitable: memory.suitable, warnings: memory.warnings)
    }
}
```
- [ ] Run: `/home/user/swift/usr/bin/swift test --package-path ReVoxCore` — the whole package passes (318 tests on HEAD + these); then `bash scripts/ci/check-constant-coverage.sh` — "All 65 ported constants are asserted".
- [ ] Commit:
```
git add ReVoxCore/Sources/ReVoxCore/DeviceRecommendation.swift ReVoxCore/Tests/ReVoxCoreTests/DeviceRecommendationTests.swift
git commit -F - <<'EOF'
feat(core): DeviceRecommendation.measured — the benchmark decides `recommended`, memory keeps `suitable`

Among the installed models' results inside the memory tier's suitable set, the lowest word error rate whose
real-time factor is under 0.5 and whose load took under 10 s wins (ties: lower real-time factor, then catalogue
order); nothing qualifying leaves the memory tier as it is. The two thresholds ship ASSUMED and are asserted by
name and value; docs/measurements/m11-model-benchmark.md row 7 validates them on a device.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 4: the translator seam and the stimulus (app)

CI is the compiler for every app step below: `swiftc -parse` only; the simulator job runs the tests.

- [ ] Write the failing test: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/BenchmarkStimulusTests.swift ReVoxMobileTests/` (5 tests: 22 050 / 24 000 / 48 000 Hz one-second tones become 16 000 ± 16 samples and are not silent; 16 kHz passes through unchanged; `SystemSpeaker(voiceIdentifier: nil, synthesize:)` with `hasVoice { _ in false }` → the English sentence spoken once; an empty clip for the Spanish text → English retried, `spoken == [spanish.text, english.text]`; silence for everything → `BenchmarkError.noSpeech` with its description).
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/BenchmarkStimulusTests.swift` — parses (the types it names are the next step's).
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkTranslating.swift /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkStimulus.swift ReVoxMobile/Benchmark/` (create the folder first: `mkdir -p ReVoxMobile/Benchmark`; XcodeGen picks new files up by path). The seam:

```swift
protocol BenchmarkTranslating: Sendable {
    func load(progress: @escaping @Sendable (String) -> Void) async throws
    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate
    func unload() async
}
extension WhisperKitTranslator: BenchmarkTranslating {}
```
and the factory's core (`BenchmarkStimulus.swift`, which also declares `BenchmarkStimulus { sentence, samples; audioSeconds }` and `BenchmarkError`):

```swift
struct BenchmarkStimulusFactory: Sendable {
    let speaker: any Speaker
    let hasVoice: @Sendable (String) -> Bool
    static func production() -> BenchmarkStimulusFactory {
        BenchmarkStimulusFactory(speaker: SystemSpeaker(voiceIdentifier: nil), hasVoice: { SystemSpeaker.hasVoice(for: $0) })
    }
    func make() async throws -> BenchmarkStimulus {
        let sentence = BenchmarkSentences.first(spokenBy: hasVoice)
        if let stimulus = try await stimulus(for: sentence) { return stimulus }
        if sentence != BenchmarkSentences.english, let fallback = try await stimulus(for: BenchmarkSentences.english) { return fallback }
        throw BenchmarkError.noSpeech
    }
    private func stimulus(for sentence: BenchmarkSentence) async throws -> BenchmarkStimulus? {
        let clip: AudioClip
        do { clip = try await speaker.synthesize(sentence.text, language: sentence.language) }
        catch SpeakerError.noVoice { return nil }
        guard !clip.isEmpty else { return nil }
        return BenchmarkStimulus(sentence: sentence, samples: try Self.samples16k(from: clip))
    }
    static func samples16k(from clip: AudioClip) throws -> [Float] {
        guard clip.sampleRate != AudioFormat.pipelineSampleRate else { return clip.samples }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(clip.sampleRate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer.mono(samples: clip.samples, format: format),
              let converter = AVAudioConverter(from: format, to: PCMConverterDriver.pipelineFormat) else {
            throw PCMConversionError.bufferAllocationFailed
        }
        return try PCMConverterDriver.convertToMono(buffer, with: converter, endOfStream: true)
    }
}
```
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Benchmark/BenchmarkTranslating.swift ReVoxMobile/Benchmark/BenchmarkStimulus.swift ReVoxMobileTests/BenchmarkStimulusTests.swift` — clean.
- [ ] Commit:
```
git add ReVoxMobile/Benchmark/BenchmarkTranslating.swift ReVoxMobile/Benchmark/BenchmarkStimulus.swift ReVoxMobileTests/BenchmarkStimulusTests.swift
git commit -F - <<'EOF'
feat(app): the benchmark's translator seam and its synthesised sentence

BenchmarkTranslating is the slice of WhisperKitTranslator the benchmark drives, so the simulator tests run over a
fake engine. BenchmarkStimulusFactory speaks the first sentence the iPhone has a voice for through any Speaker
(SystemSpeaker over SpeechWriteCollector in production), falls back to English once, and converts the clip to the
pipeline's 16 kHz through PCMConverterDriver at the voice's own rate.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 5: BenchmarkRunner and its fakes (app)

- [ ] Write the failing tests: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/Support/FakeBenchmarkSeams.swift ReVoxMobileTests/Support/ && cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/BenchmarkRunnerTests.swift ReVoxMobileTests/`. The fake drives a real `WhisperKitTranslator` over a fake `WhisperEngine` per model (events `"load tiny"`, `"translate tiny"`, `"unload tiny"`; resident memory +100 MiB on load; a thermal queue read once per model; `hold` on the stimulus and `holdTranslate(of:)` per model so a cancel lands in a known place; `setText`, `setWordless`, `failLoad`) and adds `BenchmarkRun.sample()`. The 13 tests assert: order and unload between models; `audioSeconds == 2.0`; WER `1/7` for "bus" and 0 for the reference; a wordless decode → hypothesis "" and WER 1 but still measured; progress `[.synthesising, .loading(.tiny, "Preparing model…"), .loading(.tiny, "Loading"), .translating(.tiny, pass: 1), .translating(.tiny, pass: 2), .finished(.tiny)]`; `.serious` → `.skipped(.tiny, reason: "iPhone too hot", thermalState: "serious")` and the next model runs without tiny ever loading; a load failure → `"couldn't load: boom"`, unload still attempted; cancel during tiny's translate → every result cancelled and no score; cancel during small → tiny kept, small and medium cancelled; `peakDeltaMB == 100`, `residentBeforeMB == 100`; `thermalText`/`isTooHot`; `noSpeech` propagates with nothing loaded; a second concurrent `run` throws `.busy`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/Support/FakeBenchmarkSeams.swift ReVoxMobileTests/BenchmarkRunnerTests.swift` — clean.
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkRunner.swift ReVoxMobile/Benchmark/`. The measuring loop (the file also declares `BenchmarkProgress`, `BenchmarkSeams` with `static func production(layout:)`, `BenchmarkOutcome`, the pure `thermalText`/`isTooHot`/`seconds(since:clock:)`):

```swift
actor BenchmarkRunner {
    static let passes = 2
    private static let logger = Logger(subsystem: "revox", category: "measurements")
    private let seams: BenchmarkSeams
    private let clock = ContinuousClock()
    private var isRunning = false

    func run(models: [WhisperModelID], progress: @escaping @Sendable (BenchmarkProgress) -> Void) async throws -> BenchmarkOutcome {
        guard !isRunning else { throw BenchmarkError.busy }
        isRunning = true
        defer { isRunning = false }
        progress(.synthesising)
        let stimulus = try await seams.makeStimulus()
        var results: [ModelBenchmarkResult] = []
        var cancelled = false
        for model in models {
            let thermal = Self.thermalText(seams.thermalState())
            if cancelled || Task.isCancelled {
                cancelled = true
                results.append(.skipped(model, reason: BenchmarkSkipReason.cancelled, thermalState: thermal))
                progress(.skipped(model, BenchmarkSkipReason.cancelled)); continue
            }
            if Self.isTooHot(thermal) {
                results.append(.skipped(model, reason: BenchmarkSkipReason.tooHot, thermalState: thermal))
                progress(.skipped(model, BenchmarkSkipReason.tooHot)); continue
            }
            switch await measure(model, stimulus: stimulus, thermal: thermal, progress: progress) {
            case .measured(let result): results.append(result); progress(.finished(model))
            case .failed(let reason): results.append(.skipped(model, reason: reason, thermalState: thermal)); progress(.skipped(model, reason))
            case .cancelled: cancelled = true; results.append(.skipped(model, reason: BenchmarkSkipReason.cancelled, thermalState: thermal)); progress(.skipped(model, BenchmarkSkipReason.cancelled))
            }
        }
        return BenchmarkOutcome(sentence: stimulus.sentence, results: results)
    }
```
`measure` reads `seams.residentBytes()` before, makes `seams.makeTranslator(model)`, times `load { progress(.loading(model, $0)) }` with `clock.now` (failure → `.failed(BenchmarkSkipReason.couldNotLoad(UserFacingErrorText.describe(error)))` after an `unload()`), then for `pass in 1 ... Self.passes` checks `Task.isCancelled` (→ unload, `.cancelled`), emits `.translating(model, pass:)`, times `translate(stimulus.samples, language: stimulus.sentence.language)`, samples resident memory into `peak`; after `unload()` it returns `.cancelled` if `Task.isCancelled` (a cancelled decode's empty candidate is never scored), else scores `SpeechGate.evaluate(candidate)?.english ?? ""` with `WordErrorRate.rate(reference: stimulus.sentence.reference, hypothesis:)`, builds the result (`peakDeltaMB = (peak - before) / 1_048_576`, `thermalState: thermal`, `hypothesis`) and logs exactly `benchmark model=<id> load_ms=… first_ms=… steady_ms=… audio_ms=… rtf=… wer=… resident_before_mb=… peak_delta_mb=… thermal=…` with `privacy: .public` on each value.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Benchmark/BenchmarkRunner.swift` — clean; `bash scripts/ci/check-no-host-time.sh` — clean (ContinuousClock only).
- [ ] Commit:
```
git add ReVoxMobile/Benchmark/BenchmarkRunner.swift ReVoxMobileTests/Support/FakeBenchmarkSeams.swift ReVoxMobileTests/BenchmarkRunnerTests.swift
git commit -F - <<'EOF'
feat(app): BenchmarkRunner — one model at a time, timed with ContinuousClock, scored by the gate

Thermal check before each model (serious/critical skips it), the load, a first and a steady translate timed,
MemoryMeter before and after, SpeechGate.evaluate on the output and its word error rate, unload between models,
one `benchmark model=…` measurements line per model. A cancelled task returns the partial outcome with the rest
marked cancelled, and a cancelled decode is never scored. The fakes run the real WhisperKitTranslator over a fake
engine so the simulator tests never need a model.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 6: BenchmarkStore (app)

- [ ] Write the failing tests: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/BenchmarkStoreTests.swift ReVoxMobileTests/` (save writes `1700000000.json`/`1700000600.json`, reload newest first; `latest` ignores another hardware identifier and another `whisperKitVersion`; an undecodable file and a `.txt` are skipped; a missing folder is an empty store until the first save; `defaultDirectory()` ends in `/ReVox/Benchmarks`; `BenchmarkHost.current(deviceInfo:)` has a hardware id, a dotted version and the tier).
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/BenchmarkStoreTests.swift` — clean.
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkStore.swift ReVoxMobile/Benchmark/`. Key lines: `BenchmarkHost.hardwareIdentifier()` reads `utsname().machine` with `uname`; `static func defaultDirectory(fileManager:)` = `<Application Support>/<ModelLayout.rootFolderName>/Benchmarks`, created; `var latest: BenchmarkRun? { runs.first { $0.device == host.device && $0.whisperKitVersion == whisperKitVersion } }`; `save` encodes with `.iso8601`, `[.prettyPrinted, .sortedKeys]`, writes `.atomic`, appends and sorts by date descending; `load(from:)` decodes every `.json`, logs and skips failures under `revox`/`models`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Benchmark/BenchmarkStore.swift` — clean.
- [ ] Commit:
```
git add ReVoxMobile/Benchmark/BenchmarkStore.swift ReVoxMobileTests/BenchmarkStoreTests.swift
git commit -F - <<'EOF'
feat(app): BenchmarkStore — one JSON file per run under Application Support/ReVox/Benchmarks

`latest` is the newest run made on this iPhone with this WhisperKit, so a backup restored on another phone or a
pin bump stops counting, as VerifiedLoadRecord ignores stale versions.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 7: BenchmarkViewModel (app)

- [ ] Write the failing tests: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/BenchmarkViewModelTests.swift ReVoxMobileTests/` (16 tests over a `ModelManager` with `FakeInstallSteps`, a `VerifiedLoadRecord` the test records into, a temp `BenchmarkStore`, `FakeBenchmarkSeams`, `FakeInstallHost`: refused while running / while a download is active / with no ready model, each with the exact text in `whyNotText` and `refusedAlert`; Live starting during the readiness awaits is refused; a full run releases the pipeline once, saves one file, exposes rows, `shareText == BenchmarkReport.markdown(run)`, the footer and `lastRunText`, and a `ModelsViewModel` over the same store recommends small with the "Measured on this iPhone on …" note; status texts and the background task/idle timer bracket the run (`host.ended == [1]`, `idleTimerHistory == [true, false]`); cancel keeps partial results with `"Stopped after 1 of 2 models; the results so far are kept."`; cancel before any result is a notice, not a failure; background expiry ends the task at once and is not ended twice; every model too hot → `"Nothing measured: iPhone too hot"`; `noSpeech` → the failure alert; `rows(for:)`, `footerText`, `lastRunText`, `statusText`, and every screen string).
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/BenchmarkViewModelTests.swift` — clean.
- [ ] Implement: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkViewModel.swift ReVoxMobile/Benchmark/`. The state machine:

```swift
    func start() {
        guard !isRunning else { return }
        if let reason = whyNotText { refusedAlert = reason; return }
        notice = nil
        state = .running(Self.synthesisingText)          // before the first await: canRun flips at once
        let installed = manager.installedWhisper
        task = Task { [weak self] in guard let self else { return }; await self.perform(installed: installed) }
    }
    func cancel() { guard isRunning else { return }; task?.cancel(); state = .stopping }

    private func perform(installed: [WhisperModelID]) async {
        defer { endRun() }
        var ready: [WhisperModelID] = []
        for id in installed { let isReady = await manager.isWhisperReady(id); if isReady { ready.append(id) } }
        guard !ready.isEmpty else { refusedAlert = Self.noReadyModelsText; return }
        guard !isPipelineRunning() else { refusedAlert = Self.stopToBenchmarkText; return }   // Live got there first
        await releasePipeline()
        backgroundTask = host.beginBackgroundTask(name: Self.backgroundTaskName) { [weak self] in self?.backgroundTimeExpired() }
        host.isIdleTimerDisabled = true
        do {
            let outcome = try await runner.run(models: ready) { [weak self] progress in Task { @MainActor in self?.apply(progress) } }
            finish(outcome, total: ready.count)
        } catch { failureAlert = UserFacingErrorText.describe(error) }
    }
```
`finish`: no measured result → `notice = stoppedBeforeAnyText` when every skip is cancelled, else `failureAlert = BenchmarkError.nothingMeasured(firstReason).description`; otherwise `store.save(BenchmarkRun(date: Date(), device: store.host.device, iOSVersion:, memoryTierGB:, whisperKitVersion: store.whisperKitVersion, sentence:, results:))` and `notice = stoppedEarlyText(measured:of:)` when something was cancelled. `backgroundTimeExpired` cancels the task, ends the background task immediately and sets `.stopping`; `endRun` ends it if still open, restores `host.isIdleTimerDisabled = manager.hasActiveDownload`, `state = .idle`. `whyNotText` order: `isPipelineRunning()` → `"Stop translation to run the benchmark"`, `manager.hasActiveDownload` → `"Wait for the download to finish first"`, `manager.installedWhisper.isEmpty` → `"Download a Whisper model first"`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Benchmark/BenchmarkViewModel.swift` — clean; `python3 scripts/dev/check-test-autoclosures.py` — clean.
- [ ] Commit:
```
git add ReVoxMobile/Benchmark/BenchmarkViewModel.swift ReVoxMobileTests/BenchmarkViewModelTests.swift
git commit -F - <<'EOF'
feat(app): BenchmarkViewModel — Run, progress per model, the saved run, Share results

Refuses while a session runs, a download is active or no verified model is installed (the Models pattern: the
button stays enabled and the refusal is an alert, the reason a footer). The state flips to running before the first
await; the cached Live model and pocket-tts are released first; a background task and the idle timer bracket the
run and the task is ended at once on expiry. Cancel keeps the results so far and says so.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 8: the Benchmark screen, the Models entry and the measured recommendation (app)

- [ ] Write the failing tests: `git apply /home/user/ReVoxMobile/.claude/plans/m11-L3/ModelsViewModelTests.swift.diff` (adds `benchmarkRunning`, a `benchmarks:` parameter to `makeModel`, a `benchmarkStore(_:device:)` helper and 6 tests: the capsule moves to small with `rows[2].measuredNote == ModelsViewModel.measuredNoteText(date: run.date)` and only there, warnings stay memory-derived; a measured model that is not installed does not count; another hardware id or an older `whisperKitVersion` is ignored (`benchmarkFooterText == "Recommended by memory size. Run the benchmark to measure this iPhone."`); nothing qualifying → memory, no note; the note texts; download and delete refused with `"Finish or cancel the benchmark first"` while `benchmarkRunning`), and `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobileTests/BenchmarkHostingTests.swift ReVoxMobileTests/` (hosts `BenchmarkView` idle without results, with `BenchmarkRun.sample()`, refused, at `.accessibility5`, running and stopping via the fake's `hold`, every `BenchmarkRowView`; hosts `ModelsView` with `model.benchmark` set and asserts `ModelRowView.accessibilityText(for:)` = `"Model small. 487 MB. Installed. Recommended. Measured on this iPhone on 14 November 2023"` while a row without the note keeps `"Model base. 145 MB. Installed"`; plus the two `AppEnvironment` tests of Task 9).
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobileTests/ModelsViewModelTests.swift ReVoxMobileTests/BenchmarkHostingTests.swift` — clean.
- [ ] Implement `ModelRow.swift`: after `    let isSelected: Bool` add
```swift
    /// M11: "Measured on this iPhone on 14 November 2023" on the row the benchmark recommended; nil elsewhere.
    /// Defaulted, so the memberwise construction sites of the earlier milestones keep compiling.
    var measuredNote: String? = nil
```
- [ ] Implement `ModelRowView.swift`: after the `if let note = row.note { … }` block (before `stateView`) add
```swift
            if let measured = row.measuredNote {
                Label(measured, systemImage: "gauge.with.needle").font(.caption).foregroundStyle(.secondary)
            }
```
and in `accessibilityText(for:)` after `if !row.isSuitable { parts.append(ModelsViewModel.notRecommendedText) }` add `        if let measured = row.measuredNote { parts.append(measured) }`.
- [ ] Implement `ModelsViewModel.swift`: `git apply /home/user/ReVoxMobile/.claude/plans/m11-L3/ModelsViewModel.swift.diff`. It replaces `    private let recommendation: DeviceRecommendation` with `private let deviceInfo: DeviceInfo`, `private let benchmarks: BenchmarkStore?`, `private let isBenchmarkRunning: @MainActor () -> Bool` and `var benchmark: BenchmarkViewModel?`; the init becomes `init(manager:settings:deviceInfo:isPipelineRunning:benchmarks: BenchmarkStore? = nil, isBenchmarkRunning: @escaping @MainActor () -> Bool = { false })`; adds
```swift
    var measuredResults: [ModelBenchmarkResult] {
        guard let run = benchmarks?.latest else { return [] }
        let installed = manager.installedWhisper
        return run.measured.filter { installed.contains($0.model) }
    }
    var measuredRecommendation: WhisperModelID? { DeviceRecommendation.bestMeasured(memory: deviceInfo.recommendation, results: measuredResults) }
    var recommendation: DeviceRecommendation { DeviceRecommendation.measured(memory: deviceInfo.recommendation, results: measuredResults) }
    var measuredNote: String? {
        guard measuredRecommendation != nil, let date = benchmarks?.latest?.date else { return nil }
        return Self.measuredNoteText(date: date)
    }
    var benchmarkFooterText: String {
        guard measuredRecommendation != nil, let date = benchmarks?.latest?.date else { return Self.notMeasuredFooterText }
        return Self.measuredFooterText(date: date)
    }
    static func measuredNoteText(date: Date, timeZone: TimeZone = .current) -> String { "Measured on this iPhone on \(BenchmarkVerdict.dateText(date, timeZone: timeZone))" }
    static func measuredFooterText(date: Date, timeZone: TimeZone = .current) -> String { "Recommendation measured on this iPhone on \(BenchmarkVerdict.dateText(date, timeZone: timeZone))" }
```
`rows` binds `let recommendation = self.recommendation; let measuredNote = self.measuredNote` and passes `measuredNote: recommendation.recommended == descriptor.id ? measuredNote : nil`; `canDelete`/`canDownload` become `!isPipelineRunning() && !isBenchmarkRunning()`; `footerText` returns `Self.finishBenchmarkText` when the benchmark runs; `download` refuses with `isBenchmarkRunning() ? Self.finishBenchmarkText : Self.stopToDownloadText`; `delete` starts with `guard !isBenchmarkRunning() else { throw BenchmarkError.busy }`; new statics `finishBenchmarkText = "Finish or cancel the benchmark first"`, `notMeasuredFooterText = "Recommended by memory size. Run the benchmark to measure this iPhone."`.
- [ ] Implement `ModelsView.swift`: before `            Section("Voice detector") {` insert
```swift
            if let benchmark = model.benchmark {
                Section {
                    NavigationLink(BenchmarkViewModel.linkTitle) { BenchmarkView(model: benchmark) }
                        .frame(minHeight: 44)
                        .accessibilityHint(BenchmarkViewModel.linkHint)
                } footer: {
                    Text(model.benchmarkFooterText)
                }
            }
```
- [ ] Implement `BenchmarkView.swift`: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/ReVoxMobile/Benchmark/BenchmarkView.swift ReVoxMobile/Benchmark/` — a `List` with: `Text(introText)`; a `switch model.state` giving the 44 pt `.borderedProminent` Run button (`accessibilityHint(runButtonHint)`) or a progress row (`ProgressView` + status, `.accessibilityAddTraits(.updatesFrequently)`, a 44 pt Cancel with `cancelHint`, disabled while `.stopping`); `SettingExample(symbol: "gauge.with.needle", text: BenchmarkViewModel.exampleText)`; footer `keepOpenText` while running else `whyNotText`; a "Results" section with `BenchmarkRowView` rows or `noResultsText`, `if let text = model.shareText { ShareLink(item: text) { Label(shareTitle, systemImage: "square.and.arrow.up") }.frame(minHeight: 44).accessibilityHint(shareHint) }`, footer `lastRunText`, `resultsFooterText`, `notice`; alerts "Can't run now" / "Benchmark failed"; `BenchmarkRowView` = name `.headline`, `Label(row.summary, systemImage: row.symbol)`, the detail line, `.accessibilityElement(children: .ignore).accessibilityLabel(row.spokenText)`.
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/Screens/ModelRow.swift ReVoxMobile/Screens/ModelRowView.swift ReVoxMobile/Screens/ModelsViewModel.swift ReVoxMobile/Screens/ModelsView.swift ReVoxMobile/Benchmark/BenchmarkView.swift` — clean; `diff` each against its `/home/user/ReVoxMobile/.claude/plans/m11-L3/files/…` copy — identical.
- [ ] Commit:
```
git add ReVoxMobile/Benchmark/BenchmarkView.swift ReVoxMobile/Screens/ModelRow.swift ReVoxMobile/Screens/ModelRowView.swift ReVoxMobile/Screens/ModelsViewModel.swift ReVoxMobile/Screens/ModelsView.swift ReVoxMobileTests/ModelsViewModelTests.swift ReVoxMobileTests/BenchmarkHostingTests.swift
git commit -F - <<'EOF'
feat(app): Settings › Models › Benchmark this iPhone, and the measured recommendation on the Models screen

The Models screen pushes the Benchmark screen from its view model, so its two existing hosts are untouched. The
recommendation becomes DeviceRecommendation.measured over the latest run's results for the models on disk; the
recommended row says "Measured on this iPhone on <date>" (spoken as part of its sentence), the section footer says
whether the recommendation was measured, and downloads and deletes are refused while a benchmark runs.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```
(The `BenchmarkHostingTests` file's two `AppEnvironment` tests compile only after Task 9; if the executor commits Task 8 before Task 9, CI will not run in between.)

### Task 9: AppEnvironment wiring (benchmark only)

- [ ] The failing tests are already in `ReVoxMobileTests/BenchmarkHostingTests.swift`: `testTestingEnvironmentWiresTheStoreTheScreenAndTheModelsEntry` (`environment.benchmarks.directory.lastPathComponent == "Benchmarks"` under the root, `environment.benchmark.whyNotText == "Download a Whisper model first"`, `environment.models.benchmark === environment.benchmark`, `models.benchmarkFooterText == ModelsViewModel.notMeasuredFooterText`) and `testLiveStartIsRefusedWhileABenchmarkRuns` (`AppEnvironment.gated(inner, isBenchmarkRunning: { running.value })` throws `BenchmarkError.liveBlocked` whose `UserFacingErrorText.describe` is `"Finish or cancel the benchmark in Settings › Models before starting"`, builds nothing, then builds once when not running).
- [ ] Implement: `git apply /home/user/ReVoxMobile/.claude/plans/m11-L3/AppEnvironment.swift.diff`. It adds `let benchmarks: BenchmarkStore` and `let benchmark: BenchmarkViewModel` after `let models`, a `benchmarkDirectory: URL? = nil` init parameter (testing passes `root.appendingPathComponent(BenchmarkStore.folderName, isDirectory: true)`), and:
```swift
    @MainActor
    private final class BenchmarkActivity {
        weak var benchmark: BenchmarkViewModel?
        var isRunning: Bool { benchmark?.isRunning ?? false }
    }

    static func gated(_ supplier: @escaping PipelineSupplier, isBenchmarkRunning: @escaping @MainActor () -> Bool) -> PipelineSupplier {
        { settings, progress in
            let busy = await isBenchmarkRunning()
            guard !busy else { throw BenchmarkError.liveBlocked }
            return try await supplier(settings, progress)
        }
    }
```
In `init`, `let benchmarkActivity = BenchmarkActivity()` before `self.live`, whose `supplier:` becomes `Self.gated(assembler.supplier(), isBenchmarkRunning: { benchmarkActivity.isRunning })`; then, replacing the one-line `self.models = …`:
```swift
        self.benchmarks = BenchmarkStore(directory: try benchmarkDirectory ?? BenchmarkStore.defaultDirectory(),
                                         host: BenchmarkHost.current(deviceInfo: deviceInfo))
        self.models = ModelsViewModel(manager: modelManager, settings: settings, deviceInfo: deviceInfo, isPipelineRunning: { activity.isBusy },
                                      benchmarks: benchmarks, isBenchmarkRunning: { benchmarkActivity.isRunning })
```
and after the `modelManager.onModelFilesChanged = …` block:
```swift
        // M11 §5: the benchmark releases the cached Live model and pocket-tts first, so exactly one model is resident.
        let assemblyForBenchmark = speakerAssembly
        self.benchmark = BenchmarkViewModel(
            store: benchmarks,
            manager: modelManager,
            isPipelineRunning: { activity.isBusy },
            releasePipeline: { [weak liveForRelease] in
                await liveForRelease?.releaseCachedPipeline()
                await assemblyForBenchmark.speaker.unloadPocketTTS()
            },
            runner: BenchmarkRunner(seams: .production(layout: layout)),
            host: installHost
        )
        benchmarkActivity.benchmark = benchmark
        models.benchmark = benchmark
```
- [ ] Run: `/home/user/swift/usr/bin/swiftc -parse ReVoxMobile/App/AppEnvironment.swift` — clean; `python3 scripts/dev/check-core-imports.py --all` — clean.
- [ ] Commit:
```
git add ReVoxMobile/App/AppEnvironment.swift
git commit -F - <<'EOF'
feat(app): wire the benchmark store, runner and screen; Live's Start is refused while a benchmark runs

The pipeline supplier is gated through a BenchmarkActivity box (main-actor read inside the async supplier), so a
Start during a benchmark shows "Finish or cancel the benchmark in Settings › Models before starting" instead of
loading a second WhisperKit beside the one being timed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

### Task 10: the measurement record, then the gates and the last commit

- [ ] Create `docs/measurements/m11-model-benchmark.md`: `cp /home/user/ReVoxMobile/.claude/plans/m11-L3/files/docs/measurements/m11-model-benchmark.md docs/measurements/`. Contents: what the benchmark measures; **Devices used: pending**; *How to run* (force-quit first, Settings › Models › Benchmark this iPhone › Run benchmark, Share results → paste under Raw logs, Console filter `subsystem:revox category:measurements` for the `benchmark model=` lines); *Published reference numbers* — only rows whose source resolves to a URL in the panel research: per-device speed factor and mean WER for tiny/base/small and the pinned 947 MB large-v3 on iPhone 13 (4 GB), 13 Pro (6 GB), 15 Pro and 16 Pro (8 GB) from `performance_data.json`, the "medium: not published" row from `support_data.csv`, warm load and resident memory rows from the raw run `2025-10-17T004021_3900754`, and the Mac-cluster quality rows from `quality_data.json`, each with its `https://huggingface.co/...` link and the caveat that these are 10-minute batch speed factors, not per-phrase latency; *Measured on this iPhone* — the empty owner table with exactly `BenchmarkReport.columns` and one `pending` row per model; the 9 `| # | ASSUMED item (spec) | Procedure | Evidence | Pass criterion | Result |` rows (load time, RTF, synthesised vs spoken accuracy, memory delta on 4 GB and 8 GB with a JetsamEvent check, thermal state, the `write ended by terminating buffer` count closing M3 row 6, the two thresholds validated by a 10-minute session, the sentence each device could say, background task and idle timer) all `pending`; *How to fill a row*; *Raw logs*; *Decisions taken* (thresholds kept or changed; the 947 MB vs 626 MB large-v3 catalogue follow-up).
- [ ] Run the gates from the worktree root:
```
/home/user/swift/usr/bin/swift test --package-path ReVoxCore
python3 scripts/dev/check-core-imports.py --all
python3 scripts/dev/check-test-autoclosures.py
python3 scripts/dev/check-tests-are-discoverable.py
bash scripts/ci/check-constant-coverage.sh
bash scripts/ci/check-no-host-time.sh
for f in ReVoxMobile/Benchmark/*.swift ReVoxMobile/Screens/ModelRow.swift ReVoxMobile/Screens/ModelRowView.swift ReVoxMobile/Screens/ModelsViewModel.swift ReVoxMobile/Screens/ModelsView.swift ReVoxMobile/App/AppEnvironment.swift ReVoxMobileTests/Benchmark*.swift ReVoxMobileTests/Support/FakeBenchmarkSeams.swift ReVoxMobileTests/ModelsViewModelTests.swift; do /home/user/swift/usr/bin/swiftc -parse "$f" || echo "PARSE FAIL $f"; done
grep -rniE "claude|anthropic" ReVoxMobile/Benchmark docs/measurements/m11-model-benchmark.md && echo "banned word" || true
```
All clean (verified on the staged copies: 318 core tests, 65 constants, 208 files' imports, 901 discoverable tests).
- [ ] Commit:
```
git add docs/measurements/m11-model-benchmark.md
git commit -F - <<'EOF'
docs(measurements): m11 model benchmark record — published expectations, the owner's table, nine pending rows

The published figures are Argmax's 10-minute batch speed factors and WER from the WhisperKit Benchmarks dashboard
and its raw dataset, cited by URL; they are expectations, not ReVox's numbers. The owner fills the table by pasting
the app's shared text; every row stays pending until the device evidence is in.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR
EOF
```

**Cross-lane needs**
- L7 (`README.md`): state the model table's expectations from `docs/measurements/m11-model-benchmark.md` (a link and two sentences, not the third-party numbers), add "Settings › Models › Benchmark this iPhone" to the first-run steps and reword known limitation 7 ("after a benchmark ReVox recommends the most accurate installed model that ran at least twice as fast as real time and loaded in under 10 s; the Models screen says when it was measured"); add `pending — superseded by m11 rows 6 and 2` to `docs/measurements/m3-microphone-mode.md` rows 6 and 10.
- L5 (`ScreenshotTests`): capture the Benchmark screen (`NavigationStack { BenchmarkView(model:) }` over a `BenchmarkStore` seeded with `BenchmarkRun.sample()` and `FakeBenchmarkSeams`, both in `ReVoxMobileTests/Support/FakeBenchmarkSeams.swift`) and re-capture `models` with `model.benchmark` set so the entry row and the measured note appear (spec §8).
- L6 (tutorial Models page): the line "Settings › Models › Benchmark this iPhone measures them on your iPhone." should read `BenchmarkViewModel.linkTitle` rather than a literal.
- Unowned in wave 1, for L5 wiring: `VoicesViewModel` should refuse a pocket-tts download or delete while a benchmark runs (an `isBenchmarkRunning` closure like `ModelsViewModel`'s, wired in `AppEnvironment` from `benchmarkActivity.isRunning`); `DegradationCoordinator` will react to `.serious` during a benchmark by degrading Live's next model and showing the heat banner — accepted and noted in m11 row 5, or suppress it while `benchmarkActivity.isRunning` if L5 prefers.
- `SettingsView.swift` (L1) needs no change: `ModelsView(model:)` keeps its signature and reads `model.benchmark`.