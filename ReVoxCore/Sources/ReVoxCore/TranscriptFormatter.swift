import Foundation

/// Port of `revox/transcript.py:TranscriptEntry`.
public struct TranscriptEntry: Sendable, Equatable, Codable {
    public var timestamp: Date
    public var language: String
    public var original: String          // always "" on both platforms
    public var english: String

    public init(timestamp: Date, language: String, original: String, english: String) {
        self.timestamp = timestamp
        self.language = language
        self.original = original
        self.english = english
    }
}

public enum TranscriptItem: Sendable, Equatable {
    case entry(TranscriptEntry)
    case dropMarker(Date)
}

/// Port of the file format written by `revox/transcript.py:TranscriptSession`. Core formats; the app stores and writes files.
public struct TranscriptFormatter: Sendable {
    public static let headerPrefix = "# ReVox session "
    public static let dropMarkerText = "… (skipped: falling behind)"      // U+2026

    /// The only stored property, a value type, so `Sendable` holds (no `DateFormatter`).
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    /// "yyyy-MM-dd_HH-mm-ss.txt" (Python `f"{started:%Y-%m-%d_%H-%M-%S}.txt"`).
    public func fileName(startedAt: Date) -> String {
        let c = components(of: startedAt)
        return "\(c.year)-\(c.month)-\(c.day)_\(c.hour)-\(c.minute)-\(c.second).txt"
    }

    /// "# ReVox session yyyy-MM-dd'T'HH:mm:ss\n" (Python `isoformat(timespec="seconds")` on a naive local datetime).
    public func header(startedAt: Date) -> String {
        let c = components(of: startedAt)
        return "\(Self.headerPrefix)\(c.year)-\(c.month)-\(c.day)T\(c.hour):\(c.minute):\(c.second)\n"
    }

    /// "[HH:mm:ss] [<lang>] <original>\n  → <english>\n" (two spaces, U+2192, one space).
    public func line(for entry: TranscriptEntry) -> String {
        "[\(stamp(entry.timestamp))] [\(entry.language)] \(entry.original)\n  → \(entry.english)\n"
    }

    /// "[HH:mm:ss] … (skipped: falling behind)\n"
    public func dropMarkerLine(at time: Date) -> String {
        "[\(stamp(time))] \(Self.dropMarkerText)\n"
    }

    /// Header plus items in order, with consecutive drop markers collapsed to one (Windows `_last_was_drop`).
    public func export(startedAt: Date, items: [TranscriptItem]) -> String {
        var text = header(startedAt: startedAt)
        var lastWasDrop = false
        for item in items {
            switch item {
            case .entry(let entry):
                text += line(for: entry)
                lastWasDrop = false
            case .dropMarker(let time):
                if lastWasDrop { continue }
                text += dropMarkerLine(at: time)
                lastWasDrop = true
            }
        }
        return text
    }

    // "HH:mm:ss"
    private func stamp(_ date: Date) -> String {
        let c = components(of: date)
        return "\(c.hour):\(c.minute):\(c.second)"
    }

    private struct Padded {
        let year: String, month: String, day: String, hour: String, minute: String, second: String
    }

    /// Gregorian components in the stored time zone, zero-padded. The arithmetic is identical on
    /// swift-corelibs-foundation and Apple Foundation.
    private func components(of date: Date) -> Padded {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return Padded(year: pad(c.year ?? 0, 4), month: pad(c.month ?? 0, 2), day: pad(c.day ?? 0, 2),
                      hour: pad(c.hour ?? 0, 2), minute: pad(c.minute ?? 0, 2), second: pad(c.second ?? 0, 2))
    }

    private func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }
}
