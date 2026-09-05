import Foundation
import os
import ReVoxCore

/// What the screen shows while a run is in progress (M11 §5).
enum BenchmarkProgress: Sendable, Equatable {
    case synthesising
    case loading(WhisperModelID, String)
    case translating(WhisperModelID, pass: Int)
    case finished(WhisperModelID)
    case skipped(WhisperModelID, String)
}

/// The seams the runner measures through: production reads the iPhone; the simulator tests inject fakes.
struct BenchmarkSeams: Sendable {
    var makeStimulus: @Sendable () async throws -> BenchmarkStimulus
    var makeTranslator: @Sendable (WhisperModelID) -> any BenchmarkTranslating
    var residentBytes: @Sendable () -> UInt64?
    var thermalState: @Sendable () -> ProcessInfo.ThermalState

    static func production(layout: ModelLayout) -> BenchmarkSeams {
        let factory = BenchmarkStimulusFactory.production()
        return BenchmarkSeams(
            makeStimulus: { try await factory.make() },
            makeTranslator: { WhisperKitTranslator(layout: layout, model: $0) },
            residentBytes: { MemoryMeter.residentBytes() },
            thermalState: { ProcessInfo.processInfo.thermalState }
        )
    }
}

/// One run's output before it becomes a `BenchmarkRun`: the sentence used and one result per model asked for.
struct BenchmarkOutcome: Sendable, Equatable {
    var sentence: BenchmarkSentence
    var results: [ModelBenchmarkResult]

    var measuredCount: Int { results.filter { !$0.isSkipped }.count }
    var cancelledCount: Int { results.filter { $0.skippedReason == BenchmarkSkipReason.cancelled }.count }
}

/// Runs the models strictly one at a time with `unload()` between them (M11 §5): the thermal state before each
/// (`.serious`/`.critical` skips it), `ContinuousClock` around the load, a first and a second (steady) translate,
/// `MemoryMeter` before and after, `SpeechGate.evaluate` on the output and its word error rate against the
/// reference, one `benchmark model=…` line per measured model under the `measurements` category.
actor BenchmarkRunner {
    static let passes = 2
    private static let logger = Logger(subsystem: "revox", category: "measurements")

    private let seams: BenchmarkSeams
    private let clock = ContinuousClock()
    private var isRunning = false

    init(seams: BenchmarkSeams) {
        self.seams = seams
    }

    /// Throws only when no stimulus could be made (`BenchmarkError.noSpeech`) or a run is already in progress
    /// (`BenchmarkError.busy`). A cancelled task returns the partial outcome with the rest marked cancelled.
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
                progress(.skipped(model, BenchmarkSkipReason.cancelled))
                continue
            }
            if Self.isTooHot(thermal) {
                results.append(.skipped(model, reason: BenchmarkSkipReason.tooHot, thermalState: thermal))
                progress(.skipped(model, BenchmarkSkipReason.tooHot))
                continue
            }
            switch await measure(model, stimulus: stimulus, thermal: thermal, progress: progress) {
            case .measured(let result):
                results.append(result)
                progress(.finished(model))
            case .failed(let reason):
                results.append(.skipped(model, reason: reason, thermalState: thermal))
                progress(.skipped(model, reason))
            case .cancelled:
                cancelled = true
                results.append(.skipped(model, reason: BenchmarkSkipReason.cancelled, thermalState: thermal))
                progress(.skipped(model, BenchmarkSkipReason.cancelled))
            }
        }
        return BenchmarkOutcome(sentence: stimulus.sentence, results: results)
    }

    private enum Measurement {
        case measured(ModelBenchmarkResult)
        case failed(String)
        case cancelled
    }

    private func measure(_ model: WhisperModelID, stimulus: BenchmarkStimulus, thermal: String,
                         progress: @escaping @Sendable (BenchmarkProgress) -> Void) async -> Measurement {
        let before = seams.residentBytes() ?? 0
        let translator = seams.makeTranslator(model)
        let loadStart = clock.now
        do {
            try await translator.load { message in progress(.loading(model, message)) }
        } catch {
            await translator.unload()
            return .failed(BenchmarkSkipReason.couldNotLoad(UserFacingErrorText.describe(error)))
        }
        let loadSeconds = Self.seconds(since: loadStart, clock: clock)
        var peak = max(before, seams.residentBytes() ?? before)
        var timings: [Double] = []
        var candidate = TranslationCandidate(language: stimulus.sentence.language, languageProbability: nil, segments: [])
        for pass in 1 ... Self.passes {
            if Task.isCancelled {
                await translator.unload()
                return .cancelled
            }
            progress(.translating(model, pass: pass))
            let start = clock.now
            do {
                candidate = try await translator.translate(stimulus.samples, language: stimulus.sentence.language)
            } catch {
                await translator.unload()
                return .failed(BenchmarkSkipReason.couldNotTranslate(UserFacingErrorText.describe(error)))
            }
            timings.append(Self.seconds(since: start, clock: clock))
            peak = max(peak, seams.residentBytes() ?? peak)
        }
        await translator.unload()
        // `WhisperKitTranslator` answers a cancelled decode with an empty candidate; it is never scored as a result.
        if Task.isCancelled { return .cancelled }
        let hypothesis = SpeechGate.evaluate(candidate)?.english ?? ""
        let result = ModelBenchmarkResult(
            model: model,
            loadSeconds: loadSeconds,
            firstSeconds: timings[0],
            steadySeconds: timings[Self.passes - 1],
            audioSeconds: stimulus.audioSeconds,
            wordErrorRate: WordErrorRate.rate(reference: stimulus.sentence.reference, hypothesis: hypothesis),
            residentBeforeMB: Int(before / 1_048_576),
            peakDeltaMB: Int((peak - before) / 1_048_576),
            thermalState: thermal,
            hypothesis: hypothesis
        )
        Self.logger.info("benchmark model=\(result.model.rawValue, privacy: .public) load_ms=\(Int(result.loadSeconds * 1000), privacy: .public) first_ms=\(Int(result.firstSeconds * 1000), privacy: .public) steady_ms=\(Int(result.steadySeconds * 1000), privacy: .public) audio_ms=\(Int(result.audioSeconds * 1000), privacy: .public) rtf=\(result.realTimeFactor, privacy: .public) wer=\(result.wordErrorRate, privacy: .public) resident_before_mb=\(result.residentBeforeMB, privacy: .public) peak_delta_mb=\(result.peakDeltaMB, privacy: .public) thermal=\(result.thermalState, privacy: .public)")
        return .measured(result)
    }

    // MARK: Pure helpers

    static func thermalText(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// The §9 thresholds `DegradationPolicy` uses: a serious or critical phone is not measured.
    static func isTooHot(_ thermal: String) -> Bool {
        thermal == "serious" || thermal == "critical"
    }

    static func seconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Double {
        (clock.now - start) / .seconds(1)
    }
}
