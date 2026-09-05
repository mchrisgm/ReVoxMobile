import Foundation

/// R13: a pure function of physical memory. Models outside `suitable` remain downloadable.
public struct DeviceRecommendation: Sendable, Equatable {
    public let recommended: WhisperModelID
    public let suitable: Set<WhisperModelID>
    public let warnings: [WhisperModelID: String]

    public static let heatWarning = "Long load time and heat"

    public init(recommended: WhisperModelID, suitable: Set<WhisperModelID>, warnings: [WhisperModelID: String]) {
        self.recommended = recommended
        self.suitable = suitable
        self.warnings = warnings
    }

    public static func forPhysicalMemory(bytes: UInt64) -> DeviceRecommendation {
        let tier = memoryTierGB(bytes: bytes)
        if tier < 4 {
            return DeviceRecommendation(recommended: .base, suitable: [.tiny, .base, .small], warnings: [:])
        }
        if tier < 6 {
            return DeviceRecommendation(recommended: .small, suitable: [.tiny, .base, .small], warnings: [:])
        }
        if tier < 8 {
            return DeviceRecommendation(recommended: .small, suitable: [.tiny, .base, .small, .medium], warnings: [:])
        }
        return DeviceRecommendation(recommended: .small,
                                    suitable: Set(WhisperModelID.allCases),
                                    warnings: [.medium: heatWarning, .largeV3: heatWarning])
    }

    /// Nearest whole GiB: absorbs the few hundred MB that `physicalMemory` reports below the nominal size.
    public static func memoryTierGB(bytes: UInt64) -> Int {
        Int((Double(bytes) / 1_073_741_824).rounded())
    }

    /// pocket-tts advisory (never a gate): nil at ≥ 6 GB; below, a warning that the system voice may be used under
    /// memory pressure (ASSUMED wording and threshold; resident-memory numbers measured in M4).
    public static func pocketTTSAdvisory(memoryTierGB: Int) -> String? {
        guard memoryTierGB < 6 else { return nil }
        return "On this iPhone pocket-tts and a Whisper model share limited memory; ReVox falls back to the system voice if memory runs low."
    }
}

// MARK: - M11 §5: the measured rule

extension DeviceRecommendation {
    /// ASSUMED thresholds (recorded in `docs/measurements/m11-model-benchmark.md`, row 7): a measured model is
    /// recommended only when its steady real-time factor is below this and it loaded within `maxLoadSeconds`.
    public static let maxRealTimeFactor = 0.5
    public static let maxLoadSeconds = 10.0

    /// Measured, with audio, fast enough to keep up and quick enough to load.
    public static func qualifies(_ result: ModelBenchmarkResult) -> Bool {
        !result.isSkipped && result.audioSeconds > 0
            && result.realTimeFactor < maxRealTimeFactor && result.loadSeconds < maxLoadSeconds
    }

    /// Among `results` inside the memory tier's suitable set, the lowest word error rate that qualifies; ties go to
    /// the lower real-time factor, then to catalogue order. `nil` when nothing qualifies. The caller passes only
    /// results for models that are installed now.
    public static func bestMeasured(memory: DeviceRecommendation, results: [ModelBenchmarkResult]) -> WhisperModelID? {
        let order = ModelCatalog.whisperModels.map(\.id)
        let candidates = results.filter { memory.suitable.contains($0.model) && qualifies($0) }
        let best = candidates.min { lhs, rhs in
            if lhs.wordErrorRate != rhs.wordErrorRate { return lhs.wordErrorRate < rhs.wordErrorRate }
            if lhs.realTimeFactor != rhs.realTimeFactor { return lhs.realTimeFactor < rhs.realTimeFactor }
            return (order.firstIndex(of: lhs.model) ?? order.count) < (order.firstIndex(of: rhs.model) ?? order.count)
        }
        return best?.model
    }

    /// The memory tier with `recommended` replaced by the best measured model; the memory tier unchanged when
    /// nothing qualifies. `suitable` and `warnings` always come from memory.
    public static func measured(memory: DeviceRecommendation, results: [ModelBenchmarkResult]) -> DeviceRecommendation {
        guard let best = bestMeasured(memory: memory, results: results) else { return memory }
        return DeviceRecommendation(recommended: best, suitable: memory.suitable, warnings: memory.warnings)
    }
}
