import Foundation
import XCTest
@testable import ReVoxCore

/// A value guarded by one `NSLock`; the justification for the `@unchecked Sendable` fakes.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }

    func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&stored)
    }
}

/// Polls `predicate` until it is true or `timeout` elapses (the Windows `wait_until`).
func eventually(timeout: TimeInterval = 2, _ predicate: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await predicate()
}
