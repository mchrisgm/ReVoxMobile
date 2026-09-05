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
    /// Set by the ordering test; see `StartOrderLog`.
    nonisolated(unsafe) var startOrder: StartOrderLog?
    /// When set, `start(_:)` records the attempt and then throws it (a denied microphone, a failed engine).
    nonisolated(unsafe) var startError: (any Error)?
    private var stopCount = 0
    private let bufferLimit: Int?
    private var droppedFeedCount = 0
    private var terminatedStreamCount = 0

    /// `bufferLimit` makes every stream `bufferingOldest(limit)`, so a feed that nobody is reading is reported in
    /// `droppedFeeds` instead of piling up silently as it would in the unbounded default.
    init(bufferLimit: Int? = nil) {
        self.bufferLimit = bufferLimit
    }

    var framesCalls: Int { synced { framesCallCount } }
    /// Feeds the stream refused because its bounded buffer was full (`bufferLimit` only).
    var droppedFeeds: Int { synced { droppedFeedCount } }
    /// Streams from `frames()` that were terminated — finished by `stop()`, or cancelled because their last iterator
    /// was dropped (an `AsyncStream` whose consumer went away cancels itself and refuses further yields).
    var terminatedStreams: Int { synced { terminatedStreamCount } }
    var started: [CaptureMode] { synced { startedModes } }
    var stopped: Bool { synced { stopCount > 0 } }

    /// `finish()` runs `onTermination` synchronously on the calling thread, and that hook takes the lock, so the
    /// previous continuation is finished *outside* `synced` here and in `stop()` — `NSLock` is not recursive.
    func frames() -> AsyncStream<CapturedAudio> {
        let (stream, previous) = synced { () -> (AsyncStream<CapturedAudio>, AsyncStream<CapturedAudio>.Continuation?) in
            let previous = continuation
            let policy: AsyncStream<CapturedAudio>.Continuation.BufferingPolicy =
                bufferLimit.map { .bufferingOldest($0) } ?? .unbounded
            let (stream, newContinuation) = AsyncStream.makeStream(of: CapturedAudio.self, bufferingPolicy: policy)
            newContinuation.onTermination = { [weak self] _ in
                self?.synced { self?.terminatedStreamCount += 1 }
            }
            continuation = newContinuation
            framesCallCount += 1
            return (stream, previous)
        }
        previous?.finish()
        return stream
    }

    func capturePosition() async -> Int64 {
        synced { position }
    }

    func start(_ mode: CaptureMode) async throws {
        startOrder?.record("source")
        synced { startedModes.append(mode) }
        if let startError {
            throw startError
        }
    }

    func stop() async {
        let current = synced { () -> AsyncStream<CapturedAudio>.Continuation? in
            stopCount += 1
            let current = continuation
            continuation = nil
            return current
        }
        current?.finish()
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
            if case .dropped = continuation?.yield(CapturedAudio(samples: samples, endPosition: end)) {
                droppedFeedCount += 1
            }
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
