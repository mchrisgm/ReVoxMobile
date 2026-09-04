import Foundation
import SwiftData
import ReVoxCore

/// The composition root (§4.2, A6): adapters + core pipeline for one settings snapshot, microphone mode (M5 adds
/// `BroadcastCapture` by mode). The speaker side comes from `SpeakerAssembly`; ducking goes through the session
/// controller with `duckingEnabled = settings.ducking` in the configuration (F12).
@MainActor
final class PipelineAssembler {
    private let layout: ModelLayout
    private let sessionController: AudioSessionController
    private let transcriptContainer: ModelContainer
    private let speakerAssembly: SpeakerAssembly

    init(layout: ModelLayout, sessionController: AudioSessionController, transcriptContainer: ModelContainer, speakerAssembly: SpeakerAssembly) {
        self.layout = layout
        self.sessionController = sessionController
        self.transcriptContainer = transcriptContainer
        self.speakerAssembly = speakerAssembly
    }

    func supplier() -> PipelineSupplier {
        let layout = self.layout
        let controller = self.sessionController
        let container = self.transcriptContainer
        let assembly = self.speakerAssembly
        let speakers = assembly.bundle(controller: controller)
        return { settings, progress in
            let pipeline = try await PipelineAssembler.build(settings: settings, layout: layout, sessionController: controller,
                                                            transcriptContainer: container, speakers: speakers, progress: progress)
            return await assembly.wrap(pipeline)
        }
    }

    nonisolated static func sessionMetadata(for settings: Settings, startedAt: Date, voice: String) -> SessionMetadata {
        SessionMetadata(
            startedAt: startedAt,
            captureMode: settings.capture,
            pinnedLanguage: settings.language,
            modelID: settings.whisperModel.rawValue,
            voice: voice,
            joinedInProgress: false
        )
    }

    nonisolated static func build(settings: Settings, layout: ModelLayout, sessionController: AudioSessionController,
                                  transcriptContainer: ModelContainer, speakers: SpeakerBundle,
                                  progress: @escaping @Sendable (String) -> Void) async throws -> TranslationPipeline {
        // 1. Session first, in the foreground (§6.8).
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

        // 3. Adapters. The speaker, the player factory and the voice name come from the assembly (R11, §6.5, §6.7).
        // The capture source's status line ("No microphone input", §6.1) rides the controller's SessionEvent
        // stream, which `LiveViewModel.observe(sessionEvents:)` already renders; `onStatus` defaults to a no-op,
        // so omitting it here would silently drop that line.
        let source = MicrophoneCapture(controller: sessionController, onStatus: { status in
            Task { await sessionController.publishCaptureStatus(status) }
        })
        let transcriptFactory: TranscriptSinkFactory = {
            TranscriptStore(modelContainer: transcriptContainer,
                            metadata: PipelineAssembler.sessionMetadata(for: settings, startedAt: Date(), voice: speakers.voiceName()))
        }

        // 4. The core pipeline; the session controller is the Ducker (§6.8), enabled by `LiveViewModel.configuration`.
        let dependencies = PipelineDependencies(
            source: source,
            vad: vad,
            detector: translator,
            translator: translator,
            speaker: speakers.speaker,
            playerFactory: speakers.playerFactory,
            ducker: sessionController,
            transcriptFactory: transcriptFactory
        )
        return TranslationPipeline(dependencies: dependencies)
    }
}
