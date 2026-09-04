import Foundation

public enum AttachState: Sendable, Equatable {
    case noRing
    case idle
    case attachedLive(generation: UInt64)
    case stale(lastWriteAt: Double)
}

public enum ReadResult: Sendable, Equatable {
    case frames(Int)
    case gap(dropped: Int)
    case idle
}

/// The app's side of the ring. Not Sendable: owned by one task (the BroadcastCapture capture task); the storage is
/// the shared object.
public final class RingReader {
    public static let defaultGuardFrames = 16_000          // 1 s
    public static let defaultCatchUpFrames = 32_000        // 2 s
    public static let staleAfterSeconds: Double = 3
    /// A cursor above this cannot be a real frame count (557 years at 16 kHz), so the header is corrupt or lying.
    /// The header carries no checksum: one flipped bit in bit 63 of the 8 bytes at offset 32 passes both the magic
    /// and the geometry check, and `Int(_: UInt64)` on the result traps. The file persists, so that trap would be a
    /// crash on every launch until the app is deleted — docs/security-review-m5.md finding 1.
    public static let maxPlausibleCursor: UInt64 = 1 << 48

    private let storage: any RingStorage
    private let layout: RingLayout
    public private(set) var readCursor: UInt64 = 0
    public private(set) var overrunCount: UInt64 = 0
    private var catchUp = RingReader.defaultCatchUpFrames

    /// `.tooSmall` when the storage cannot hold the layout, `.badMagic` on a foreign or unwritten header,
    /// `.unsupportedLayout` when the header's geometry differs from `layout`.
    public init(storage: any RingStorage, layout: RingLayout = .v1) throws {
        guard storage.count >= layout.totalBytes else { throw RingError.tooSmall }
        guard let header = RingHeader.read(from: storage), header.magic == layout.magic else { throw RingError.badMagic }
        guard header.headerBytes == UInt32(layout.headerBytes),
              header.capacityFrames == UInt32(layout.capacityFrames),
              header.sampleRate == UInt32(layout.sampleRate),
              header.channels == 1, header.sampleFormat == 1 else { throw RingError.unsupportedLayout }
        self.storage = storage
        self.layout = layout
        readCursor = header.readCursor
        overrunCount = header.overrunCount
    }

    /// nil once the shared page stops being a ring header (a corrupted magic after `init` succeeded). Optional
    /// rather than force-unwrapped: the writer is another process and the page can change under us at any time.
    public var header: RingHeader? {
        RingHeader.read(from: storage)
    }

    /// Decides live/stale/idle from state, generation and heartbeat; positions readCursor = max(stored, writeCursor − catchUp).
    /// A stored record from another generation is ignored (the header is trusted). A negative `catchUp` reads as
    /// zero (attach at the writer): `UInt64(_:)` traps below zero, and nothing else it could mean.
    public func attach(now: Double, storedReadCursor: UInt64?, storedGeneration: UInt64?,
                       catchUp: Int = RingReader.defaultCatchUpFrames) -> AttachState {
        let catchUp = max(0, catchUp)
        self.catchUp = catchUp
        guard let header else { return .noRing }
        switch header.state {
        case .running:
            guard header.isHeartbeatFresh(now: now) else {
                return .stale(lastWriteAt: header.lastWriteAt)
            }
            let generationMatches = storedGeneration == nil || storedGeneration == header.generation
            let stored = generationMatches ? (storedReadCursor ?? 0) : 0
            let writeCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)
            guard writeCursor <= RingReader.maxPlausibleCursor else { return .noRing }
            let behind = writeCursor > UInt64(catchUp) ? writeCursor - UInt64(catchUp) : 0
            readCursor = max(min(stored, writeCursor), behind)
            storage.storeCursor(readCursor, at: RingHeader.Offset.readCursor)
            return .attachedLive(generation: header.generation)
        case .idle, .paused, .finished, .failed:
            return .idle
        }
    }

    /// Copies [readCursor, writeCursor) in 512-multiples (at most `buffer.count`); re-checks writeCursor after the copy;
    /// on overrun discards, bumps overrunCount, jumps to writeCursor − catchUp.
    public func read(into buffer: UnsafeMutableBufferPointer<Float>, guard guardFrames: Int = RingReader.defaultGuardFrames) -> ReadResult {
        let capacity = UInt64(layout.capacityFrames)
        let safeDistance = capacity - UInt64(max(0, min(guardFrames, layout.capacityFrames)))
        let start = readCursor
        let writeCursor = storage.loadCursor(at: RingHeader.Offset.writeCursor)      // acquire
        guard writeCursor <= RingReader.maxPlausibleCursor else { return .idle }     // a lying header, not a gap
        guard writeCursor > start else { return .idle }
        if writeCursor - start > safeDistance {
            return overrun(from: start, writeCursor: writeCursor)
        }
        let available = Int(min(writeCursor - start, UInt64(buffer.count)))
        let count = available - available % Segmenter.chunkSamples
        guard count > 0, let destination = buffer.baseAddress else { return .idle }
        let data = storage.base + layout.headerBytes
        let physical = Int(start % capacity)
        let firstPart = min(count, layout.capacityFrames - physical)
        UnsafeMutableRawPointer(destination)
            .copyMemory(from: data.advanced(by: physical * MemoryLayout<Float>.size), byteCount: firstPart * MemoryLayout<Float>.size)
        if firstPart < count {
            UnsafeMutableRawPointer(destination + firstPart)
                .copyMemory(from: data, byteCount: (count - firstPart) * MemoryLayout<Float>.size)
        }
        // The samples come from a page another process writes; nothing has validated them. One NaN reaching the VAD
        // poisons its LSTM state for the rest of the run — every later probability is NaN, `probability >= threshold`
        // is false for NaN, so no phrase is ever detected again and nothing reports an error. Zeroing here covers the
        // pipeline, the level meters and the self-capture probe at once (docs/security-review-m5.md finding 2).
        for index in 0 ..< count where !destination[index].isFinite {
            destination[index] = 0
        }
        let recheck = storage.loadCursor(at: RingHeader.Offset.writeCursor)          // did the writer lap us meanwhile?
        // A writer restart between the two loads rewinds the cursor (`RingWriter.begin` zeroes it for a new
        // generation): nothing is consumable, so discard the copy — the same rule as the entry guard above.
        guard recheck > start, recheck <= RingReader.maxPlausibleCursor else { return .idle }
        if recheck - start > safeDistance {
            return overrun(from: start, writeCursor: recheck)
        }
        readCursor = start + UInt64(count)
        storage.storeCursor(readCursor, at: RingHeader.Offset.readCursor)
        return .frames(count)
    }

    private func overrun(from start: UInt64, writeCursor: UInt64) -> ReadResult {
        overrunCount += 1
        storage.base.storeUInt64(overrunCount, RingHeader.Offset.overrunCount)
        let target = writeCursor > UInt64(catchUp) ? writeCursor - UInt64(catchUp) : 0
        readCursor = max(target, start)
        storage.storeCursor(readCursor, at: RingHeader.Offset.readCursor)
        return .gap(dropped: Int(clamping: readCursor - start))
    }
}
