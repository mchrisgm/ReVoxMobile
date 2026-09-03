import Foundation
import os
import ReVoxCore

/// Logs per-call durations, the detection probability and the per-segment log-probabilities for the M3
/// measurement record (§13 Q2, Q4; `docs/measurements/m3-microphone-mode.md`). Pure pass-through otherwise.
actor TimedTranslator: Translator, LanguageDetector {
    private static let logger = Logger(subsystem: "revox", category: "measurements")
    private let inner: WhisperKitTranslator
    private let clock = ContinuousClock()

    init(_ inner: WhisperKitTranslator) {
        self.inner = inner
    }

    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection {
        let start = clock.now
        let detection = try await inner.detectLanguage(in: audio)
        let milliseconds = Self.milliseconds(since: start, clock: clock)
        Self.logger.info("detect ms=\(milliseconds, privacy: .public) samples=\(audio.count, privacy: .public) language=\(detection.language, privacy: .public) probability=\(detection.probability, privacy: .public)")
        return detection
    }

    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate {
        let start = clock.now
        let candidate = try await inner.translate(audio, language: language)
        let milliseconds = Self.milliseconds(since: start, clock: clock)
        let minimum = candidate.segments.map(\.averageLogProbability).min() ?? 0
        let characters = candidate.segments.reduce(0) { $0 + $1.text.count }
        Self.logger.info("translate ms=\(milliseconds, privacy: .public) samples=\(audio.count, privacy: .public) segments=\(candidate.segments.count, privacy: .public) minAvgLogProb=\(minimum, privacy: .public) chars=\(characters, privacy: .public)")
        return candidate
    }

    private static func milliseconds(since start: ContinuousClock.Instant, clock: ContinuousClock) -> Int {
        let elapsed = clock.now - start
        return Int(elapsed / .milliseconds(1))
    }
}
