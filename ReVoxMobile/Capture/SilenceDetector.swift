import Foundation

/// "No audio from the app (some players are not captured)" (§6.2): `rmsLevel1s` below −60 dBFS for 10 s while attached.
struct SilenceDetector: Equatable, Sendable {
    static let thresholdLevel: Float = 0.001
    static let requiredSeconds: Double = 10

    private var quietSince: Double?
    private var reported = false

    init() {}

    /// Returns true exactly once per silent stretch, at the first observation ≥ 10 s after the stretch began.
    mutating func observe(rms: Float, now: Double) -> Bool {
        guard rms < Self.thresholdLevel else {
            quietSince = nil
            reported = false
            return false
        }
        guard let since = quietSince else {
            quietSince = now
            return false
        }
        guard !reported, now - since >= Self.requiredSeconds else { return false }
        reported = true
        return true
    }

    mutating func reset() {
        quietSince = nil
        reported = false
    }
}
