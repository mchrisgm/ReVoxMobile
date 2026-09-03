import Foundation
@testable import ReVoxCore

/// The Windows `FakeCaptureBackend`: `frames()` returns a fresh stream per call and counts the calls; `feed(_:)`
/// yields `CapturedAudio` with positions into the latest stream; `stop()` finishes the current stream.
/// `frames()` is a synchronous protocol requirement, so this is a class whose every stored property is guarded by
/// one `NSLock` (taken only inside the synchronous `synced` helper), not an actor.
final class FakeAudioSource: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    private var nextPosition: Int64 = 0
    private var position: Int64 = 0
    private var framesCallCount = 0
    private var startedModes: [CaptureMode] = []
    private var stopCount = 0

    var framesCalls: Int { synced { framesCallCount } }
    var started: [CaptureMode] { synced { startedModes } }
    var stopped: Bool { synced { stopCount > 0 } }

    func frames() -> AsyncStream<CapturedAudio> {
        synced {
            continuation?.finish()
            let (stream, newContinuation) = AsyncStream.makeStream(of: CapturedAudio.self)
            continuation = newContinuation
            framesCallCount += 1
            return stream
        }
    }

    func capturePosition() async -> Int64 {
        synced { position }
    }

    func start(_ mode: CaptureMode) async throws {
        synced { startedModes.append(mode) }
    }

    func stop() async {
        synced {
            stopCount += 1
            continuation?.finish()
            continuation = nil
        }
    }

    /// Mic semantics: positions continue from the last fed sample and `capturePosition` follows.
    func feed(_ samples: [Float]) {
        let end = synced { nextPosition + Int64(samples.count) }
        feed(samples, endingAt: end)
    }

    /// Broadcast semantics: an explicit ring position for the last sample; `capturePosition` never goes backwards.
    func feed(_ samples: [Float], endingAt end: Int64) {
        synced {
            nextPosition = end
            position = max(position, end)
            continuation?.yield(CapturedAudio(samples: samples, endPosition: end))
        }
    }

    /// Moves the stamped capture position ahead of the delivered chunks (the ring writeCursor in broadcast mode).
    func setCapturePosition(_ newPosition: Int64) {
        synced { position = newPosition }
    }

    private func synced<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
