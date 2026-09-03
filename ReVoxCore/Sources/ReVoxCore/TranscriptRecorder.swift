import Foundation

/// Where the pipeline writes transcript entries and drop markers (Windows `TranscriptSession`).
public protocol TranscriptSink: Sendable {
    func add(_ entry: TranscriptEntry) async
    func addDropMarker(at time: Date) async
    func close() async
}
public typealias TranscriptSinkFactory = @Sendable () -> any TranscriptSink

/// In-memory `TranscriptSink` with the Windows dedupe rule; the app's SwiftData sink reuses it for the flag.
public actor TranscriptRecorder: TranscriptSink {
    public let startedAt: Date
    private let formatter: TranscriptFormatter
    public private(set) var items: [TranscriptItem] = []
    public private(set) var isClosed = false
    private var lastWasDrop = false          // _last_was_drop

    public init(startedAt: Date, formatter: TranscriptFormatter = TranscriptFormatter()) {
        self.startedAt = startedAt
        self.formatter = formatter
    }

    /// Ignored after `close()`.
    public func add(_ entry: TranscriptEntry) {
        guard !isClosed else { return }
        items.append(.entry(entry))
        lastWasDrop = false
    }

    /// Ignored while closed or when the last item is a drop marker.
    public func addDropMarker(at time: Date) {
        guard !isClosed, !lastWasDrop else { return }
        items.append(.dropMarker(time))
        lastWasDrop = true
    }

    /// Idempotent.
    public func close() {
        isClosed = true
    }

    public func exportText() -> String {
        formatter.export(startedAt: startedAt, items: items)
    }
}
