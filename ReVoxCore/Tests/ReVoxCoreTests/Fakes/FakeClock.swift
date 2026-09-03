import Foundation
@testable import ReVoxCore

/// The Windows `fixed_clock`: a fixed start advanced by one second per read.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000), step: TimeInterval = 1) {
        current = start
        self.step = step
    }

    /// The closure to inject as `PipelineDependencies.clock`.
    var now: @Sendable () -> Date {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            let value = current
            current = current.addingTimeInterval(step)
            return value
        }
    }
}
