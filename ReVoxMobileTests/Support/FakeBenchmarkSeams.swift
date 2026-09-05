import Foundation
import ReVoxCore
@testable import ReVoxMobile

/// The simulator's stand-in for the benchmark's device side (M11 §5): a fixed 2 s Spanish stimulus, one real
/// `WhisperKitTranslator` over a fake `WhisperEngine` per model (so the gate, the token filter and the
/// cancellation mapping are the production ones), a resident-memory counter that steps up on load, a thermal
/// queue read once per model, and a `hold` that freezes the run inside `makeStimulus` for state tests.
final class FakeBenchmarkSeams: @unchecked Sendable {
    struct LoadFailure: Error, CustomStringConvertible {
        var description: String { "boom" }
    }

    static let sentence = BenchmarkSentences.spanish
    static let samples = [Float](repeating: 0.1, count: 2 * AudioFormat.pipelineSampleRate)   // 2 s at 16 kHz
    static let megabyte: UInt64 = 1_048_576

    private let lock = NSLock()
    private var textsByModel: [WhisperModelID: String] = [:]
    private var thermalQueue: [ProcessInfo.ThermalState] = []
    private var failingLoads: Set<WhisperModelID> = []
    private var heldStimulus = false
    private var heldTranslate: Set<WhisperModelID> = []
    private var resident: UInt64 = 100 * FakeBenchmarkSeams.megabyte
    /// Whether the fake decode returns no word tokens (the gate then drops the candidate) for a model.
    private var wordless: Set<WhisperModelID> = []

    /// "load tiny", "translate tiny", "unload tiny", … in the order the runner drove them.
    let events = LockedBox<[String]>([])

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    /// The English each model "hears"; the reference itself when unset.
    func setText(_ text: String, for model: WhisperModelID) { locked { textsByModel[model] = text } }
    func setWordless(_ model: WhisperModelID) { locked { _ = wordless.insert(model) } }
    func setThermal(_ states: [ProcessInfo.ThermalState]) { locked { thermalQueue = states } }
    func failLoad(of model: WhisperModelID) { locked { _ = failingLoads.insert(model) } }

    var hold: Bool {
        get { locked { heldStimulus } }
        set { locked { heldStimulus = newValue } }
    }

    /// Freezes that model's translate calls; a cancelled task wakes from `Task.sleep` with a `CancellationError`.
    func holdTranslate(of model: WhisperModelID) { locked { _ = heldTranslate.insert(model) } }
    func releaseTranslate(of model: WhisperModelID) { locked { _ = heldTranslate.remove(model) } }
    private func isTranslateHeld(_ model: WhisperModelID) -> Bool { locked { heldTranslate.contains(model) } }

    var residentBytes: UInt64 { locked { resident } }

    private func nextThermal() -> ProcessInfo.ThermalState {
        locked { thermalQueue.isEmpty ? .nominal : thermalQueue.removeFirst() }
    }

    var seams: BenchmarkSeams {
        BenchmarkSeams(
            makeStimulus: { [self] in
                while self.hold { try await Task.sleep(nanoseconds: 10_000_000) }
                return BenchmarkStimulus(sentence: Self.sentence, samples: Self.samples)
            },
            makeTranslator: { [self] model in self.translator(for: model) },
            residentBytes: { [self] in self.residentBytes },
            thermalState: { [self] in self.nextThermal() }
        )
    }

    private func translator(for model: WhisperModelID) -> any BenchmarkTranslating {
        let fails = locked { failingLoads.contains(model) }
        let text = locked { textsByModel[model] ?? Self.sentence.reference }
        let noWords = locked { wordless.contains(model) }
        let engine = WhisperEngine(
            load: { [self] progress in
                self.events.mutate { $0.append("load \(model.rawValue)") }
                if fails { throw LoadFailure() }
                self.locked { self.resident += 100 * Self.megabyte }
                progress("Loading")
                return 50_257
            },
            detect: { _ in ("es", -0.1) },
            transcribe: { [self] _, _ in
                self.events.mutate { $0.append("translate \(model.rawValue)") }
                while self.isTranslateHeld(model) { try await Task.sleep(nanoseconds: 10_000_000) }
                let tokens = noWords ? [] : [WhisperTokenLogProb(token: 10, logProbability: -0.1)]
                return [WhisperSegmentSnapshot(text: " \(text)", noSpeechProbability: 0, tokenLogProbs: tokens)]
            },
            unload: { [self] in
                self.events.mutate { $0.append("unload \(model.rawValue)") }
                self.locked { self.resident = max(100 * Self.megabyte, self.resident - 100 * Self.megabyte) }
            }
        )
        return WhisperKitTranslator(engine: engine)
    }
}

extension BenchmarkRun {
    /// tiny and small measured, medium skipped as too hot: what the hosting and screenshot tests render.
    static func sample(date: Date = Date(timeIntervalSince1970: 1_700_000_000), device: String = "iPhone17,1",
                       whisperKitVersion: String = LibraryVersions.whisperKit) -> BenchmarkRun {
        BenchmarkRun(
            date: date, device: device, iOSVersion: "26.0.1", memoryTierGB: 8, whisperKitVersion: whisperKitVersion,
            sentence: BenchmarkSentences.spanish,
            results: [
                ModelBenchmarkResult(model: .tiny, loadSeconds: 0.4, firstSeconds: 0.9, steadySeconds: 0.3, audioSeconds: 3.8,
                                     wordErrorRate: 0.25, residentBeforeMB: 120, peakDeltaMB: 80, thermalState: "nominal",
                                     hypothesis: "Good morning, where is the bus stop?"),
                ModelBenchmarkResult(model: .small, loadSeconds: 3, firstSeconds: 1.2, steadySeconds: 0.9, audioSeconds: 3.8,
                                     wordErrorRate: 0.125, residentBeforeMB: 130, peakDeltaMB: 240, thermalState: "nominal",
                                     hypothesis: "Good morning, where is the bus station?"),
                .skipped(.medium, reason: BenchmarkSkipReason.tooHot, thermalState: "serious"),
            ]
        )
    }
}
