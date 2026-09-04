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
    /// `language` is the pinned or detected code; never nil at this level. Whisper's translate task, so the
    /// result is always English whatever the source language is.
    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate
}

/// Whisper's *transcribe* task: the words as spoken, in the language they were spoken in (M8, second direction).
/// The default implementation is the translate task, so a host that has not adopted two-way keeps working.
public protocol Transcriber: Sendable {
    func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate
}

/// Text-to-text translation into a language Whisper cannot produce (M8).
///
/// Whisper's translate task emits English and nothing else, so the second direction of a two-way conversation —
/// English out to the other person's language — needs a separate engine. `nil` means "this pair is not available
/// here"; the phrase is still transcribed in the language it was spoken in, and nothing is spoken for it.
public protocol SecondaryTranslator: Sendable {
    func translate(_ text: String, from source: String, to target: String) async throws -> String?
}

/// How a phrase was routed, so a caller can explain what happened without re-deriving it.
public enum TranslationRoute: Sendable, Equatable {
    /// Translated into English by Whisper — the one-way path, and every phrase that is not the ignored language.
    case toEnglish
    /// The ignored language with two-way off: dropped before the translator was called.
    case ignored
    /// The ignored language with two-way on, transcribed and translated into the target language.
    case toTarget(String)
    /// The ignored language with two-way on, transcribed, but no engine could reach the target language.
    /// The transcript keeps the phrase as spoken; nothing is spoken back.
    case transcribedOnly(reason: String)
}

public struct RoutedTranslation: Sendable, Equatable {
    public var translation: Translation
    public var route: TranslationRoute
    /// False when the phrase is for the transcript only (`transcribedOnly`).
    public var isSpoken: Bool

    public init(translation: Translation, route: TranslationRoute, isSpoken: Bool) {
        self.translation = translation
        self.route = route
        self.isSpoken = isSpoken
    }
}

/// Binds `LanguageDetector` and `Translator` the way Windows' single `transcribe()` call did, so the Windows STT
/// tests mirror one-to-one. Deviation W2: when the language-probability gate fails the translator is not called.
///
/// M8 adds the two-way routing of §8.2 on top, without changing the one-way path: with no ignored language
/// configured, every phrase takes exactly the route it took before.
public struct TranslationStage: Sendable {
    private let detector: any LanguageDetector
    private let translator: any Translator
    private let transcriber: (any Transcriber)?
    private let secondary: (any SecondaryTranslator)?
    private let pinnedLanguage: String?
    private let ignoredLanguage: String?
    private let twoWay: Bool
    private let targetLanguage: String?
    private let wantsOriginal: Bool

    public init(detector: any LanguageDetector, translator: any Translator, pinnedLanguage: String?,
                transcriber: (any Transcriber)? = nil, secondary: (any SecondaryTranslator)? = nil,
                ignoredLanguage: String? = nil, twoWay: Bool = false, targetLanguage: String? = nil,
                wantsOriginal: Bool = false) {
        self.wantsOriginal = wantsOriginal
        self.detector = detector
        self.translator = translator
        self.transcriber = transcriber
        self.secondary = secondary
        self.pinnedLanguage = pinnedLanguage
        self.ignoredLanguage = ignoredLanguage
        self.twoWay = twoWay
        self.targetLanguage = targetLanguage
    }

    /// nil = dropped by a gate or by the ignored-language rule (no transcript entry, nothing spoken).
    public func translate(_ audio: [Float]) async throws -> Translation? {
        try await route(audio)?.translation
    }

    /// The same decision with the reason attached (M8). The pipeline uses this so it can transcribe a phrase it
    /// is not going to speak.
    public func route(_ audio: [Float]) async throws -> RoutedTranslation? {
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

        // §8.2: the language the user asked ReVox to leave alone.
        if let ignoredLanguage, language == ignoredLanguage {
            guard twoWay else { return nil }             // not translated, not transcribed
            return try await secondDirection(audio, language: language, probability: detection?.probability)
        }

        var candidate = try await translator.translate(audio, language: language)
        candidate.languageProbability = detection?.probability
        guard var translation = SpeechGate.evaluate(candidate) else { return nil }
        translation.original = await originalIfWanted(audio, language: language, english: translation.english)
        return RoutedTranslation(translation: translation, route: .toEnglish, isSpoken: true)
    }

    /// M9 Learning mode: the words as spoken. English needs no second decode — the translation *is* the words —
    /// and a transcribe failure costs nothing but the original: learning must never lose a phrase.
    private func originalIfWanted(_ audio: [Float], language: String, english: String) async -> String {
        guard wantsOriginal else { return "" }
        if language == "en" { return english }
        guard let transcriber else { return "" }
        guard let candidate = try? await transcriber.transcribe(audio, language: language) else { return "" }
        let parts = candidate.segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return SpokenText.clean(parts.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// The ignored language with two-way on: transcribe it as spoken, then translate that text into the target.
    /// With no target (or English as the target) Whisper's own translate task is the engine, because it already
    /// produces English — the second direction then costs nothing extra.
    private func secondDirection(_ audio: [Float], language: String, probability: Float?) async throws -> RoutedTranslation? {
        guard let targetLanguage, targetLanguage != "en" else {
            var candidate = try await translator.translate(audio, language: language)
            candidate.languageProbability = probability
            guard let translation = SpeechGate.evaluate(candidate) else { return nil }
            return RoutedTranslation(translation: translation, route: .toEnglish, isSpoken: true)
        }

        let source = transcriber ?? TranslateTaskTranscriber(translator: translator)
        var candidate = try await source.transcribe(audio, language: language)
        candidate.languageProbability = probability
        guard let spoken = SpeechGate.evaluate(candidate) else { return nil }

        guard let secondary else {
            return RoutedTranslation(translation: Translation(english: spoken.english, language: language, spokenLanguage: language),
                                     route: .transcribedOnly(reason: Self.noEngineReason), isSpoken: false)
        }
        guard let translated = try await secondary.translate(spoken.english, from: language, to: targetLanguage) else {
            return RoutedTranslation(translation: Translation(english: spoken.english, language: language, spokenLanguage: language),
                                     route: .transcribedOnly(reason: Self.unavailablePairReason(from: language, to: targetLanguage)),
                                     isSpoken: false)
        }
        let cleaned = SpokenText.clean(translated)
        guard !cleaned.isEmpty else { return nil }
        // Tagged with the language the text is written in, not the one it came from: a transcript reader — and the
        // export — sees "[fr] Bonjour", which is what was said to the other person. `route` keeps the direction.
        // The words as spoken were transcribed anyway, so Learning mode gets them for free here.
        return RoutedTranslation(translation: Translation(english: cleaned, language: targetLanguage, spokenLanguage: targetLanguage,
                                                          original: wantsOriginal ? spoken.english : ""),
                                 route: .toTarget(targetLanguage), isSpoken: true)
    }

    public static let noEngineReason = "This iPhone has no on-device translator for the second direction"

    public static func unavailablePairReason(from source: String, to target: String) -> String {
        "No on-device translation from \(source) to \(target)"
    }
}

/// The fallback source for the second direction when the host has not supplied a transcribe-task seam: Whisper's
/// translate task. Its output is English rather than the language as spoken, which the target-language engine can
/// still translate — a lower-fidelity path, never a broken one.
struct TranslateTaskTranscriber: Transcriber {
    let translator: any Translator

    func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate {
        try await translator.translate(audio, language: language)
    }
}
