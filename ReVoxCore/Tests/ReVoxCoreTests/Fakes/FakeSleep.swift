import Foundation
@testable import ReVoxCore

/// Records the requested nanoseconds and suspends until `resumeAll()`; a cancelled sleeper throws `CancellationError`
/// and leaves the pending list. Injected as `PipelineDependencies.sleep` / `DuckingCoordinator.sleep`.
/// Every stored property is guarded by one `NSLock`, taken only inside the synchronous helpers.
final class FakeSleep: @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var requestedNanoseconds: [UInt64] = []
    private var sleepers: [Sleeper] = []

    var requested: [UInt64] {
        synced { requestedNanoseconds }
    }

    var pendingCount: Int {
        synced { sleepers.count }
    }

    /// The closure to inject.
    var sleep: @Sendable (UInt64) async throws -> Void {
        { [self] nanoseconds in
            record(nanoseconds)
            let id = UUID()
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    register(Sleeper(id: id, continuation: continuation))
                }
            } onCancel: {
                cancel(id: id)
            }
        }
    }

    func resumeAll() {
        let pending = synced { () -> [Sleeper] in
            let all = sleepers
            sleepers.removeAll()
            return all
        }
        for sleeper in pending {
            sleeper.continuation.resume()
        }
    }

    private func record(_ nanoseconds: UInt64) {
        synced { requestedNanoseconds.append(nanoseconds) }
    }

    private func register(_ sleeper: Sleeper) {
        let alreadyCancelled = synced { () -> Bool in
            if Task.isCancelled { return true }
            sleepers.append(sleeper)
            return false
        }
        if alreadyCancelled {
            sleeper.continuation.resume(throwing: CancellationError())
        }
    }

    private func cancel(id: UUID) {
        let sleeper = synced { () -> Sleeper? in
            guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
            return sleepers.remove(at: index)
        }
        sleeper?.continuation.resume(throwing: CancellationError())
    }

    private func synced<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
