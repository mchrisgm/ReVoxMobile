import Foundation
@testable import ReVoxCore

/// A `HeapRingStorage` wrapper whose `loadCursor` advances the write cursor by `advance` frames on the reader's
/// second load after `arm()` — a writer that laps the reader while its copy is in progress.
final class OvertakingCursorStorage: RingStorage, @unchecked Sendable {
    private let inner: HeapRingStorage
    private let advance: UInt64
    private let lock = NSLock()
    private var loadsSinceArm: Int?

    init(inner: HeapRingStorage, advance: Int) {
        self.inner = inner
        self.advance = UInt64(advance)
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
            let advanced = inner.loadCursor(at: offset) + advance
            inner.storeCursor(advanced, at: offset)
            loadsSinceArm = nil
            return advanced
        }
        return inner.loadCursor(at: offset)
    }

    func storeCursor(_ value: UInt64, at offset: Int) {
        inner.storeCursor(value, at: offset)
    }
}
