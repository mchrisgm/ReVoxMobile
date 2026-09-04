import Foundation

/// The segment queue of `pipeline.py:_enqueue_segment`: at most `capacity` pending elements, oldest dropped.
public struct BoundedSegmentQueue<Element: Sendable>: Sendable {
    public static var defaultCapacity: Int { 3 }              // max_pending

    public let capacity: Int
    private var elements: [Element] = []

    /// A capacity below one is one: the push loop drops everything and then appends, which is what Windows does for
    /// `max_pending = 0` too — so that is the capacity the queue reports, and "at most `capacity` pending" holds.
    public init(capacity: Int = 3) {
        self.capacity = max(1, capacity)
    }

    /// Drops the oldest elements until count < capacity, then appends. Returns the number dropped.
    public mutating func push(_ element: Element) -> Int {
        var dropped = 0
        while elements.count >= capacity, !elements.isEmpty {
            elements.removeFirst()
            dropped += 1
        }
        elements.append(element)
        return dropped
    }

    public mutating func pop() -> Element? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public mutating func removeAll() {
        elements.removeAll()
    }
}
