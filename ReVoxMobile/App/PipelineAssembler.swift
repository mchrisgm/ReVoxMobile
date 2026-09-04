import Foundation
import SwiftData
import ReVoxCore

/// A successful build: the core pipeline plus the source it captures from (the keep-alive monitor reads the
/// source's capture position). `pipeline` is optional only so the simulator tests can construct the value.
struct BuiltPipeline: Sendable {
    let pipeline: TranslationPipeline?
    let source: any AudioSource
}

/// The composition root (§4.2, A6) for both sources: adapters + core pipeline for one settings snapshot. The speaker
/// side comes from `SpeakerAssembly`; ducking goes through the session controller with `duckingEnabled =
/// settings.ducking` (F12); the keep-alive monitor of §6.8 wraps every run; the capture source follows `settings.capture`.
@MainActor
final class PipelineAssembler {
    private let layout: ModelLayout
    private let sessionController: AudioSessionController
    private let transcriptContainer: ModelContainer
    private let speakerAssembly: SpeakerAssembly
    private let keepAlive: KeepAliveMonitor
    private let sources: CaptureSources

    init(layout: ModelLayout, sessionController: AudioSessionController, transcriptContainer: ModelContainer,
         speakerAssembly: SpeakerAssembly, keepAlive: KeepAliveMonitor, sources: CaptureSources) {
        self.layout = layout
        self.sessionController = sessionController
        self.transcriptContainer = transcriptContainer
        self.speakerAssembly = speakerAssembly
        self.keepAlive = keepAlive
        self.sources = sources
    }

    func supplier() -> PipelineSupplier {
        let layout = self.layout
        let controller = self.sessionController
        let container = self.transcriptContainer
        let assembly = self.speakerAssembly
        let monitor = self.keepAlive
        let sources = self.sources
        let speakers = assembly.bundle(controller: controller)
        return { settings, progress in
            let built = try await PipelineAssembler.build(settings: settings, layout: layout, sessionController: controller,
                                                          transcriptContainer: container, speakers: speakers, sources: sources, progress: progress)
            guard let pipeline = built.pipeline else { throw PipelineBuildError.vadLoadFailed("no pipeline was built") }
            let source = built.source
            let isBroadcast = settings.capture == .broadcast
            // Per run, not per build: `LiveViewModel` caches the pipeline across restarts (`start()` calls this supplier
            // only when the model, latency mode or capture mode changed), so installing the ring-overrun handler here
            // once would leave it nil from the second run on — no drop marker, no "Falling behind" badge (§6.2, §5.4, §9).
            // `onStart` re-arms it on every run; `onStop` releases it again; `[weak pipeline]` keeps a stopped, dropped
            // pipeline (with its WhisperKit model, speaker and player) from being resurrected by a late overrun.
            let install: @Sendable () -> Void = { [weak pipeline] in
                guard isBroadcast else {
                    sources.setBroadcastGapHandler(nil)
                    return
                }
                let handler: @Sendable (Int) async -> Void = { _ in await pipeline?.noteCaptureGap() }
                sources.setBroadcastGapHandler(handler)
            }
            let monitored = MonitoredPipeline(pipeline: pipeline, monitor: monitor, position: { await source.capturePosition() },
                                              onStart: install,
                                              onStop: { sources.setBroadcastGapHandler(nil) })
            return await assembly.wrap(monitored)
        }
    }

    nonisolated static func sessionMetadata(for settings: Settings, startedAt: Date, voice: String, joinedInProgress: Bool = false) -> SessionMetadata {
        SessionMetadata(
            startedAt: startedAt,
            captureMode: settings.capture,
            pinnedLanguage: settings.language,
            modelID: settings.whisperModel.rawValue,
            voice: voice,
            joinedInProgress: joinedInProgress
        )
    }

    nonisolated static func build(settings: Settings, layout: ModelLayout, sessionController: AudioSessionController,
                                  transcriptContainer: ModelContainer, speakers: SpeakerBundle, sources: CaptureSources,
                                  progress: @escaping @Sendable (String) -> Void) async throws -> BuiltPipeline {
        // 1. Session first, in the foreground (§6.8): the resident mask of the selected mode.
        try await sessionController.configure(for: settings.capture)

        // 2. Models before the pipeline exists (§6.4, §9): a load failure is a banner, never a pipeline error.
        let vad = SileroVAD(bundleURL: layout.vadBundle)
        do {
            try await vad.load()
        } catch {
            throw PipelineBuildError.vadLoadFailed(String(describing: error))
        }
        let whisper = WhisperKitTranslator(layout: layout, model: settings.whisperModel)
        do {
            try await whisper.load(progress: progress)
        } catch {
            throw PipelineBuildError.whisperLoadFailed(model: settings.whisperModel, reason: String(describing: error))
        }
        let translator = TimedTranslator(whisper)

        // 3. Adapters. The source follows the capture mode (§4.2); the speaker side comes from the assembly (R11, §6.5, §6.7).
        let isBroadcast = settings.capture == .broadcast
        let source: any AudioSource = isBroadcast ? sources.makeBroadcast() : sources.makeMicrophone(sessionController)
        let transcriptFactory: TranscriptSinkFactory = {
            let joined = isBroadcast ? sources.broadcastJoinedInProgress() : false
            return TranscriptStore(modelContainer: transcriptContainer,
                                   metadata: PipelineAssembler.sessionMetadata(for: settings, startedAt: Date(), voice: speakers.voiceName(),
                                                                               joinedInProgress: joined))
        }

        // In broadcast mode every speaking edge also reaches the capture for the self-capture probe; the core
        // pipeline's own edge handling is untouched. This runs on the player's audio-completion thread, so both
        // calls must be non-blocking: `noteBroadcastSpeakingEdge` only yields into the capture's edge stream, which
        // stamps the ring writeCursor on its own drain task (§4.3). The wrapper is bound to its own local first:
        // a multi-statement closure literal inside a ternary branch does not type-check.
        let wrappedFactory: AudioPlayerFactory = { sampleRate, onSpeaking in
            speakers.playerFactory(sampleRate) { speaking in
                sources.noteBroadcastSpeakingEdge(speaking)
                onSpeaking(speaking)
            }
        }
        let playerFactory: AudioPlayerFactory = isBroadcast ? wrappedFactory : speakers.playerFactory

        // 4. The core pipeline; the session controller is the Ducker (§6.8), enabled by `LiveViewModel.configuration`.
        let dependencies = PipelineDependencies(
            source: source,
            vad: vad,
            detector: translator,
            translator: translator,
            speaker: speakers.speaker,
            playerFactory: playerFactory,
            ducker: sessionController,
            transcriptFactory: transcriptFactory
        )
        // The ring-overrun handler (§6.2 `.gap` → drop marker + `.lag`) is NOT installed here: `build` runs once per
        // pipeline, `start()` runs once per run, and a cached pipeline is restarted many times. `supplier()` installs
        // it from `MonitoredPipeline.onStart` and releases it from `onStop` instead.
        let pipeline = TranslationPipeline(dependencies: dependencies)
        return BuiltPipeline(pipeline: pipeline, source: source)
    }
}
