import Foundation
import SwiftData
import ReVoxCore

/// The composition root (§4.2, A6): adapters + core pipeline for one settings snapshot, microphone mode in M3.
@MainActor
final class PipelineAssembler {
    private let layout: ModelLayout
    private let sessionController: AudioSessionController
    private let transcriptContainer: ModelContainer

    init(layout: ModelLayout, sessionController: AudioSessionController, transcriptContainer: ModelContainer) {
        self.layout = layout
        self.sessionController = sessionController
        self.transcriptContainer = transcriptContainer
    }

    func supplier() -> PipelineSupplier {
        let layout = self.layout
        let controller = self.sessionController
        let container = self.transcriptContainer
        return { settings, progress in
            try await PipelineAssembler.build(settings: settings, layout: layout, sessionController: controller, transcriptContainer: container, progress: progress)
        }
    }

    nonisolated static func sessionMetadata(for settings: Settings, startedAt: Date) -> SessionMetadata {
        SessionMetadata(
            startedAt: startedAt,
            captureMode: settings.capture,
            pinnedLanguage: settings.language,
            modelID: settings.whisperModel.rawValue,
            voice: "system",   // M4: the effective speaker's voice name
            joinedInProgress: false
        )
    }

    nonisolated static func build(settings: Settings, layout: ModelLayout, sessionController: AudioSessionController,
                                  transcriptContainer: ModelContainer, progress: @escaping @Sendable (String) -> Void) async throws -> TranslationPipeline {
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

        // 3. Adapters.
        let speaker = SystemSpeaker(voiceIdentifier: settings.systemVoiceIdentifier)
        // The capture source's status line ("No microphone input", §6.1) rides the controller's SessionEvent
        // stream, which `LiveViewModel.observe(sessionEvents:)` already renders (Tasks 28, 30, 35).
        let source = MicrophoneCapture(controller: sessionController, onStatus: { status in
            Task { await sessionController.publishCaptureStatus(status) }
        })
        let voiceVolume = Float(settings.voiceVolume)
        let playerFactory: AudioPlayerFactory = { _, onSpeaking in
            let player = AudioPlayer(controller: sessionController, onSpeaking: onSpeaking)
            player.setVoiceVolume(voiceVolume)
            return player
        }
        let transcriptFactory: TranscriptSinkFactory = {
            TranscriptStore(modelContainer: transcriptContainer, metadata: PipelineAssembler.sessionMetadata(for: settings, startedAt: Date()))
        }

        // 4. The core pipeline (ducking through the controller; `duckingEnabled` is false in the M3 configuration).
        let dependencies = PipelineDependencies(
            source: source,
            vad: vad,
            detector: translator,
            translator: translator,
            speaker: speaker,
            playerFactory: playerFactory,
            ducker: sessionController,
            transcriptFactory: transcriptFactory
        )
        return TranslationPipeline(dependencies: dependencies)
    }
}
