import Foundation
@testable import ReVoxCore

/// The Windows `FakeTranscript`: entries, drop count, closed flag.
actor FakeTranscriptSink: TranscriptSink {
    private(set) var entries: [TranscriptEntry] = []
    private(set) var drops = 0
    private(set) var dropTimes: [Date] = []
    private(set) var closed = false

    func add(_ entry: TranscriptEntry) async {
        entries.append(entry)
    }

    func addDropMarker(at time: Date) async {
        drops += 1
        dropTimes.append(time)
    }

    func close() async {
        closed = true
    }
}
