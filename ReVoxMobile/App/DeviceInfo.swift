import Foundation
import os
import ReVoxCore

/// `ProcessInfo.processInfo.physicalMemory` is the only input of the device recommendation (C6, R13, §6.11).
struct DeviceInfo: Sendable, Equatable {
    let physicalMemoryBytes: UInt64

    var memoryTierGB: Int {
        DeviceRecommendation.memoryTierGB(bytes: physicalMemoryBytes)
    }

    var recommendation: DeviceRecommendation {
        DeviceRecommendation.forPhysicalMemory(bytes: physicalMemoryBytes)
    }

    static func current(processInfo: ProcessInfo = .processInfo) -> DeviceInfo {
        DeviceInfo(physicalMemoryBytes: processInfo.physicalMemory)
    }

    /// Logged once per launch; the reported values on the test devices are the M3 measurement of §10.4.
    func logOnce(logger: Logger = Logger(subsystem: "revox", category: "device")) {
        let recommendation = self.recommendation
        logger.info("physicalMemory=\(self.physicalMemoryBytes, privacy: .public) tierGB=\(self.memoryTierGB, privacy: .public) recommended=\(recommendation.recommended.rawValue, privacy: .public)")
    }
}
