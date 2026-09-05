import SwiftUI
import ReVoxCore

/// One example under a setting (M9): a symbol, one sentence of what the setting does with the current value,
/// and — where a transcript row is the subject — the row itself, rendered by the same view the Live screen uses.
/// A footer of prose tells the reader what a setting *is*; this shows what it *does*.
struct SettingExample<Content: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder let content: () -> Content

    init(symbol: String, text: String, @ViewBuilder content: @escaping () -> Content) {
        self.symbol = symbol
        self.text = text
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(text)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: \(text)")
    }
}

extension SettingExample where Content == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}

/// The copy and the sample rows behind every example, kept off the views so the tests can read them.
enum SettingExamples {
    static let sampleTime = Date(timeIntervalSince1970: 1_700_000_000)
    static let spanishOriginal = "¿Dónde está la estación?"
    static let spanishEnglish = "Where is the station?"
    /// Kana on purpose: ICU transliterates kanji by their Chinese readings, and an example should be right.
    static let japaneseOriginal = "おはよう"

    static func latency(_ preset: SegmenterPreset) -> String {
        switch preset {
        case .balanced: return "A phrase is finished after half a second of silence, or at 10 seconds. Waits a little; keeps sentences whole."
        case .fast: return "A phrase is finished after 0.3 s of silence, or at 4 seconds. Quicker, with longer sentences split in two."
        case .veryFast: return "A phrase is finished after 0.2 s of silence, or at 3 seconds. Quickest, with more and shorter phrases and more work for the model."
        }
    }

    static let sourceLanguageAuto = "Auto-detect hears “\(spanishOriginal)” as Spanish and translates it. A phrase it cannot place is shown greyed and marked Unsure, and is not spoken."
    static func sourceLanguagePinned(_ name: String) -> String {
        "Every phrase is decoded as \(name), even one spoken in another language. Pin only when you know what you will hear."
    }

    static let skipLanguageNone = "Everything is translated into English, including you. Choose the language you speak so a conversation is not echoed back at you."
    static func skipLanguage(_ name: String) -> String {
        "“\(spanishEnglish)” said in \(name) is not translated and not transcribed. Turn on Two-way on the Live tab to have it spoken to the other person in their language instead."
    }
    /// M10/M11: a pinned source language is never detected, so You speak only ever matches when it names the pinned
    /// language itself — and then it matches every phrase.
    static func skipLanguageWhilePinned(ignored: String, pinned: String) -> String {
        if ignored == pinned {
            return "Source language is pinned to \(pinned) and \(ignored) is the language you speak, so every phrase counts as yours and nothing is translated. Change one of the two."
        }
        return "Source language is pinned to \(pinned), so nothing is ever heard as \(ignored) and everything is translated, including you. Set Source language to Auto-detect for You speak to work."
    }
    /// The one the screen shows: `ignored` and `pinned` are display names, nil for Not set and Auto-detect.
    static func skipLanguageText(ignored: String?, pinned: String?) -> String {
        guard let ignored else { return skipLanguageNone }
        guard let pinned else { return skipLanguage(ignored) }
        return skipLanguageWhilePinned(ignored: ignored, pinned: pinned)
    }

    static let mute = "The transcript keeps running; nothing is spoken until you unmute."
    static func ducking(_ on: Bool) -> String {
        on ? "While ReVox speaks, other apps' audio is lowered by iOS, then restored." : "Other apps keep their volume while ReVox speaks; the two overlap."
    }
    static func voiceVolume(_ volume: Double) -> String {
        "ReVox's own voice plays at \(Int((volume * 100).rounded())) %. Other apps are not affected."
    }

    static func keepModelWhenHot(_ on: Bool, model: WhisperModelID) -> String {
        on ? "iPhone is hot — the next session still uses \(model.displayName)."
           : "iPhone is hot: translation reduced — the next session uses a smaller installed model until it cools down."
    }

    static func learning(_ on: Bool) -> String {
        on ? "The words as spoken appear above the translation." : "Only the translation is shown."
    }
    static func romanize(_ on: Bool) -> String {
        on ? "Under a script you cannot read, how it sounds in Latin letters." : "The original is shown in its own script only."
    }
    /// M10: with Learning off there is no original to romanize, and the toggle above is disabled; say why.
    static let romanizeNeedsLearning = "Turn on Learning to show the original; Romanize then adds how it sounds in Latin letters."
    static func romanizeText(on: Bool, learning: Bool) -> String {
        learning ? romanize(on) : romanizeNeedsLearning
    }

    static func timeDisplay(_ mode: Settings.TimeDisplay) -> String {
        switch mode {
        case .time: return "Each phrase shows the time it was said."
        case .age: return "Each phrase shows how long ago it was said, counting up as you read."
        case .both: return "Each phrase shows how long ago it was said and the time."
        }
    }

    /// The Spanish row every row-based example renders; `original` empty unless the example is about learning.
    static func sampleRow(original: String = "") -> LiveTranscriptRow {
        LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, time: sampleTime,
                          kind: .entry(language: "es", original: original, english: spanishEnglish))
    }

    static let japaneseRow = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, time: sampleTime,
                                               kind: .entry(language: "ja", original: japaneseOriginal, english: "Good morning."))
}
