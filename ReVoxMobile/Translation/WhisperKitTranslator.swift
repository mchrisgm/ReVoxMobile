import Foundation
import os
import ReVoxCore

enum WhisperTranslatorError: Error, Equatable, CustomStringConvertible {
    case notLoaded

    var description: String {
        switch self {
        case .notLoaded: return "Whisper model is not loaded"
        }
    }
}

/// `Translator` + `LanguageDetector` over one WhisperKit instance (§6.4, R2, R3). One call at a time.
actor WhisperKitTranslator: Translator, LanguageDetector, Transcriber {
    static let preparingMessage = "Preparing model…"
    private static let logger = Logger(subsystem: "revox", category: "whisper")

    private let engine: WhisperEngine
    private var specialTokenBegin: Int?
    /// nil in production (R3); the Task 42 device test sets WhisperKit's default −1.5 to compare outputs.
    private(set) var firstTokenLogProbThreshold: Float?

    init(engine: WhisperEngine) {
        self.engine = engine
    }

    init(layout: ModelLayout, model: WhisperModelID) {
        let descriptor = ModelCatalog.whisper(model)
        self.init(engine: WhisperEngine.production(modelFolder: layout.whisperFolder(descriptor), tokenizerFolder: layout.root))
    }

    var isLoaded: Bool { specialTokenBegin != nil }

    func setFirstTokenLogProbThreshold(_ threshold: Float?) {
        firstTokenLogProbThreshold = threshold
    }

    /// Runs before `pipeline.start` so a broken model never puts the pipeline in `.error` (§6.4, §9).
    func load(progress: @escaping @Sendable (String) -> Void) async throws {
        guard specialTokenBegin == nil else { return }
        progress(Self.preparingMessage)
        specialTokenBegin = try await engine.load(progress)
    }

    func unload() async {
        await engine.unload()
        specialTokenBegin = nil
    }

    // MARK: LanguageDetector (R2)

    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection {
        guard isLoaded else { throw WhisperTranslatorError.notLoaded }
        let result = try await engine.detect(audio)
        let probability = Self.probability(fromLogProbability: result.logProbability)
        let raw = exp(result.logProbability)
        if raw < 0 || raw > 1 {
            Self.logger.error("language probability outside [0, 1]: exp(\(result.logProbability, privacy: .public)) = \(raw, privacy: .public)")
        }
        Self.logger.info("language=\(result.language, privacy: .public) probability=\(probability, privacy: .public)")
        return LanguageDetection(language: result.language, probability: probability)
    }

    static func probability(fromLogProbability logProbability: Float) -> Float {
        let value = exp(logProbability)
        guard value.isFinite else { return logProbability < 0 ? 0 : 1 }
        return min(max(value, 0), 1)
    }

    // MARK: Translator (R3)

    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate {
        try await run(audio, language: language, task: "translate")
    }

    // MARK: Transcriber (M8, §8.2)

    /// The same decode with Whisper's transcribe task, so the words come back in the language they were spoken
    /// in. Only the second direction of a two-way conversation asks for this.
    func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate {
        try await run(audio, language: language, task: "transcribe")
    }

    private func run(_ audio: [Float], language: String, task: String) async throws -> TranslationCandidate {
        guard let specialTokenBegin else { throw WhisperTranslatorError.notLoaded }
        var spec = WhisperDecodingSpec(language: language, task: task)
        spec.firstTokenLogProbThreshold = firstTokenLogProbThreshold
        let snapshots: [WhisperSegmentSnapshot]
        do {
            snapshots = try await engine.transcribe(audio, spec)
        } catch is CancellationError {
            return TranslationCandidate(language: language, languageProbability: nil, segments: [])
        }
        let segments = snapshots.map { snapshot in
            TranslationSegment(
                text: snapshot.text,
                noSpeechProbability: snapshot.noSpeechProbability,
                averageLogProbability: Self.averageLogProbability(of: snapshot.tokenLogProbs, specialTokenBegin: specialTokenBegin)
            )
        }
        return TranslationCandidate(language: language, languageProbability: nil, segments: segments)
    }

    /// Mean log-probability over word tokens only (ids below `specialTokenBegin`); WhisperKit's `avgLogprob`
    /// averages in the zero-valued prefill and end tokens (API §4). No word tokens → −∞ (dropped by the gate).
    static func averageLogProbability(of tokens: [WhisperTokenLogProb], specialTokenBegin: Int) -> Float {
        let words = tokens.filter { $0.token < specialTokenBegin }
        guard !words.isEmpty else { return -.infinity }
        return words.reduce(0) { $0 + $1.logProbability } / Float(words.count)
    }
}
