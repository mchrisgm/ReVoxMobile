import Foundation
@testable import ReVoxMobile

@MainActor
final class FakeInstallHost: InstallHost {
    private(set) var begun: [(identifier: Int, name: String)] = []
    private(set) var ended: [Int] = []
    private var expirations: [Int: @MainActor () -> Void] = [:]
    private var next = 1
    private var idleTimerDisabled = false
    /// Every value the manager assigned, in order, so a test can assert the timer was not left on.
    private(set) var idleTimerHistory: [Bool] = []

    var isIdleTimerDisabled: Bool {
        get { idleTimerDisabled }
        set {
            idleTimerDisabled = newValue
            idleTimerHistory.append(newValue)
        }
    }

    func beginBackgroundTask(name: String, expiration: @escaping @MainActor () -> Void) -> Int {
        let identifier = next
        next += 1
        begun.append((identifier, name))
        expirations[identifier] = expiration
        return identifier
    }

    func endBackgroundTask(_ identifier: Int) {
        ended.append(identifier)
        expirations[identifier] = nil
    }

    /// Simulates iOS expiring the background time of every open task.
    func expireAll() {
        for (_, handler) in expirations {
            handler()
        }
    }
}
