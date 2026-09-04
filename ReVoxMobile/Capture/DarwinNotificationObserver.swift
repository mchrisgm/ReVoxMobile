import Foundation

/// `CFNotificationCenterAddObserver` over the Darwin centre for a fixed set of names (§6.2). The centre delivers
/// on the main run loop; each delivery is forwarded as the name into `names` (unbounded), from which the
/// capture task hops off the main thread. The stream keeps only the newest name: the producer is the main run
/// loop and the consumers decode property lists, so an unbounded buffer lets any app on the device grow ReVox's
/// memory by posting in a loop — and N pending wakes and one pending wake produce the same state read, because a
/// notification is a hint and every wake re-reads the header (docs/security-review-m5.md finding 6).
/// `@unchecked Sendable`: the observer registration is guarded by a lock and the continuation is thread-safe.
final class DarwinNotificationObserver: @unchecked Sendable {
    let names: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let observed: [String]
    private let lock = NSLock()
    private var isObserving = false

    init(names: [String]) {
        observed = names
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.names = stream
        self.continuation = continuation
    }

    deinit {
        stop()
        continuation.finish()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isObserving else { return }
        isObserving = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in observed {
            CFNotificationCenterAddObserver(center, observer, DarwinNotificationObserver.callback, name as CFString, nil, .deliverImmediately)
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isObserving else { return }
        isObserving = false
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }

    /// The C callback: recovers the observer from the opaque pointer and yields the name (no payload exists).
    private static let callback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer, let name else { return }
        let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
        instance.continuation.yield(name.rawValue as String)
    }
}
