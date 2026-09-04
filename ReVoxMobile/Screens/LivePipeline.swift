import Foundation
import ReVoxCore

/// The slice of `TranslationPipeline` the Live screen drives; tests substitute `FakeLivePipeline`.
protocol LivePipeline: Sendable {
    var events: AsyncStream<PipelineEvent> { get }
    func start(_ configuration: PipelineConfiguration) async
    func stop() async
    func setMuted(_ muted: Bool) async
    /// A capture gap (ring overrun or a keep-alive heartbeat gap): drop marker + `.lag`, no segment dropped (§5.4).
    func noteCaptureGap() async
}

extension TranslationPipeline: LivePipeline {}

/// Builds a loaded pipeline for the given settings, reporting load phases ("Preparing model…").
typealias PipelineSupplier = @Sendable (_ settings: Settings, _ progress: @escaping @Sendable (String) -> Void) async throws -> any LivePipeline

/// What makes a loaded pipeline reusable across restarts (Windows `_invalidate`: latency mode; plus the model).
struct PipelineSignature: Equatable, Sendable {
    var model: String
    var latencyMode: String

    init(settings: Settings) {
        model = settings.model
        latencyMode = settings.latencyMode
    }
}
