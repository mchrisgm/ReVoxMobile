import Foundation

/// One fixed sentence the benchmark has the iPhone's own voice say, and the English it should come back as (M11 §5).
public struct BenchmarkSentence: Codable, Sendable, Equatable {
    public let language: String
    public let text: String
    public let reference: String

    public init(language: String, text: String, reference: String) {
        self.language = language
        self.text = text
        self.reference = reference
    }
}

/// The stimuli, in the order they are tried; English is the fallback every iPhone can say.
public enum BenchmarkSentences {
    public static let spanish = BenchmarkSentence(language: "es", text: "Buenos días, ¿dónde está la estación de tren?",
                                                  reference: "Good morning, where is the train station?")
    public static let french = BenchmarkSentence(language: "fr", text: "Bonjour, où est la gare, s'il vous plaît ?",
                                                 reference: "Hello, where is the train station, please?")
    public static let german = BenchmarkSentence(language: "de", text: "Guten Morgen, wo ist der Bahnhof?",
                                                 reference: "Good morning, where is the train station?")
    public static let english = BenchmarkSentence(language: "en", text: "Good morning, where is the train station?",
                                                  reference: "Good morning, where is the train station?")
    public static let preferred: [BenchmarkSentence] = [spanish, french, german]

    /// The first preferred sentence the iPhone has a voice for, else English.
    public static func first(spokenBy hasVoice: (String) -> Bool) -> BenchmarkSentence {
        preferred.first { hasVoice($0.language) } ?? english
    }
}

/// Why a model was not measured; the text shown after "Skipped: " and stored in the run.
public enum BenchmarkSkipReason {
    public static let tooHot = "iPhone too hot"
    public static let cancelled = "cancelled"

    public static func couldNotLoad(_ message: String) -> String { "couldn't load: \(message)" }
    public static func couldNotTranslate(_ message: String) -> String { "couldn't translate: \(message)" }
}

/// One model's measurements from one run (M11 §5). A skipped model has `skippedReason` set and zeros elsewhere.
public struct ModelBenchmarkResult: Codable, Sendable, Equatable, Identifiable {
    public let model: WhisperModelID
    public let loadSeconds: Double
    public let firstSeconds: Double
    public let steadySeconds: Double
    public let audioSeconds: Double
    /// `steadySeconds / audioSeconds`; 0 when no audio was measured (never infinite: the run is JSON).
    public let realTimeFactor: Double
    public let wordErrorRate: Double
    public let residentBeforeMB: Int
    public let peakDeltaMB: Int
    public let thermalState: String
    public let skippedReason: String?
    /// The gate's English for the sentence, so the owner can read what the model heard.
    public let hypothesis: String

    public var id: WhisperModelID { model }
    public var isSkipped: Bool { skippedReason != nil }

    public init(model: WhisperModelID, loadSeconds: Double, firstSeconds: Double, steadySeconds: Double, audioSeconds: Double,
                wordErrorRate: Double, residentBeforeMB: Int, peakDeltaMB: Int, thermalState: String,
                skippedReason: String? = nil, hypothesis: String = "") {
        self.model = model
        self.loadSeconds = loadSeconds
        self.firstSeconds = firstSeconds
        self.steadySeconds = steadySeconds
        self.audioSeconds = audioSeconds
        self.realTimeFactor = audioSeconds > 0 ? steadySeconds / audioSeconds : 0
        self.wordErrorRate = wordErrorRate
        self.residentBeforeMB = residentBeforeMB
        self.peakDeltaMB = peakDeltaMB
        self.thermalState = thermalState
        self.skippedReason = skippedReason
        self.hypothesis = hypothesis
    }

    public static func skipped(_ model: WhisperModelID, reason: String, thermalState: String) -> ModelBenchmarkResult {
        ModelBenchmarkResult(model: model, loadSeconds: 0, firstSeconds: 0, steadySeconds: 0, audioSeconds: 0, wordErrorRate: 1,
                             residentBeforeMB: 0, peakDeltaMB: 0, thermalState: thermalState, skippedReason: reason)
    }
}

