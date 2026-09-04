import Foundation
import ReVoxCore
@testable import ReVoxMobile

/// The Windows `FakePipeline` of `test_app.py`: records start/stop/mute/gap and emits the state events itself.
final class FakeLivePipeline: LivePipeline, @unchecked Sendable {
    private let lock = NSLock()
    let events: AsyncStream<PipelineEvent>
    private let continuation: AsyncStream<PipelineEvent>.Continuation
    private(set) var startedWith: [PipelineConfiguration] = []
    private(set) var stopCount = 0
    private(set) var muted: [Bool] = []
    private var gaps = 0
    var gapCount: Int { lock.lock(); defer { lock.unlock() }; return gaps }

    init() {
        let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
    }

    func start(_ configuration: PipelineConfiguration) async {
        lock.lock(); startedWith.append(configuration); lock.unlock()
        continuation.yield(.state(.running))
    }

    func stop() async {
        lock.lock(); stopCount += 1; lock.unlock()
        continuation.yield(.state(.idle))
    }

    func setMuted(_ muted: Bool) async {
        lock.lock(); self.muted.append(muted); lock.unlock()
    }

    func noteCaptureGap() async {
        lock.lock(); gaps += 1; lock.unlock()
        continuation.yield(.lag)
    }

    func emit(_ event: PipelineEvent) {
        continuation.yield(event)
    }
}
