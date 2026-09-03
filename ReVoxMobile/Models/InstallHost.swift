import Foundation
import UIKit

/// The `UIApplication` calls an install needs (§6.9): background time for the current file and the idle timer.
@MainActor
protocol InstallHost: AnyObject {
    func beginBackgroundTask(name: String, expiration: @escaping @MainActor () -> Void) -> Int
    func endBackgroundTask(_ identifier: Int)
    var isIdleTimerDisabled: Bool { get set }
}

@MainActor
final class UIApplicationInstallHost: InstallHost {
    func beginBackgroundTask(name: String, expiration: @escaping @MainActor () -> Void) -> Int {
        let identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            Task { @MainActor in expiration() }
        }
        return identifier.rawValue
    }

    func endBackgroundTask(_ identifier: Int) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: identifier))
    }

    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}
