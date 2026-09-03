import Foundation

/// One probability per 512-sample chunk at 16 kHz, semantics of the Silero JIT model `model(chunk, 16000)`.
public protocol SpeechProbabilityModel: Sendable {
    /// `chunk.count == Segmenter.chunkSamples`.
    func probability(of chunk: [Float]) async throws -> Float
    /// Clears the model's recurrent state. Called once per pipeline start through `Segmenter.reset()`.
    func reset() async
}

/// Port of `PRESETS` in `revox/pipeline/segmenter.py`.
public enum SegmenterPreset: String, CaseIterable, Codable, Sendable {
    case balanced, fast

    /// `silence_ms`: balanced 500, fast 300.
    public var silenceMs: Int {
        switch self {
        case .balanced: return 500
        case .fast: return 300
        }
    }

    /// `max_segment_s`: balanced 10.0, fast 4.0.
    public var maxSegmentSeconds: Double {
        switch self {
        case .balanced: return 10.0
        case .fast: return 4.0
        }
    }
}

/// What the pipeline needs from a segmenter; lets tests substitute one in which every fed chunk is one segment.
public protocol PhraseSegmenter: AnyObject, Sendable {
    func feed(_ samples: [Float]) async throws -> [[Float]]
    func flush() async -> [Float]?
    func reset() async
}

/// Port of `revox/pipeline/segmenter.py:Segmenter`: turns a continuous 16 kHz stream into phrases using a per-chunk
/// speech probability.
///
/// `@unchecked Sendable`: the mutable state is driven from one task at a time (the pipeline's capture stage), exactly
/// like the Windows object that is only touched by the capture thread. Never feed one instance from two tasks.
public final class Segmenter: @unchecked Sendable {
    public static let chunkSamples = 512          // CHUNK_SAMPLES
    public static let sampleRate = 16_000         // SAMPLE_RATE
    public static let defaultSpeechThreshold: Float = 0.5
    public static let defaultPaddingMs = 200

    public let preset: SegmenterPreset
    public let speechThreshold: Float
    public let silenceChunks: Int                 // max(1, Int(silenceMs/1000 * 16000 / 512))
    public let maxChunks: Int                     // max(1, Int(maxSegmentSeconds * 16000 / 512))
    public let paddingChunks: Int                 // max(1, Int(paddingMs/1000 * 16000 / 512))

    private let vad: any SpeechProbabilityModel
    private var preRoll: [[Float]] = []           // deque(maxlen=paddingChunks)
    private var pending: [Float] = []
    private var segment: [[Float]] = []
    private var silenceRun = 0
    private var inSpeech = false

    public init(vad: any SpeechProbabilityModel,
                preset: SegmenterPreset = .balanced,
                speechThreshold: Float = Segmenter.defaultSpeechThreshold,
                paddingMs: Int = Segmenter.defaultPaddingMs) {
        self.vad = vad
        self.preset = preset
        self.speechThreshold = speechThreshold
        // Python `int()` truncates; compute in Double and truncate, never round.
        let rate = Double(Segmenter.sampleRate)
        let chunk = Double(Segmenter.chunkSamples)
        silenceChunks = max(1, Int(Double(preset.silenceMs) / 1000 * rate / chunk))
        maxChunks = max(1, Int(preset.maxSegmentSeconds * rate / chunk))
        paddingChunks = max(1, Int(Double(paddingMs) / 1000 * rate / chunk))
    }

    /// Appends samples of any length; returns every phrase completed by this call.
    public func feed(_ samples: [Float]) async throws -> [[Float]] {
        pending.append(contentsOf: samples)
        var completed: [[Float]] = []
        while pending.count >= Segmenter.chunkSamples {
            let piece = Array(pending[0 ..< Segmenter.chunkSamples])
            pending.removeFirst(Segmenter.chunkSamples)
            if let done = try await process(piece) {
                completed.append(done)
            }
        }
        return completed
    }

    /// Emits the in-progress phrase, if any; returns nil when not in speech.
    public func flush() -> [Float]? {
        guard inSpeech, !segment.isEmpty else { return nil }
        return finish(segment)
    }

    /// Forgets pending samples, pre-roll and the in-progress phrase; also resets the VAD state.
    public func reset() async {
        pending.removeAll()
        preRoll.removeAll()
        segment.removeAll()
        silenceRun = 0
        inSpeech = false
        await vad.reset()
    }

    // `_process`
    private func process(_ piece: [Float]) async throws -> [Float]? {
        let isSpeech = try await vad.probability(of: piece) >= speechThreshold
        if !inSpeech {
            if isSpeech {
                inSpeech = true
                segment = preRoll + [piece]
                silenceRun = 0
            } else {
                preRoll.append(piece)
                if preRoll.count > paddingChunks {
                    preRoll.removeFirst()
                }
            }
            return nil
        }

        segment.append(piece)
        if isSpeech {
            silenceRun = 0
        } else {
            silenceRun += 1
        }

        if silenceRun >= silenceChunks {
            let keepTail = silenceRun - paddingChunks
            let body = Array(segment.dropLast(max(0, keepTail)))
            return finish(body)
        }
        if segment.count >= maxChunks {
            return finish(segment)
        }
        return nil
    }

    // `_finish`
    private func finish(_ chunks: [[Float]]) -> [Float] {
        let joined = Array(chunks.joined())
        segment.removeAll()
        silenceRun = 0
        inSpeech = false
        preRoll.removeAll()
        return joined
    }
}

extension Segmenter: PhraseSegmenter {}
