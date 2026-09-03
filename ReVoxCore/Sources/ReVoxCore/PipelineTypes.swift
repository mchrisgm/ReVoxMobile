import Foundation

public enum CaptureMode: String, Codable, Sendable, CaseIterable {
    case microphone, broadcast
}

/// A run of 16 kHz mono Float32 samples whose last sample sits at absolute capture position `endPosition`
/// (samples occupy [endPosition − samples.count, endPosition) on the source's timeline).
public struct CapturedAudio: Sendable, Equatable {
    public var samples: [Float]
    public var endPosition: Int64

    public init(samples: [Float], endPosition: Int64) {
        self.samples = samples
        self.endPosition = endPosition
    }
}

public protocol AudioSource: Sendable {
    /// A fresh stream per call: chunks of any length, in capture order, positions non-decreasing. Samples captured
    /// after `start` are yielded into the most recently returned stream; the stream finishes on `stop()`.
    /// The pipeline calls `frames()` before `start(_:)` on every run, so a source can be restarted.
    func frames() -> AsyncStream<CapturedAudio>
    /// The source's current capture position (mic: frames yielded so far; broadcast: the ring writeCursor now).
    func capturePosition() async -> Int64
    func start(_ mode: CaptureMode) async throws
    func stop() async
}

public protocol Speaker: Sendable {
    var sampleRate: Int { get }
    /// Whitespace-only text must return an empty clip without touching the engine.
    func synthesize(_ text: String) async throws -> AudioClip
}

public protocol AudioPlayer: Sendable {
    func start() async throws
    func enqueue(_ clip: AudioClip) async
    func setMuted(_ muted: Bool) async
    func clear() async
    func stop() async
    var isSpeaking: Bool { get async }
}
public typealias AudioPlayerFactory = @Sendable (_ sampleRate: Int, _ onSpeaking: @escaping SpeakingCallback) -> any AudioPlayer

public enum PipelineState: String, Sendable, Equatable {
    case idle, running, error
}

public enum PipelineEvent: Sendable, Equatable {
    case state(PipelineState)
    case entry(TranscriptEntry)
    case lag
    case speaking(Bool)
    case error(String)
}

public struct PipelineConfiguration: Sendable, Equatable {
    public var captureMode: CaptureMode
    public var preset: SegmenterPreset
    public var pinnedLanguage: String?
    public var maxPending: Int = 3
    public var captureGateHoldFrames: Int = CaptureGate.defaultHoldFrames
    public var captureLatencyFrames: Int = 0                       // ASSUMED broadcast value, measured in M5
    public var duckingEnabled: Bool = true
    public var duckingHoldNanoseconds: UInt64 = DuckingCoordinator.defaultHoldNanoseconds

    public init(captureMode: CaptureMode,
                preset: SegmenterPreset,
                pinnedLanguage: String? = nil,
                maxPending: Int = 3,
                captureGateHoldFrames: Int = CaptureGate.defaultHoldFrames,
                captureLatencyFrames: Int = 0,
                duckingEnabled: Bool = true,
                duckingHoldNanoseconds: UInt64 = DuckingCoordinator.defaultHoldNanoseconds) {
        self.captureMode = captureMode
        self.preset = preset
        self.pinnedLanguage = pinnedLanguage
        self.maxPending = maxPending
        self.captureGateHoldFrames = captureGateHoldFrames
        self.captureLatencyFrames = captureLatencyFrames
        self.duckingEnabled = duckingEnabled
        self.duckingHoldNanoseconds = duckingHoldNanoseconds
    }
}

public typealias SegmenterFactory = @Sendable (_ vad: any SpeechProbabilityModel, _ preset: SegmenterPreset) -> any PhraseSegmenter

public struct PipelineDependencies: Sendable {
    public var source: any AudioSource
    public var vad: any SpeechProbabilityModel
    public var detector: any LanguageDetector
    public var translator: any Translator
    public var speaker: any Speaker
    public var playerFactory: AudioPlayerFactory
    public var ducker: any Ducker
    public var transcriptFactory: TranscriptSinkFactory
    public var segmenterFactory: SegmenterFactory = { vad, preset in Segmenter(vad: vad, preset: preset) }
    public var clock: @Sendable () -> Date = { Date() }
    public var sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }

    public init(source: any AudioSource,
                vad: any SpeechProbabilityModel,
                detector: any LanguageDetector,
                translator: any Translator,
                speaker: any Speaker,
                playerFactory: @escaping AudioPlayerFactory,
                ducker: any Ducker,
                transcriptFactory: @escaping TranscriptSinkFactory,
                segmenterFactory: @escaping SegmenterFactory = { vad, preset in Segmenter(vad: vad, preset: preset) },
                clock: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.source = source
        self.vad = vad
        self.detector = detector
        self.translator = translator
        self.speaker = speaker
        self.playerFactory = playerFactory
        self.ducker = ducker
        self.transcriptFactory = transcriptFactory
        self.segmenterFactory = segmenterFactory
        self.clock = clock
        self.sleep = sleep
    }
}
