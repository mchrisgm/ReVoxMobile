import Foundation
import ReVoxCore

/// A source that captures nothing; records the mode it was started with.
final class StubAudioSource: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    private(set) var startedModes: [CaptureMode] = []
    private(set) var stopCount = 0

    func frames() -> AsyncStream<CapturedAudio> {
        lock.lock(); defer { lock.unlock() }
        continuation?.finish()
        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        return stream
    }

    func capturePosition() async -> Int64 { 0 }

    func start(_ mode: CaptureMode) async throws {
        lock.lock(); startedModes.append(mode); lock.unlock()
    }

    func stop() async {
        lock.lock(); stopCount += 1; continuation?.finish(); continuation = nil; lock.unlock()
    }
}
