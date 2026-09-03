import XCTest
@testable import ReVoxCore

final class BoundedSegmentQueueTests: XCTestCase {
    func testDefaultCapacityIsThree() {
        XCTAssertEqual(BoundedSegmentQueue<Int>.defaultCapacity, 3)
        XCTAssertEqual(BoundedSegmentQueue<Int>().capacity, 3)
    }

    func testDropsOldestWhenFull() {
        var queue = BoundedSegmentQueue<Int>(capacity: 2)
        var dropped: [Int] = []
        for value in 1 ... 6 {
            dropped.append(queue.push(value))
        }
        XCTAssertEqual(dropped, [0, 0, 1, 1, 1, 1])          // one drop per push from the third on
        XCTAssertEqual(dropped.reduce(0, +), 4)
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.pop(), 5)                        // the survivors are the last two pushed
        XCTAssertEqual(queue.pop(), 6)
        XCTAssertNil(queue.pop())
    }

    func testPopIsFIFO() {
        var queue = BoundedSegmentQueue<String>()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.push("a"), 0)
        XCTAssertEqual(queue.push("b"), 0)
        XCTAssertEqual(queue.push("c"), 0)
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.pop(), "a")
        XCTAssertEqual(queue.push("d"), 0)
        XCTAssertEqual(queue.pop(), "b")
        XCTAssertEqual(queue.pop(), "c")
        XCTAssertEqual(queue.pop(), "d")
    }

    func testRemoveAllEmpties() {
        var queue = BoundedSegmentQueue<Int>()
        _ = queue.push(1)
        _ = queue.push(2)
        queue.removeAll()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertNil(queue.pop())
    }
}
