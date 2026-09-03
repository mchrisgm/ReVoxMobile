import Foundation
@testable import ReVoxCore

/// A `HeapRingStorage` wrapper whose `loadCursor` rewinds the write cursor to `rewindTo` on the reader's second load
/// after `arm()` — a writer that restarted (`RingWriter.begin` zeroes the cursor for a new generation) while the
/// reader's copy was in progress.
final class RewindingCursorStorage: RingStorage, @unchecked Sendable {
    private let inner: HeapRingStorage
    private let rewindTo: UInt64
    private let lock = NSLock()
    private var loadsSinceArm: Int?

    init(inner: HeapRingStorage, rewindTo: UInt64) {
        self.inner = inner
        self.rewindTo = rewindTo
    }

    var base: UnsafeMutableRawPointer { inner.base }
    var count: Int { inner.count }

    func arm() {
        lock.lock()
        loadsSinceArm = 0
        lock.unlock()
    }

    func loadCursor(at offset: Int) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard offset == RingHeader.Offset.writeCursor, let loads = loadsSinceArm else {
            return inner.loadCursor(at: offset)
        }
        loadsSinceArm = loads + 1
        if loads + 1 == 2 {
            inner.storeCursor(rewindTo, at: offset)
            loadsSinceArm = nil
            return rewindTo
        }
        return inner.loadCursor(at: offset)
    }

    func storeCursor(_ value: UInt64, at offset: Int) {
        inner.storeCursor(value, at: offset)
    }
}
