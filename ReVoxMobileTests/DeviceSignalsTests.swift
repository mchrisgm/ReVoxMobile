import XCTest
import UIKit
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class DeviceSignalsTests: XCTestCase {
    /// `thermalStateDidChangeNotification` fires on a *change*. An app launched on a phone that is already
    /// `.serious` or `.critical` would run the §9 policy at `.nominal` until the next transition — translating at
    /// full size on a hot device, or not pausing at critical — so the launch state is replayed once.
    func testALaunchOnAHotDeviceReplaysTheThermalStateOnce() async {
        let center = NotificationCenter()
        let signals = DeviceSignals(center: center, initialThermalState: .serious)
        var iterator = signals.signals.makeAsyncIterator()
        var copy = iterator
        let first = await withTimeout(seconds: 1) { await copy.next() }
        iterator = copy
        XCTAssertEqual(first, .thermalState(.serious))

        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        var next = iterator
        let second = await withTimeout(seconds: 1) { await next.next() }
        XCTAssertEqual(second, .memoryWarning, "then the observers deliver as before")
    }

    func testACriticalLaunchIsReplayedToo() async {
        let signals = DeviceSignals(center: NotificationCenter(), initialThermalState: .critical)
        var iterator = signals.signals.makeAsyncIterator()
        let first = await withTimeout(seconds: 1) { await iterator.next() }
        XCTAssertEqual(first, .thermalState(.critical))
    }

    /// `.nominal` and `.fair` have no effect in the policy; replaying them would only churn the log.
    func testANominalOrFairLaunchReplaysNothing() async {
        for state in [ProcessInfo.ThermalState.nominal, .fair] {
            let signals = DeviceSignals(center: NotificationCenter(), initialThermalState: state)
            var iterator = signals.signals.makeAsyncIterator()
            let first = await withTimeout(seconds: 0.2) { await iterator.next() }
            XCTAssertNil(first, "nothing replayed for \(state)")
        }
    }
}
