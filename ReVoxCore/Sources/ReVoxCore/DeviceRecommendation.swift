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
