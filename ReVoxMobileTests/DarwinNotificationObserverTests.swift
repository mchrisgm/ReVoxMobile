import XCTest
@testable import ReVoxMobile

/// Darwin notifications are system-wide; posting and observing inside one process is the same mechanism the
/// extension → app path uses (§6.2). Delivery happens on the main run loop, which the host app keeps running.
final class DarwinNotificationObserverTests: XCTestCase {
    func testObservedNameIsDeliveredAndUnobservedNameIsNot() async {
        let observed = "group.test.revox-\(UUID().uuidString).broadcast.audio"
        let other = "group.test.revox-\(UUID().uuidString).broadcast.stopped"
        let observer = DarwinNotificationObserver(names: [observed])
        observer.start()
        defer { observer.stop() }

        DarwinNotificationPoster(name: other).post()
        DarwinNotificationPoster(name: observed).post()

        var iterator = observer.names.makeAsyncIterator()
        let first = await withTimeout(seconds: 3) { await iterator.next() }
        XCTAssertEqual(first, observed)

        DarwinNotificationPoster(name: observed).post()
        let second = await withTimeout(seconds: 3) { await iterator.next() }
        XCTAssertEqual(second, observed, "each post is one element; the unobserved name never appears")
    }

    /// docs/security-review-m5.md (second pass): the pointer CF holds must stay valid even if the observer is
    /// deallocated from another thread while a delivery is in flight on the main run loop. The registered box is
    /// retained for the life of the process and invalidated by `stop`, so a post to a name whose observer is gone
    /// reaches a live object that does nothing — rather than a freed one.
    func testAPostAfterTheObserverIsGoneIsHarmless() async {
        let name = "group.test.revox-\(UUID().uuidString).broadcast.audio"
        do {
            let observer = DarwinNotificationObserver(names: [name])
            observer.start()
            observer.stop()
        }                                          // the observer is deallocated here
        DarwinNotificationPoster(name: name).post()
        // The assertion is that this does not crash; a run loop turn gives any in-flight delivery time to land.
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    func testStopIsIdempotentAndStopsDelivery() async {
        let name = "group.test.revox-\(UUID().uuidString).broadcast.started"
        let observer = DarwinNotificationObserver(names: [name])
        observer.start()
        observer.stop()
        observer.stop()
        DarwinNotificationPoster(name: name).post()
        var iterator = observer.names.makeAsyncIterator()
        let delivered = await withTimeout(seconds: 1) { await iterator.next() }
        XCTAssertNil(delivered)
    }
}

/// Returns nil when `body` does not finish within `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
