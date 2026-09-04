import Foundation
import ReVoxCore

/// The production `RingStorage` (§5.9): the mapped file plus the C11 acquire/release accessors of `RingAtomics.c`.
/// `@unchecked Sendable`: the mapping is immutable for its lifetime and the cursor accessors are atomic; the data
/// region is coordinated only through those cursors (data → cursor on the writer, cursor → data → cursor re-check
/// on the reader).
final class MappedRingStorage: RingStorage, @unchecked Sendable {
    let mapping: RingFileMapping

    init(mapping: RingFileMapping) {
        self.mapping = mapping
    }

    var base: UnsafeMutableRawPointer { mapping.base }
    var count: Int { mapping.count }

    func loadCursor(at offset: Int) -> UInt64 {
        revox_ring_load_cursor(mapping.base + offset)
    }

    func storeCursor(_ value: UInt64, at offset: Int) {
        revox_ring_store_cursor(mapping.base + offset, value)
    }
}
