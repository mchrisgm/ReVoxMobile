import Foundation
import ReVoxCore

/// Runs the keep-alive monitor alongside a pipeline run: `start` starts the ticks after the pipeline is running,
/// a gap becomes `noteCaptureGap()` (drop marker + `.lag`, §9), `stop` stops the ticks before the pipeline.
final class MonitoredPipeline: LivePipeline, Sendable {
    private let pipeline: any LivePipeline
    private let monitor: KeepAliveMonitor
    private let position: @Sendable () async -> Int64
    private let onStart: @Sendable () -> Void
    private let onStop: @Sendable () -> Void

    init(pipeline: any LivePipeline, monitor: KeepAliveMonitor, position: @escaping @Sendable () async -> Int64,
         onStart: @escaping @Sendable () -> Void = {}, onStop: @escaping @Sendable () -> Void = {}) {
        self.pipeline = pipeline
        self.monitor = monitor
        self.position = position
        self.onStart = onStart
        self.onStop = onStop
    }

    var events: AsyncStream<PipelineEvent> { pipeline.events }

    func start(_ configuration: PipelineConfiguration) async {
        onStart()                    // re-install anything this run needs on app-lifetime objects (the ring gap handler)
        await pipeline.start(configuration)
        monitor.reset()
        let pipeline = self.pipeline
        monitor.start(position: position, onGap: { _ in await pipeline.noteCaptureGap() })
    }

    func stop() async {
        monitor.stop()
        await pipeline.stop()
        onStop()                     // release anything the run installed on app-lifetime objects (the ring gap handler)
    }

    func setMuted(_ muted: Bool) async {
        await pipeline.setMuted(muted)
    }

    func noteCaptureGap() async {
        await pipeline.noteCaptureGap()
    }
}
