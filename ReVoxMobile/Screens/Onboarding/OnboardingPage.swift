import Foundation
import ReVoxCore

/// The first-run tutorial's pages (M10, refreshed in M11 §6), in the order they are shown. Each page is a title,
/// one sentence under it, the symbol the hero morphs into, and — on the view side — a demo the reader can tap:
/// the real Live control strip, the real Languages group and the real transcript rows over a demo model, so what
/// the tutorial shows is what the app does and nothing can drift.
enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, controls, transcript, twoWay, learning, models, ready

    var id: Int { rawValue }

    /// The pages in the order the tutorial walks through them.
    static let ordered: [OnboardingPage] = allCases

    var title: String {
        switch self {
        case .welcome: return "Welcome to ReVox"
        case .controls: return "The Live controls"
        case .transcript: return "Start and read"
        case .twoWay: return "Two-way conversation"
        case .learning: return "Learning mode"
        case .models: return "Models and voices"
        case .ready: return "You're ready"
        }
    }

    /// Where a sentence names a control it reads the strip's own static, so a rename on Live shows up here
    /// without an edit (`OnboardingTests.testTheTutorialNamesTheStripsControls`).
    var subtitle: String {
        switch self {
        case .welcome:
            return "ReVox hears speech, translates it into English on this iPhone, speaks the translation and keeps a transcript. Nothing you say or hear leaves the phone."
        case .controls:
            return "Three groups of pills sit above the transcript: \(LiveControlStrip.listenCaption), \(LiveControlStrip.voiceCaption) and \(LiveControlStrip.languagesCaption). A pill says what it is set to — tap it to change it, \(LiveControlStrip.moreAccessibilityLabel) to read what each one does, and Start to see them lock."
        case .transcript:
            return "Tap Start and speak. Each finished phrase appears with its language and its English translation, is spoken aloud, and shows how long ago it was said. A phrase ReVox is not sure about arrives greyed and marked Unsure: kept in the transcript, never spoken."
        case .twoWay:
            return "In a conversation ReVox should not echo your own language back at you; it should say what you say to the other person in theirs. Tell it what you speak and what they speak, then turn on \(LiveControlStrip.twoWayPillName) to see both directions."
        case .learning:
            return "\(LiveControlStrip.learningPillName) shows the words as they were spoken above the translation, so you can follow the other language as well as understand it. \(OnboardingDemo.wordTapText)"
        case .models:
            return "ReVox translates with a Whisper model you download once. Voices are optional; the iPhone's own voice needs no download."
        case .ready:
            return "That is all there is to it. You can show this tutorial again any time from Settings."
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "waveform.and.mic"
        case .controls: return "slider.horizontal.3"
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
    static let twoWayIgnored = "en"
    static let twoWayTarget = "es"
    static let bothSidesText = "Both sides stay in the transcript."

    /// The card's footnote while Two-way is on, following the pills' languages (M11 §6: "What you say in English is
    /// spoken to them in Spanish, and what they say is spoken to you in English. Both sides stay in the
    /// transcript."). With nothing chosen, or both the same, Live's own line says what is still missing.
    static func twoWayOnText(you: String?, they: String) -> String {
        guard let you, you != they else { return LiveView.twoWaySummary(you: you, they: they) }
        let youName = LanguageCatalog.displayName(you, whenNil: LiveView.noLanguageTitle)
        let theyName = LanguageCatalog.displayName(they, whenNil: LiveView.noLanguageTitle)
        return "What you say in \(youName) is spoken to them in \(theyName), and what they say is spoken to you in English. \(bothSidesText)"
    }

    /// The footnote while Two-way is off: Live's own line, then the invitation.
    static func twoWayOffText(you: String?) -> String {
        "\(LiveView.twoWayOffSummary(you: you)) Turn on \(LiveControlStrip.twoWayPillName) to answer them in their language."
    }

    /// The second sentence of the Learning page (M11 §2): the same words Settings › Learning gains.
    static let wordTapText = "Tap any word for its pronunciation and meaning."

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
    /// The chip that says "default": the catalogue's default, so the word stays true whatever the benchmark
    /// (M11 §5) recommends on a given iPhone.
    static let recommendedModel: WhisperModelID = ModelCatalog.defaultWhisperModel
    /// M11 §6: the one line the Models page gains.
    static let benchmarkText = "Settings › Models › Benchmark this iPhone measures them on your iPhone."
    static let systemVoiceText = "The iPhone's own voice — works at once, no download."
    static let pocketVoiceText = "pocket-tts — optional, four natural voices, downloaded once from Settings › Voices."
}
