import Foundation
@testable import ReVoxCore

/// The Windows `fake_vad`: `mean(|x|) > 0.1 → 1.0 else 0.0`. Counts calls and resets.
actor EnergyVAD: SpeechProbabilityModel {
    private(set) var callCount = 0
    private(set) var resetCount = 0
    private let fail: Bool

    /// `fail` makes every `probability(of:)` throw (a Core ML prediction that failed).
    init(fail: Bool = false) {
        self.fail = fail
    }

    func probability(of chunk: [Float]) async throws -> Float {
        callCount += 1
        if fail {
            throw FakeTranslatorError()
        }
        guard !chunk.isEmpty else { return 0 }
        let mean = chunk.reduce(0) { $0 + abs($1) } / Float(chunk.count)
        return mean > 0.1 ? 1.0 : 0.0
    }

    func reset() async {
        resetCount += 1
    }
}
