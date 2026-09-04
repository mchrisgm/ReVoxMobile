import Foundation

/// VoiceOver sentences for the Live status line and the progress rows (§8.8): the visual " · " separator and the
/// " — " dash become spoken punctuation, and every part ends with a full stop unless it already ends with an ellipsis.
enum LiveStatusAccessibility {
    /// The parameters are the status line's parts in the order §8.2 lists them: model, voice, lag, ducking,
    /// session status, broadcast attach state.
    static func label(modelStatus: String, voiceStatus: String, isFallingBehind: Bool, duckingStatus: String?,
                      sessionStatus: String?, broadcastStatus: String?) -> String {
        var sentences = [sentence("Model \(modelStatus.replacingOccurrences(of: " · ", with: " "))")]
        if voiceStatus.hasPrefix("System voice") {
            let remainder = String(voiceStatus.dropFirst("System voice".count)).replacingOccurrences(of: " — ", with: ": ")
            sentences.append(sentence("Using system voice\(remainder)"))
        } else {
            sentences.append(sentence("Using \(voiceStatus)"))
        }
        if isFallingBehind { sentences.append(sentence("Falling behind")) }
        if let duckingStatus { sentences.append(sentence(duckingStatus)) }
        if let sessionStatus { sentences.append(sentence(sessionStatus)) }
        if let broadcastStatus { sentences.append(sentence(broadcastStatus)) }
        return sentences.joined(separator: " ")
    }

    /// "42 percent"; nil and out-of-range fractions are clamped so a spinner-less bar always has a spoken value.
    static func percentText(_ fraction: Double?) -> String {
        let clamped = min(1, max(0, fraction ?? 0))
        return "\(Int((clamped * 100).rounded(.down))) percent"
    }

    private static func sentence(_ text: String) -> String {
        text.hasSuffix("…") ? text : text + "."
    }
}