/// One benchmark run, the JSON the store keeps (M11 §5).
public struct BenchmarkRun: Codable, Sendable, Equatable {
    public let date: Date
    /// The hardware identifier (`utsname.machine`, e.g. "iPhone17,1"); a run from another iPhone is ignored.
    public let device: String
    public let iOSVersion: String
    public let memoryTierGB: Int
    public let whisperKitVersion: String
    public let sentence: BenchmarkSentence
    public let results: [ModelBenchmarkResult]

    public init(date: Date, device: String, iOSVersion: String, memoryTierGB: Int, whisperKitVersion: String,
                sentence: BenchmarkSentence, results: [ModelBenchmarkResult]) {
        self.date = date
        self.device = device
        self.iOSVersion = iOSVersion
        self.memoryTierGB = memoryTierGB
        self.whisperKitVersion = whisperKitVersion
        self.sentence = sentence
        self.results = results
    }

    /// The results that were actually measured, in run order.
    public var measured: [ModelBenchmarkResult] { results.filter { !$0.isSkipped } }

    public func result(for model: WhisperModelID) -> ModelBenchmarkResult? {
        results.first { $0.model == model }
    }
}

/// Every user-visible wording about a result, in one Linux-tested place. No `String(format:)` and no locale:
/// integer arithmetic gives the same text on swift-corelibs-foundation and on the iPhone.
public enum BenchmarkVerdict {
    public static let keepsUp = "Keeps up"
    public static let tooSlow = "Too slow for live use"
    public static let slowToLoad = "Slow to load"
    public static let notMeasured = "not measured"
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                             "October", "November", "December"]

    /// "4", "2.1", "0.5": one decimal, a trailing zero dropped.
    public static func oneDecimal(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0" }
        let tenths = Int((value * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    /// "0.08", "1.25": always two decimals.
    public static func twoDecimals(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0.00" }
        let hundredths = Int((value * 100).rounded())
        let fraction = hundredths % 100
        return "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// "4.2× faster than real time" / "as fast as real time" / "1.6× slower than real time" / "not measured".
    public static func speedText(realTimeFactor: Double) -> String {
        guard realTimeFactor.isFinite, realTimeFactor > 0 else { return notMeasured }
        if realTimeFactor < 0.95 { return "\(oneDecimal(1 / realTimeFactor))× faster than real time" }
        if realTimeFactor <= 1.05 { return "as fast as real time" }
        return "\(oneDecimal(realTimeFactor))× slower than real time"
    }

    /// "loads in under a second" / "loads in 6 s".
    public static func loadText(seconds: Double) -> String {
        seconds < 0.95 ? "loads in under a second" : "loads in \(Int(seconds.rounded())) s"
    }

    /// "every word right" / "88 % of words right" (accuracy clamps at 0).
    public static func accuracyText(wordErrorRate: Double) -> String {
        guard wordErrorRate > 0 else { return "every word right" }
        return "\(Int((max(0, 1 - wordErrorRate) * 100).rounded())) % of words right"
    }

    /// "uses 240 MB" (the peak resident delta of the run).
    public static func memoryText(megabytes: Int) -> String { "uses \(megabytes) MB" }

    /// "4.2× faster than real time · loads in 3 s · 88 % of words right · uses 240 MB"; a skipped result reads
    /// "Skipped: <reason>".
    public static func line(_ result: ModelBenchmarkResult) -> String {
        if let reason = result.skippedReason { return "Skipped: \(reason)" }
        return [speedText(realTimeFactor: result.realTimeFactor), loadText(seconds: result.loadSeconds),
                accuracyText(wordErrorRate: result.wordErrorRate), memoryText(megabytes: result.peakDeltaMB)].joined(separator: " · ")
    }

    /// "Keeps up" / "Too slow for live use" / "Slow to load" / "Skipped: <reason>" — a word, never a colour.
    public static func summaryText(_ result: ModelBenchmarkResult) -> String {
        if let reason = result.skippedReason { return "Skipped: \(reason)" }
        if DeviceRecommendation.qualifies(result) { return keepsUp }
        if result.audioSeconds <= 0 || result.realTimeFactor >= DeviceRecommendation.maxRealTimeFactor { return tooSlow }
        return slowToLoad
    }

    public static func summarySymbol(_ result: ModelBenchmarkResult) -> String {
        if result.isSkipped { return "minus.circle" }
        if DeviceRecommendation.qualifies(result) { return "checkmark.circle" }
        if result.audioSeconds <= 0 || result.realTimeFactor >= DeviceRecommendation.maxRealTimeFactor { return "tortoise" }
        return "hourglass"
    }

    // MARK: Spoken twins (units in full, as the M10 rows do)

    /// "4.2 times faster than real time".
    public static func spokenSpeedText(realTimeFactor: Double) -> String {
        speedText(realTimeFactor: realTimeFactor).replacingOccurrences(of: "×", with: " times")
    }

    /// "loads in 3 seconds" / "loads in 1 second" / "loads in under a second".
    public static func spokenLoadText(seconds: Double) -> String {
        guard seconds >= 0.95 else { return loadText(seconds: seconds) }
        let whole = Int(seconds.rounded())
        return "loads in \(whole) \(whole == 1 ? "second" : "seconds")"
    }

    /// "uses 240 megabytes".
    public static func spokenMemoryText(megabytes: Int) -> String { "uses \(megabytes) megabytes" }

    /// The VoiceOver sentence of a result row: "small. Keeps up. 4.2 times faster than real time. loads in 3
    /// seconds. 88 % of words right. uses 240 megabytes" or "medium. Skipped: iPhone too hot".
    public static func spokenText(_ result: ModelBenchmarkResult) -> String {
        if let reason = result.skippedReason { return "\(result.model.displayName). Skipped: \(reason)" }
        return [result.model.displayName, summaryText(result), spokenSpeedText(realTimeFactor: result.realTimeFactor),
                spokenLoadText(seconds: result.loadSeconds), accuracyText(wordErrorRate: result.wordErrorRate),
                spokenMemoryText(megabytes: result.peakDeltaMB)].joined(separator: ". ")
    }

    /// "14 November 2023" in `timeZone`: fixed English month names, so the text is the same on every device.
    public static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.day ?? 1) \(monthNames[max(0, min(11, (parts.month ?? 1) - 1))]) \(parts.year ?? 1970)"
    }
}

/// The text the share sheet exports and the owner pastes into `docs/measurements/m11-model-benchmark.md`.
public enum BenchmarkReport {
    public static let columns = "| Model | Load s | First s | Steady s | Audio s | RTF | WER | Resident before MB | Peak delta MB | Thermal | Verdict |"
    static let rule = "|---|---|---|---|---|---|---|---|---|---|---|"

    public static func markdown(_ run: BenchmarkRun) -> String {
        var lines = [
            "# ReVox benchmark · \(run.device) · iOS \(run.iOSVersion) · \(run.memoryTierGB) GB · WhisperKit \(run.whisperKitVersion) · \(timestamp(run.date))",
            "",
            "Sentence (\(run.sentence.language)): \(run.sentence.text)",
            "Reference: \(run.sentence.reference)",
            "",
            columns,
            rule,
        ]
        for result in run.results {
            lines.append(row(result))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One table row; a skipped model shows dashes and its reason.
    public static func row(_ result: ModelBenchmarkResult) -> String {
        if let reason = result.skippedReason {
            return "| \(result.model.displayName) | – | – | – | – | – | – | – | – | \(result.thermalState) | Skipped: \(reason) |"
        }
        let cells = [
            result.model.displayName,
            BenchmarkVerdict.oneDecimal(result.loadSeconds),
            BenchmarkVerdict.oneDecimal(result.firstSeconds),
            BenchmarkVerdict.oneDecimal(result.steadySeconds),
            BenchmarkVerdict.oneDecimal(result.audioSeconds),
            BenchmarkVerdict.twoDecimals(result.realTimeFactor),
            BenchmarkVerdict.twoDecimals(result.wordErrorRate),
            "\(result.residentBeforeMB)",
            "\(result.peakDeltaMB)",
            result.thermalState,
            BenchmarkVerdict.summaryText(result),
        ]
        return "| " + cells.joined(separator: " | ") + " |"
    }

    /// "2023-11-14T22:13:20Z": Gregorian components in UTC, zero-padded (no `DateFormatter`, as `TranscriptFormatter`).
    public static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            let number = value ?? 0
            return number < 10 ? "0\(number)" : "\(number)"
        }
        return "\(c.year ?? 1970)-\(pad(c.month))-\(pad(c.day))T\(pad(c.hour)):\(pad(c.minute)):\(pad(c.second))Z"
    }
}
