import Foundation

/// A Latin transliteration of a phrase for Learning mode (M9): what the words sound like, for a reader who
/// cannot read the script they were spoken in.
public enum Romanizer {
    /// nil when the transliteration would change nothing — already-Latin text, or nothing at all — so the row
    /// never shows the same line twice.
    public static func romanize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let latin = trimmed.applyingTransform(.toLatin, reverse: false) else { return nil }
        let cleaned = latin.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned == trimmed || cleaned.isEmpty ? nil : cleaned
    }
}
