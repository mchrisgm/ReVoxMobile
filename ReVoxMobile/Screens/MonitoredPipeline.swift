import Foundation
import ReVoxCore

/// Runs the keep-alive monitor alongside a pipeline run: `start` starts the ticks after the pipeline is running,
/// a gap becomes `noteCaptureGap()` (drop marker + `.lag`, §9), `stop` stops the ticks before the pipeline.
final class MonitoredPipeline: LivePipeline, Sendable {
    private let pipeline: any LivePipeline
    private let monitor: KeepAliveMonitor
    private let position: @Sendable () async -> Int64

    init(pipeline: any LivePipeline, monitor: KeepAliveMonitor, position: @escaping @Sendable () async -> Int64) {
        self.pipeline = pipeline
        self.monitor = monitor
        self.position = position
    }

    var events: AsyncStream<PipelineEvent> { pipeline.events }

    func start(_ configuration: PipelineConfiguration) async {
        await pipeline.start(configuration)
        monitor.reset()
        let pipeline = self.pipeline
        monitor.start(position: position, onGap: { _ in await pipeline.noteCaptureGap() })
    }

    func stop() async {
        monitor.stop()
        await pipeline.stop()
    }

    func setMuted(_ muted: Bool) async {
        await pipeline.setMuted(muted)
    }

    func noteCaptureGap() async {
        await pipeline.noteCaptureGap()
    }
}
