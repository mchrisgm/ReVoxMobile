import Foundation

/// `CFNotificationCenterAddObserver` over the Darwin centre for a fixed set of names (§6.2). The centre delivers
/// on the main run loop; each delivery is forwarded as the name into `names`, from which the capture task hops off
/// the main thread. The stream keeps only the newest name: the producer is the main run loop and the consumers
/// decode property lists, so an unbounded buffer lets any app on the device grow ReVox's memory by posting in a
/// loop — and N pending wakes and one pending wake produce the same state read, because a notification is a hint
/// and every wake re-reads the header (docs/security-review-m5.md finding 6).
/// `@unchecked Sendable`: the observer registration is guarded by a lock and the continuation is thread-safe.
final class DarwinNotificationObserver: @unchecked Sendable {
    /// What the C callback is handed, instead of the observer itself.
    ///
    /// CFNotificationCenter collects matching observers under its own lock and then invokes them *outside* it, so
    /// `CFNotificationCenterRemoveEveryObserver` returning does not un-invoke a callback already in flight. The
    /// observer is deregistered from whatever thread calls `stop` — for `BroadcastCapture` that is a cooperative
    /// pool thread — while delivery happens on the main run loop, so a raw `Unmanaged.passUnretained(self)` could
    /// be read by a callback after the object it points at was freed (docs/security-review-m5.md, second pass).
    ///
    /// This box is therefore registered `passRetained` and never released: the pointer CF holds stays valid for
    /// the life of the process, so an in-flight callback is always safe, and `invalidate()` makes a late one a
    /// no-op. It costs one small allocation per observer, which is bounded by the number of capture runs.
    private final class Context: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<String>.Continuation?

        init(continuation: AsyncStream<String>.Continuation) {
            self.continuation = continuation
        }

        func yield(_ name: String) {
            lock.lock()
            let continuation = self.continuation
            lock.unlock()
            continuation?.yield(name)
        }

        func invalidate() {
            lock.lock()
            continuation = nil
            lock.unlock()
        }
    }

    let names: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let context: Context
    private let contextPointer: UnsafeMutableRawPointer
    private let observed: [String]
    private let lock = NSLock()
    private var isObserving = false

    init(names: [String]) {
        observed = names
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.names = stream
        self.continuation = continuation
        let context = Context(continuation: continuation)
        self.context = context
        self.contextPointer = Unmanaged.passRetained(context).toOpaque()
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
        for name in observed {
            CFNotificationCenterAddObserver(center, contextPointer, DarwinNotificationObserver.callback, name as CFString, nil, .deliverImmediately)
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isObserving else { return }
        isObserving = false
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), contextPointer)
        context.invalidate()
    }

    /// The C callback: recovers the context from the opaque pointer and yields the name (no payload exists).
    private static let callback: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer, let name else { return }
        Unmanaged<Context>.fromOpaque(observer).takeUnretainedValue().yield(name.rawValue as String)
    }
}
