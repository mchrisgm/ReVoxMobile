import Foundation

/// How long ago a Live row was said (M9): a reader following a conversation wants "12 s", not "10:41:07".
public enum RelativeAge {
    /// "now" under a second, whole seconds under a minute, whole minutes under an hour, then hours and minutes.
    /// A `then` in the future reads as "now": the clock skewed, and a negative age would only confuse.
    public static func text(from then: Date, to now: Date) -> String {
        let interval = now.timeIntervalSince(then)
        // A `Date` can carry NaN or infinity and `Int(_:)` traps on both; a row whose timestamp came back from
        // storage as garbage must not crash the screen on every redraw. Nonsense reads as "now" like a future
        // timestamp does, and a huge but finite age is clamped so the conversion cannot trap either.
        guard interval.isFinite, interval >= 1 else { return "now" }
        let seconds = Int(min(interval, Double(Int.max / 4)).rounded(.down))
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
