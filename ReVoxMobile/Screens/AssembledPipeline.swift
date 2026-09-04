import Foundation
import ReVoxCore

/// The `LivePipeline` the Live screen drives: every `start` first prepares the effective speaker with the
/// session's selection (R11, §6.5), then starts the core pipeline. Generic over `LivePipeline` so tests wrap a fake.
final class AssembledPipeline: LivePipeline, Sendable {
    private let pipeline: any LivePipeline
    private let speaker: EffectiveSpeaker
    private let selection: @Sendable () async -> SpeakerSelection

    init(pipeline: any LivePipeline, speaker: EffectiveSpeaker, selection: @escaping @Sendable () async -> SpeakerSelection) {
        self.pipeline = pipeline
        self.speaker = speaker
        self.selection = selection
    }

    var events: AsyncStream<PipelineEvent> { pipeline.events }

    func start(_ configuration: PipelineConfiguration) async {
        let chosen = await selection()
        await speaker.prepare(chosen)
        await pipeline.start(configuration)
    }

    func stop() async {
        await pipeline.stop()
    }

    func setMuted(_ muted: Bool) async {
        await pipeline.setMuted(muted)
    }
}
