import CoreML
import Foundation
import ReVoxCore

/// `SpeechProbabilityModel` over the 512-sample Silero export (§6.3, R1). Serialises predictions and owns the LSTM state.
actor SileroVAD: SpeechProbabilityModel {
    typealias Predictor = @Sendable (_ input: [Float], _ hidden: [Float], _ cell: [Float]) throws -> SileroPrediction

    private let bundleURL: URL?
    private let computeUnits: MLComputeUnits
    private var predictor: Predictor?
    private var assembler = SileroInputAssembler()

    /// Production: `load()` compiles nothing (the bundle is `.mlmodelc`) and keeps one `MLModel`.
    init(bundleURL: URL, computeUnits: MLComputeUnits = .cpuOnly) {
        self.bundleURL = bundleURL
        self.computeUnits = computeUnits
    }

    /// Tests: an injected predictor, already "loaded".
    init(predictor: @escaping Predictor) {
        self.bundleURL = nil
        self.computeUnits = .cpuOnly
        self.predictor = predictor
    }

    var isLoaded: Bool { predictor != nil }

    func load() throws {
        guard predictor == nil, let bundleURL else { return }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let model = try MLModel(contentsOf: bundleURL, configuration: configuration)
        let coreML = try CoreMLSileroPredictor(model: model)
        predictor = { input, hidden, cell in try coreML.predict(input: input, hidden: hidden, cell: cell) }
    }

    func probability(of chunk: [Float]) async throws -> Float {
        guard let predictor else { throw SileroVADError.notLoaded }
        let input = try assembler.input(for: chunk)
        let output = try predictor(input, assembler.hidden, assembler.cell)
        // Defence in depth behind `RingReader`'s sanitising: a single non-finite value in the LSTM state is permanent.
        // Every later probability would be NaN, `probability >= speechThreshold` is false for NaN, so no phrase would
        // ever be detected again — and `Segmenter.reset()` runs once per pipeline start, so the run would stay
        // silently dead with no error anywhere (docs/security-review-m5.md finding 2). Dropping the poisoned state
        // costs one chunk of LSTM context; keeping it costs the session.
        guard output.probability.isFinite,
              output.hidden.allSatisfy({ $0.isFinite }),
              output.cell.allSatisfy({ $0.isFinite }) else {
            assembler.reset()
            return 0
        }
        try assembler.update(hidden: output.hidden, cell: output.cell)
        return output.probability
    }

    /// Called once per pipeline start through `Segmenter.reset()` (§5.1); never mid-run.
    func reset() async {
        assembler.reset()
    }
}
