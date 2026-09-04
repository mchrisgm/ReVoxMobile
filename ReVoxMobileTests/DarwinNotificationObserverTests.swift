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
