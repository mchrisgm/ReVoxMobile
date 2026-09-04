import Foundation
import os

/// Resident-memory readings for the M4 measurement record (§10.4, §13 Q6/Q7).
///
/// Read straight from `task_info`, not from a library helper: the numbers decide whether the increased-memory-limit
/// entitlement is worth keeping and whether dropping the pocket-tts manager gives the memory back, so the reading
/// should not depend on another package's private conventions about which counter it reports.
enum MemoryMeter {
    private static let logger = Logger(subsystem: "revox", category: "measurements")

    private static func info() -> mach_task_basic_info? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    static func residentBytes() -> UInt64? { info().map { $0.resident_size } }
    static func peakBytes() -> UInt64? { info().map { $0.resident_size_max } }

    static func log(_ label: String) {
        logger.info("memory \(label, privacy: .public) resident_mb=\((residentBytes() ?? 0) / 1_048_576, privacy: .public) peak_mb=\((peakBytes() ?? 0) / 1_048_576, privacy: .public)")
    }
}
