import XCTest
@testable import ReVoxCore

final class ChunkReframerTests: XCTestCase {
    func testExactChunkCountForAnyCadence() {
        let total = 9_600                                   // 18 × 512 + 384
        for slice in [100, 480, 512, 1600, 9_600] {
            var reframer = ChunkReframer()
            var chunks: [AudioChunk] = []
            var position: Int64 = 0
            var start = 0
            while start < total {
                let count = min(slice, total - start)
                position += Int64(count)
                chunks += reframer.push([Float](repeating: Float(start), count: count), endingAt: position)
                start += count
            }
            XCTAssertEqual(chunks.count, 18, "slice \(slice)")
            XCTAssertEqual(reframer.pendingCount, 384, "slice \(slice)")
            XCTAssertEqual(reframer.expectedNextPosition, 9_600)
            XCTAssertEqual(chunks.map(\.endPosition), (1 ... 18).map { Int64($0 * 512) })
            XCTAssertTrue(chunks.allSatisfy { $0.samples.count == 512 })
            XCTAssertEqual(reframer.drain().count, 384)
            XCTAssertEqual(reframer.pendingCount, 0)
        }
    }

    func testPositionsAdvanceFromTheFirstItemsStart() {
        var reframer = ChunkReframer()
        let first = reframer.push([Float](repeating: 1, count: 700), endingAt: 1_700)   // starts at 1 000
        XCTAssertEqual(first.map(\.endPosition), [1_512])
        let second = reframer.push([Float](repeating: 2, count: 400), endingAt: 2_100)
        XCTAssertEqual(second.map(\.endPosition), [2_024])
        XCTAssertEqual(second[0].samples.prefix(188).allSatisfy { $0 == 1 }, true)   // 700 − 512 = 188 from the first item
        XCTAssertEqual(reframer.pendingCount, 76)
        XCTAssertEqual(reframer.expectedNextPosition, 2_100)
    }

    func testDiscontinuityDropsRemainderAndReseats() {
        var reframer = ChunkReframer()
        XCTAssertTrue(reframer.push([Float](repeating: 1, count: 300), endingAt: 300).isEmpty)
        XCTAssertEqual(reframer.pendingCount, 300)
        let chunks = reframer.push([Float](repeating: 2, count: 512), endingAt: 5_000)   // expected 300, got 4 488
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].endPosition, 5_000)
        XCTAssertTrue(chunks[0].samples.allSatisfy { $0 == 2 })
        XCTAssertEqual(reframer.pendingCount, 0)
    }

    func testCustomChunkSize() {
        var reframer = ChunkReframer(chunkSamples: 4)
        let chunks = reframer.push([1, 2, 3, 4, 5, 6, 7, 8, 9], endingAt: 9)
        XCTAssertEqual(chunks, [AudioChunk(samples: [1, 2, 3, 4], endPosition: 4), AudioChunk(samples: [5, 6, 7, 8], endPosition: 8)])
        XCTAssertEqual(reframer.drain(), [9])
    }

    func testAnEmptyItemAtTheExpectedPositionChangesNothing() {
        var reframer = ChunkReframer()
        XCTAssertTrue(reframer.push([Float](repeating: 1, count: 300), endingAt: 300).isEmpty)
        XCTAssertTrue(reframer.push([], endingAt: 300).isEmpty)
        XCTAssertEqual(reframer.pendingCount, 300)
        XCTAssertEqual(reframer.expectedNextPosition, 300)
        XCTAssertTrue(reframer.push([], endingAt: 900).isEmpty)          // an empty item at a new position re-seats
        XCTAssertEqual(reframer.pendingCount, 0)
        XCTAssertEqual(reframer.expectedNextPosition, 900)
    }

    /// A position that goes backwards (a broadcast writer restarting at zero) is a discontinuity like any other.
    func testABackwardsPositionReseatsLikeAnyDiscontinuity() {
        var reframer = ChunkReframer()
        XCTAssertTrue(reframer.push([Float](repeating: 1, count: 300), endingAt: 5_300).isEmpty)
        let chunks = reframer.push([Float](repeating: 2, count: 512), endingAt: 512)
        XCTAssertEqual(chunks.map(\.endPosition), [512])
        XCTAssertTrue(chunks[0].samples.allSatisfy { $0 == 2 })
        XCTAssertEqual(reframer.pendingCount, 0)
        XCTAssertEqual(reframer.expectedNextPosition, 512)
    }
}
