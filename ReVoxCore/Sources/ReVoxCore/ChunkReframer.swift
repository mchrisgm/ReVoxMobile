import Foundation

/// A full 512-sample chunk stamped with the capture position of its last sample.
public struct AudioChunk: Sendable, Equatable {
    public var samples: [Float]
    public var endPosition: Int64

    public init(samples: [Float], endPosition: Int64) {
        self.samples = samples
        self.endPosition = endPosition
    }
}

/// Re-frames captured runs of any length into fixed chunks, carrying capture positions across item boundaries.
public struct ChunkReframer: Sendable {
    public let chunkSamples: Int
    private var pending: [Float] = []
    /// Capture position of `pending[0]`.
    private var pendingStart: Int64 = 0
    public private(set) var expectedNextPosition: Int64?

    public init(chunkSamples: Int = Segmenter.chunkSamples) {
        self.chunkSamples = chunkSamples
    }

    /// Full chunks only, each stamped with the capture position of its last sample. A discontinuity
    /// (`endingAt − samples.count != expectedNextPosition`) discards the pending remainder and re-seats the position.
    public mutating func push(_ samples: [Float], endingAt endPosition: Int64) -> [AudioChunk] {
        let start = endPosition - Int64(samples.count)
        if let expected = expectedNextPosition, expected != start {
            pending.removeAll()
            pendingStart = start
        } else if pending.isEmpty {
            pendingStart = start
        }
        pending.append(contentsOf: samples)
        expectedNextPosition = endPosition

        var chunks: [AudioChunk] = []
        var offset = 0
        while pending.count - offset >= chunkSamples {
            let slice = Array(pending[offset ..< offset + chunkSamples])
            pendingStart += Int64(chunkSamples)
            chunks.append(AudioChunk(samples: slice, endPosition: pendingStart))
            offset += chunkSamples
        }
        pending.removeFirst(offset)
        return chunks
    }

    public var pendingCount: Int { pending.count }

    /// The remainder (< chunkSamples); clears it.
    public mutating func drain() -> [Float] {
        defer { pending.removeAll() }
        return pending
    }
}
