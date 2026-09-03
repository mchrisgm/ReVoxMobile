import Foundation

/// Records the order in which the pipeline starts its dependencies.
///
/// The audio graph on iOS is order-sensitive: the capture tap must be installed on the engine's input node
/// before that engine is started, or the input is never pulled and the microphone stays silent (observed on
/// device, build 8). The source's `start` installs the tap and the player's `start` starts the engine, so the
/// pipeline must start the source first — this log lets a test hold that ordering.
final class StartOrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock(); entries.append(entry); lock.unlock()
    }

    var recorded: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}
