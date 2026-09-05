import Foundation
import ReVoxCore

/// The first-run tutorial's pages (M10), in the order they are shown. Each page is a title, one sentence under
/// it, the symbol the hero morphs into, and — on the view side — a demo the reader can tap: the same segmented
/// control, toggles and transcript rows the Live screen uses, so what the tutorial shows is what the app does.
enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, source, transcript, twoWay, learning, models, ready

    var id: Int { rawValue }

    /// The pages in the order the tutorial walks through them.
    static let ordered: [OnboardingPage] = allCases

    var title: String {
        switch self {
        case .welcome: return "Welcome to ReVox"
        case .source: return "Choose a source"
        case .transcript: return "Start and read"
        case .twoWay: return "Two-way conversation"
        case .learning: return "Learning mode"
        case .models: return "Models and voices"
        case .ready: return "You're ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "ReVox hears speech, translates it into English on this iPhone, speaks the translation and keeps a transcript. Nothing you say or hear leaves the phone."
        case .source:
            return "Listen to the room through the microphone, or to a call, a video or anything else playing on this iPhone. Tap to try both."
        case .transcript:
            return "Tap Start and speak. Each finished phrase appears with its language and its English translation, is spoken aloud, and shows how long ago it was said."
        case .twoWay:
            return "In a conversation, your own language should be left alone and spoken back to the other person in theirs. Turn on Two-way to see both directions."
        case .learning:
            return "Learning shows the words as they were spoken above the translation, so you can follow the other language as well as understand it."
        case .models:
            return "ReVox translates with a Whisper model you download once. Voices are optional; the iPhone's own voice needs no download."
        case .ready:
            return "That is all there is to it. You can show this tutorial again any time from Settings."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "waveform.and.mic"
        case .source: return "dot.radiowaves.left.and.right"
        case .transcript: return "text.bubble"
        case .twoWay: return "arrow.left.arrow.right"
        case .learning: return "text.book.closed"
        case .models: return "cpu"
        case .ready: return "checkmark.circle"
        }
    }
}

/// One line of a demo list: a symbol and a sentence.
struct OnboardingPoint: Identifiable, Equatable, Sendable {
    let symbol: String
    let text: String
    var id: String { symbol + text }
}

/// The copy and the scripted rows behind the demos, kept off the views so the tests can read them.
enum OnboardingDemo {
    /// What ReVox does, one line each, revealed one after another on the Welcome page.
    static let welcomePoints: [OnboardingPoint] = [
        OnboardingPoint(symbol: "ear", text: "Hears the microphone, or other apps"),
        OnboardingPoint(symbol: "iphone", text: "Translates on the iPhone itself"),
        OnboardingPoint(symbol: "speaker.wave.2", text: "Speaks the translation aloud"),
        OnboardingPoint(symbol: "clock", text: "Keeps a transcript in History"),
    ]
    static let privacyText = "Nothing leaves the phone."

    /// The recap on the Ready page.
    static let readyPoints: [OnboardingPoint] = [
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Pick a source on the Live tab"),
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Tap Start, then Stop when you are done"),
        OnboardingPoint(symbol: "checkmark.circle.fill", text: "Every session is saved to History"),
    ]
    static let readyFootnote = "ReVox needs a Whisper model before the first translation. The Live tab asks you to download one; you can also find it under Settings › Models."

    /// A scripted conversation for the transcript demo, one row at a time. The last line is a guess (M11 §3):
    /// `LiveTranscriptRowView` greys it and marks it Unsure exactly as on Live.
    struct Line: Equatable, Sendable {
        let language: String
        let original: String
        let english: String
        var isGuess = false
    }

    static let transcriptScript: [Line] = [
        Line(language: "es", original: "Buenos días, ¿cómo estás?", english: "Good morning, how are you?"),
        Line(language: "fr", original: "Le train part à neuf heures.", english: "The train leaves at nine."),
        Line(language: "de", original: "Könnten Sie das wiederholen?", english: "Could you repeat that?"),
        Line(language: "es", original: "Claro, no hay problema.", english: "Of course, no problem."),
        Line(language: "pt", original: "Até logo, então.", english: "See you later, then.", isGuess: true),
    ]
    /// Seconds between two demo rows: long enough to read one before the next slides in.
    static let rowInterval: TimeInterval = 1.4
    static let transcriptEmptyText = "Tap Start to hear a short conversation."
    static let speakingText = "Speaking the translation aloud"
    /// Under the rows once the guess has arrived, and after Stop while the greyed row is still there.
    static let guessText = "The greyed phrase is marked Unsure: ReVox was not sure of it, so it is kept but not spoken."

    /// The two-way demo: what they said, translated to English, and your reply, spoken back in Spanish. The
    /// reply row carries the Spanish in its translation column, exactly as the Live screen shows it.
    static let theirLine = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, time: SettingExamples.sampleTime,
                                             kind: .entry(language: "es", original: "¿Nos vemos en la estación?", english: "Shall we meet at the station?"))
    static let yourReply = LiveTranscriptRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, time: SettingExamples.sampleTime.addingTimeInterval(6),
                                             kind: .entry(language: "en", original: "Yes, at nine.", english: "Sí, a las nueve."))
    static let twoWayOffText = "With Two-way off, what you say is translated into English too — and echoed back at you."
    static let twoWayOnText = "English is left alone and spoken back in Spanish. Both sides stay in the transcript."
    static let twoWayIgnored = "en"
    static let twoWayTarget = "es"

    static func learningText(learning: Bool, romanize: Bool) -> String {
        guard learning else { return SettingExamples.learning(false) }
        return romanize ? SettingExamples.romanize(true) : SettingExamples.learning(true)
    }

    /// One line per model: which to pick, and what it costs.
    static func modelNote(_ id: WhisperModelID) -> String {
        switch id {
        case .tiny: return "The quickest and the roughest. For an older iPhone, or when speed matters more than accuracy."
        case .base: return "Quick, with fewer mistakes than tiny. A good fallback when small runs warm."
        case .small: return "The default, and the right choice for most iPhones: accurate enough, quick enough, cool enough."
        case .medium: return "Noticeably more accurate, noticeably slower, and warm on a long session. Needs a recent iPhone."
        case .largeV3: return "The most accurate, and the slowest and hottest. Only for the newest iPhones, and short sessions."
        }
    }
    static let recommendedModel: WhisperModelID = .small
    static let systemVoiceText = "The iPhone's own voice — works at once, no download."
    static let pocketVoiceText = "pocket-tts — optional, four natural voices, downloaded once from Settings › Voices."
}
