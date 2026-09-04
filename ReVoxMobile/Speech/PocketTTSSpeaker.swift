import Foundation
import FluidAudio
import os
import ReVoxCore

/// Kyutai pocket-tts through FluidAudio as a `Speaker` (§6.5, R6, R7): one `PocketTtsManager` with
/// `placement: .ane`, whole-phrase synthesis through `synthesizeDetailed`, un-normalised 24 kHz samples (the
/// player applies the fixed gain, §6.7). The three engine calls sit behind `Engine`, so the tests mirror
/// `test_tts.py` without a model; `make(voice:fluidBaseDirectory:)` builds the production engine.
///
/// The conformance names its module: FluidAudio exports a `Speaker` of its own (a diarisation identity), so
/// the bare name is ambiguous in any file that imports both.
actor PocketTTSSpeaker: ReVoxCore.Speaker {
    struct Engine: Sendable {
        var initialize: @Sendable () async throws -> Void
        var setVoice: @Sendable (String) -> Void
        var synthesize: @Sendable (_ text: String, _ voice: String) async throws -> [Float]

        /// `initialize()`, `setDefaultVoice(_:)` and `synthesizeDetailed` with the library defaults 0.7 / true / 50 (§6.5).
        static func production(manager: PocketTtsManager) -> Engine {
            Engine(
                initialize: {
                    try await manager.initialize()
                },
                setVoice: { voice in
                    Task { await manager.setDefaultVoice(voice) }
                },
                synthesize: { text, voice in
                    let result = try await manager.synthesizeDetailed(
                        text: text,
                        voice: voice,
                        temperature: 0.7,
                        deEss: true,
                        maxTokensPerChunk: 50
                    )
                    return result.samples   // de-essed, un-normalised
                }
            )
        }
    }

    /// `PocketTtsConstants.audioSampleRate` = 24 000; cached here, never re-queried from the engine (the Speaker contract).
    static let sampleRateHz: Int = PocketTtsConstants.audioSampleRate
    nonisolated let sampleRate: Int = PocketTTSSpeaker.sampleRateHz
    private static let logger = Logger(subsystem: "revox", category: "measurements")

    private let engine: Engine
    private(set) var voice: String
    private(set) var isLoaded = false
    private(set) var initializeCount = 0
    private var loadTask: Task<Void, Error>?

    /// `voice` outside `ModelCatalog.pocketTTS.offeredVoices` maps to "alba": only the offered voice files are
    /// guaranteed by the installed check, and a missing file would make the library fetch it (§6.5).
    init(voice: String, engine: Engine) {
        self.engine = engine
        self.voice = Self.offeredVoice(voice)
    }

    /// Production: the manager over `layout.fluidBaseDirectory` with the same directory / precision / placement
    /// triple as the download and the verified load (R5, R6), so `initialize()` hits the cache instead of fetching.
    static func make(voice: String, fluidBaseDirectory: URL) -> PocketTTSSpeaker {
        let manager = PocketTtsManager(
            defaultVoice: offeredVoice(voice),
            language: .english,
            directory: fluidBaseDirectory,
            precision: .fp16,
            placement: .ane
        )
        return PocketTTSSpeaker(voice: voice, engine: .production(manager: manager))
    }

    static func offeredVoice(_ voice: String) -> String {
        ModelCatalog.pocketTTS.offeredVoices.contains(voice) ? voice : PocketTtsConstants.defaultVoice
    }

    /// Idempotent and re-entrant: exactly one `initialize()` succeeds for the life of the actor; concurrent callers
    /// await the same load; a failed load can be retried.
    func load() async throws {
        if isLoaded { return }
        if let loadTask {
            try await loadTask.value
            return
        }
        initializeCount += 1
        let engine = self.engine
        let task = Task { try await engine.initialize() }
        loadTask = task
        let started = ContinuousClock.now
        do {
            try await task.value
            isLoaded = true
            // §13 Q6: the first load after an install pays the cold ANE compile; later loads should not.
            Self.logger.info("pocket-tts load ms=\(Int((ContinuousClock.now - started) / .milliseconds(1)), privacy: .public)")
            MemoryMeter.log("pocket-tts loaded")
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Windows `set_voice`: the next synthesis carries the new voice; the manager's default is updated too.
    func setVoice(_ voice: String) {
        let accepted = Self.offeredVoice(voice)
        self.voice = accepted
        engine.setVoice(accepted)
    }

    func synthesize(_ text: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)   // test_empty_text_skips_model
        }
        try await load()
        let started = ContinuousClock.now
        let samples = try await engine.synthesize(text, voice)
        let synthesisSeconds = (ContinuousClock.now - started) / .seconds(1)
        let audioSeconds = Double(samples.count) / Double(sampleRate)
        Self.logger.info("pocket-tts synthesis s=\(synthesisSeconds, privacy: .public) audio_s=\(audioSeconds, privacy: .public) rtf=\(audioSeconds > 0 ? synthesisSeconds / audioSeconds : 0, privacy: .public) resident_mb=\((MemoryMeter.residentBytes() ?? 0) / 1_048_576, privacy: .public)")
        return AudioClip(samples: samples, sampleRate: sampleRate)
    }
}
