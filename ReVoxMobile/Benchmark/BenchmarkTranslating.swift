import Foundation
import ReVoxCore

/// The slice of `WhisperKitTranslator` the benchmark drives (M11 §5): a protocol, so the simulator tests run the
/// runner over a fake and never need a model.
protocol BenchmarkTranslating: Sendable {
    func load(progress: @escaping @Sendable (String) -> Void) async throws
    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate
    func unload() async
}

extension WhisperKitTranslator: BenchmarkTranslating {}
