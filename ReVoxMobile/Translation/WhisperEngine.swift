import Foundation
import ReVoxCore
import WhisperKit

struct WhisperTokenLogProb: Equatable, Sendable {
    var token: Int
    var logProbability: Float
}

/// The value-typed view of a `TranscriptionSegment` the adapter needs (§6.4).
struct WhisperSegmentSnapshot: Equatable, Sendable {
    var text: String
    var noSpeechProbability: Float
    var tokenLogProbs: [WhisperTokenLogProb]
}

/// The R3 decoding options, verbatim (§6.4). Only `language` varies; `firstTokenLogProbThreshold` is nil in
/// production and set only by the device measurement test (Task 42).
struct WhisperDecodingSpec: Equatable, Sendable {
    var task = "translate"
    var language: String
    var temperature: Float = 0.0
    var temperatureFallbackCount = 0
    var usePrefillPrompt = true
    var detectLanguage = false
    var skipSpecialTokens = true
    var withoutTimestamps = true
    var wordTimestamps = false
    var windowClipTime: Float = 0
    var compressionRatioThreshold: Float? = nil
    var logProbThreshold: Float? = nil
    var firstTokenLogProbThreshold: Float? = nil
    var noSpeechThreshold: Float? = nil
    var chunkingStrategy = "none"

    init(language: String) {
        self.language = language
    }

    var decodingOptions: DecodingOptions {
        DecodingOptions(
            task: .translate,
            language: language,
            temperature: temperature,
            temperatureFallbackCount: temperatureFallbackCount,
            usePrefillPrompt: usePrefillPrompt,
            detectLanguage: detectLanguage,
            skipSpecialTokens: skipSpecialTokens,
            withoutTimestamps: withoutTimestamps,
            wordTimestamps: wordTimestamps,
            windowClipTime: windowClipTime,
            compressionRatioThreshold: compressionRatioThreshold,
            logProbThreshold: logProbThreshold,
            firstTokenLogProbThreshold: firstTokenLogProbThreshold,
            noSpeechThreshold: noSpeechThreshold,
            chunkingStrategy: ChunkingStrategy.none
        )
    }
}

/// Holds the one non-Sendable `WhisperKit`; only the translator actor's serialised closures touch it.
final class WhisperKitBox: @unchecked Sendable {
    var kit: WhisperKit?
}

/// The WhisperKit calls of §6.4 behind closures; `production` is the only place the app constructs `WhisperKit`.
struct WhisperEngine: Sendable {
    /// Prewarm + load; reports model-state descriptions; returns `specialTokens.specialTokenBegin`.
    var load: @Sendable (_ progress: @escaping @Sendable (String) -> Void) async throws -> Int
    /// `detectLangauge(audioArray:)`: the argmax language and its log-probability.
    var detect: @Sendable (_ audio: [Float]) async throws -> (language: String, logProbability: Float)
    var transcribe: @Sendable (_ audio: [Float], _ spec: WhisperDecodingSpec) async throws -> [WhisperSegmentSnapshot]
    var unload: @Sendable () async -> Void

    static func production(modelFolder: URL, tokenizerFolder: URL) -> WhisperEngine {
        let box = WhisperKitBox()
        return WhisperEngine(
            load: { progress in
                if box.kit == nil {
                    let config = WhisperKitConfig(
                        modelFolder: modelFolder.path,
                        tokenizerFolder: tokenizerFolder,
                        computeOptions: ModelComputeOptions(),
                        verbose: false,
                        logLevel: .error,
                        prewarm: false,
                        load: false,
                        download: false
                    )
                    let kit = try await WhisperKit(config)
                    kit.modelStateCallback = { _, newState in progress(newState.description) }
                    try await kit.prewarmModels()
                    try await kit.loadModels()
                    box.kit = kit
                }
                guard let kit = box.kit, let tokenizer = kit.tokenizer else {
                    throw WhisperError.tokenizerUnavailable()
                }
                return tokenizer.specialTokens.specialTokenBegin
            },
            detect: { audio in
                guard let kit = box.kit else { throw WhisperError.modelsUnavailable() }
                let result = try await kit.detectLangauge(audioArray: audio)
                return (language: result.language, logProbability: result.langProbs[result.language] ?? -Float.infinity)
            },
            transcribe: { audio, spec in
                guard let kit = box.kit else { throw WhisperError.modelsUnavailable() }
                let results = try await kit.transcribe(audioArray: audio, decodeOptions: spec.decodingOptions)
                return results.flatMap(\.segments).map { segment in
                    WhisperSegmentSnapshot(
                        text: segment.text,
                        noSpeechProbability: segment.noSpeechProb,
                        tokenLogProbs: segment.tokenLogProbs.flatMap { entry in
                            entry.map { WhisperTokenLogProb(token: $0.key, logProbability: $0.value) }
                        }
                    )
                }
            },
            unload: {
                if let kit = box.kit {
                    await kit.unloadModels()
                }
                box.kit = nil
            }
        )
    }
}
