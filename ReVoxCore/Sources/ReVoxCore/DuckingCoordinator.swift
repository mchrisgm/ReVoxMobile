import Foundation

/// Lowers everything else while ReVox speaks. No target pid: iOS ducks "everything else" in both modes (W6).
public protocol Ducker: Sendable {
    func duck() async
    func restore() async
}

/// Port of the ducking policy in `pipeline.py:_on_speaking` plus the idempotence of `ducking.py`, with the iOS hold
/// (R8): `restore()` is issued only after the speaking-false edge has been quiet for `hold` nanoseconds.
///
/// Contract: `isDucked` is written *before* the `await` on the `Ducker`, never after it returns, so a
/// `speakingChanged(true)` that arrives while a long `restore()` is in flight issues a new `duck()`.
public actor DuckingCoordinator {
    public static let defaultHoldNanoseconds: UInt64 = 250_000_000     // ~250 ms (R8)

    private let ducker: any Ducker
    private let hold: UInt64
    private let sleep: @Sendable (UInt64) async throws -> Void
    private var enabled: Bool
    public private(set) var isDucked = false
    private var holdTask: Task<Void, Never>?

    public init(ducker: any Ducker, enabled: Bool, hold: UInt64 = DuckingCoordinator.defaultHoldNanoseconds,
                sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) {
        self.ducker = ducker
        self.enabled = enabled
        self.hold = hold
        self.sleep = sleep
    }

    /// Disabling while ducked restores immediately; while disabled no `Ducker` call is made by any method.
    public func setEnabled(_ newValue: Bool) async {
        if !newValue {
            cancelHold()
        }
        let restoreNeeded = !newValue && isDucked
        if restoreNeeded {
            isDucked = false
        }
        enabled = newValue
        if restoreNeeded {
            await ducker.restore()
        }
    }

    public func speakingChanged(_ speaking: Bool) async {
        guard enabled else { return }
        if speaking {
            cancelHold()
            guard !isDucked else { return }          // Windows Ducker.duck: if self._ducked: return
            isDucked = true
            await ducker.duck()
        } else {
            guard isDucked else { return }
            cancelHold()
            holdTask = Task { [hold, sleep] in
                do {
                    try await sleep(hold)
                } catch {
                    return                            // cancelled inside the hold
                }
                guard !Task.isCancelled else { return }
                await self.holdElapsed()
            }
        }
    }

    /// mute, stop, error: cancels any hold and always forwards `restore()` (the Windows call pattern).
    public func restoreNow() async {
        cancelHold()
        guard enabled else { return }
        isDucked = false
        await ducker.restore()
    }

    private func holdElapsed() async {
        guard !Task.isCancelled, enabled, isDucked else { return }
        holdTask = nil
        isDucked = false
        await ducker.restore()
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }
}
