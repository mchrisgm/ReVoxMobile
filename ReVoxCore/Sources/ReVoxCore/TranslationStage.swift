import Foundation

public struct LanguageDetection: Sendable, Equatable {
    public var language: String
    public var probability: Float

    public init(language: String, probability: Float) {
        self.language = language
        self.probability = probability
    }
}

public protocol LanguageDetector: Sendable {
    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection
}

public protocol Translator: Sendable {
    /// `language` is the pinned or detected code; never nil at this level.
    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate
}

/// Binds `LanguageDetector` and `Translator` the way Windows' single `transcribe()` call did, so the Windows STT
/// tests mirror one-to-one. Deviation W2: when the language-probability gate fails the translator is not called.
public struct TranslationStage: Sendable {
    private let detector: any LanguageDetector
    private let translator: any Translator
    private let pinnedLanguage: String?

    public init(detector: any LanguageDetector, translator: any Translator, pinnedLanguage: String?) {
        self.detector = detector
        self.translator = translator
        self.pinnedLanguage = pinnedLanguage
    }

    /// nil = dropped by a gate (no transcript entry, nothing spoken).
    public func translate(_ audio: [Float]) async throws -> Translation? {
        var detection: LanguageDetection?
        let language: String
        if let pinnedLanguage {
            language = pinnedLanguage
        } else {
            let detected = try await detector.detectLanguage(in: audio)
            guard SpeechGate.languagePasses(probability: detected.probability) else { return nil }
            detection = detected
            language = detected.language
        }
        var candidate = try await translator.translate(audio, language: language)
        candidate.languageProbability = detection?.probability
        return SpeechGate.evaluate(candidate)
    }
}
