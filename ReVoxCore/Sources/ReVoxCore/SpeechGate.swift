import Foundation

/// One decoded segment as the translator reports it (faster-whisper `Segment` fields the gates read).
public struct TranslationSegment: Sendable, Equatable {
    public var text: String
    public var noSpeechProbability: Float        // seg.no_speech_prob (WhisperKit: always 0, documented)
    public var averageLogProbability: Float      // seg.avg_logprob recomputed over word tokens (R3)

    public init(text: String, noSpeechProbability: Float, averageLogProbability: Float) {
        self.text = text
        self.noSpeechProbability = noSpeechProbability
        self.averageLogProbability = averageLogProbability
    }
}

/// The translator's output for one phrase before the gates (faster-whisper `segments, info`).
public struct TranslationCandidate: Sendable, Equatable {
    public var language: String                  // info.language
    public var languageProbability: Float?       // info.language_probability; nil when pinned (gate skipped)
    public var segments: [TranslationSegment]

    public init(language: String, languageProbability: Float?, segments: [TranslationSegment]) {
        self.language = language
        self.languageProbability = languageProbability
        self.segments = segments
    }
}

/// Port of `revox/pipeline/stt.py:Translation`.
public struct Translation: Sendable, Equatable, Codable {
    /// The text ReVox says and stores. Named for the one-way case it was born in; with two-way on (M8) the
    /// second direction puts its target-language text here, and `spokenLanguage` says which language that is.
    public var english: String
    /// The language that was heard.
    public var language: String
    /// The language `english` is written in: "en" for every one-way phrase, the chosen target for the second
    /// direction of a two-way conversation. The speaker picks its voice from this.
    public var spokenLanguage: String
    /// M9 Learning mode: the words as spoken, in `language`. "" unless learning asked for them — a transcribe
    /// pass costs a second decode per phrase, so it is never run unasked.
    public var original: String
    /// M11: the gates were unsure (an auto-detected language below `SpeechGate.languageProbMin`, or only text
    /// between `guessLogProbFloor` and `averageLogProbMin`). Shown greyed, never spoken.
    public var isGuess: Bool

    public init(english: String, language: String, spokenLanguage: String = "en", original: String = "", isGuess: Bool = false) {
        self.english = english
        self.language = language
        self.spokenLanguage = spokenLanguage
        self.original = original
        self.isGuess = isGuess
    }

    enum CodingKeys: String, CodingKey {
        case english, language, spokenLanguage, original, isGuess
    }

    /// A transcript written before M8 has no `spokenLanguage` (those entries were all English); before M9 no
    /// `original`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        english = try container.decode(String.self, forKey: .english)
        language = try container.decode(String.self, forKey: .language)
        spokenLanguage = try container.decodeIfPresent(String.self, forKey: .spokenLanguage) ?? "en"
        original = try container.decodeIfPresent(String.self, forKey: .original) ?? ""
        isGuess = try container.decodeIfPresent(Bool.self, forKey: .isGuess) ?? false
    }
}

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

/// Port of the gating in `revox/pipeline/stt.py:Translator.translate`. Constants and the hallucination set are verbatim.
public enum SpeechGate {
    public static let noSpeechMax: Float = 0.85          // NO_SPEECH_MAX
    public static let averageLogProbMin: Float = -1.2    // AVG_LOGPROB_MIN
    public static let languageProbMin: Float = 0.4       // LANGUAGE_PROB_MIN
    /// M11 (not a Windows constant): a segment whose average log-probability is below this is noise, not a guess.
    /// Between the floor and `averageLogProbMin` it is an unsure part; the escape hatch if unsure rows prove noisy.
    public static let guessLogProbFloor: Float = -2.5
    public static let hallucinationPhrases: Set<String> = [  // HALLUCINATION_PHRASES
        "", "you", "thanks for watching", "thank you for watching",
        "subtitles by the amara.org community", "subscribe",
    ]

    /// Python `string.punctuation` + `string.whitespace` + "!¡¿?" (40 distinct characters).
    public static let strippedCharacters: Set<Character> = {
        var set = Set<Character>()
        for scalar in "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars {   // string.punctuation
            set.insert(Character(scalar))
        }
        for whitespace in [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"] as [Character] {   // string.whitespace
            set.insert(whitespace)
        }
        for extra in ["!", "¡", "¿", "?"] as [Character] {
            set.insert(extra)
        }
        return set
    }()

    /// `text.lower().strip(strippedCharacters)`: lowercase, then remove characters from both ends while they are
    /// in the set. Works on unicode scalars so that "\r\n" is stripped as two characters, as Python does.
    public static func normalize(_ text: String) -> String {
        let scalars = Array(text.lowercased().unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end, strippedCharacters.contains(Character(scalars[start])) {
            start += 1
        }
        while end > start, strippedCharacters.contains(Character(scalars[end - 1])) {
            end -= 1
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[start ..< end])
        return String(view)
    }

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

    /// Python `str.strip()` with no argument: whitespace from both ends.
    static func pythonStrip(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
