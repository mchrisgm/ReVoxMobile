import Foundation
@testable import ReVoxCore

/// The Windows `FakeSegmenter`: every fed chunk is one segment; `flush()` returns nil.
actor FakeSegmenter: PhraseSegmenter {
    private(set) var resetCount = 0
    private(set) var feedCount = 0

    func feed(_ samples: [Float]) async throws -> [[Float]] {
        feedCount += 1
        return [samples]
    }

    func flush() async -> [Float]? {
        nil
    }

    func reset() async {
        resetCount += 1
    }
}
