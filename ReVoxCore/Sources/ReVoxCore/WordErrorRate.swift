import Foundation

/// Word error rate for the on-device benchmark (M11 §5): Levenshtein distance over words divided by the number of
/// reference words. Foundation-only, so the score is the same on Linux and on the iPhone.
public enum WordErrorRate {
    /// Lowercased words. Letters, digits and whitespace survive; every other character is dropped, so "station?"
    /// and "¿dónde" compare as "station" and "dónde". Accents are kept: both sides are normalised the same way.
    public static func words(_ text: String) -> [String] {
        let kept = text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        return kept.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Levenshtein distance between two word arrays (insertions, deletions and substitutions cost one each).
    public static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0 ... b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1 ... a.count {
            current[0] = i
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Edits divided by the reference word count. An empty reference scores 0 against an empty hypothesis and 1
    /// against anything else. Insertions can push the rate above 1.
    public static func rate(reference: String, hypothesis: String) -> Double {
        let expected = words(reference)
        let heard = words(hypothesis)
        if expected.isEmpty { return heard.isEmpty ? 0 : 1 }
        return Double(editDistance(expected, heard)) / Double(expected.count)
    }

    /// `max(0, 1 − rate)`: accuracy never goes below zero.
    public static func accuracy(reference: String, hypothesis: String) -> Double {
        max(0, 1 - rate(reference: reference, hypothesis: hypothesis))
    }
}
