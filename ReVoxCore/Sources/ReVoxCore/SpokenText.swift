import Foundation

/// What the voice is allowed to say, and what the transcript is allowed to show (§5.3).
///
/// The Windows version fed faster-whisper's segment text straight to the TTS, and faster-whisper never emits
/// Whisper's special tokens. WhisperKit does not either while `skipSpecialTokens` is true — its `SegmentSeeker`
/// decodes segment text from the tokens below `specialTokenBegin`, so `<|es|>`, `<|translate|>` and the
/// timestamp tokens are already filtered (verified in the pinned 1.1.0 checkout). This is the boundary that
/// makes that a guarantee of ReVox rather than a property of a dependency: whatever a future model, decoder
/// setting or upstream bump produces, the only thing that reaches the speaker is the translated sentence.
public enum SpokenText {
    /// Removes any residual `<|…|>` span, then collapses the whitespace that removing one leaves behind.
    /// Everything else — punctuation, casing, accents, the sentence itself — is left exactly as translated.
    public static func clean(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var index = text.unicodeScalars.startIndex
        let scalars = text.unicodeScalars
        while index < scalars.endIndex {
            if scalars[index] == "<", let close = specialTokenEnd(in: scalars, from: index) {
                index = close
                continue
            }
            out.append(scalars[index])
            index = scalars.index(after: index)
        }
        return collapseWhitespace(String(out))
    }

    /// The index just past a `<|…|>` span starting at `start`, or nil when this `<` does not open one.
    /// A bare `<` in a sentence ("a < b") is left alone, because it is text the speaker should say.
    private static func specialTokenEnd(in scalars: String.UnicodeScalarView,
                                        from start: String.UnicodeScalarView.Index) -> String.UnicodeScalarView.Index? {
        var index = scalars.index(after: start)
        guard index < scalars.endIndex, scalars[index] == "|" else { return nil }
        index = scalars.index(after: index)
        while index < scalars.endIndex {
            if scalars[index] == "|" {
                let next = scalars.index(after: index)
                guard next < scalars.endIndex else { return nil }
                if scalars[next] == ">" { return scalars.index(after: next) }
            }
            if scalars[index] == "<" { return nil }          // an unterminated span is not a token
            index = scalars.index(after: index)
        }
        return nil
    }

    /// Runs of whitespace become one space, and the ends are trimmed — so removing a token from
    /// "<|es|> hola" leaves "hola", not " hola".
    static func collapseWhitespace(_ text: String) -> String {
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !current.isEmpty {
                    parts.append(String(current))
                    current = String.UnicodeScalarView()
                }
                continue
            }
            current.append(scalar)
        }
        if !current.isEmpty { parts.append(String(current)) }
        return parts.joined(separator: " ")
    }
}
