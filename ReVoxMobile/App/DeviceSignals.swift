import Foundation
import UIKit

/// The signals the M7 degradation policy consumes (§6.11, §9). Only observed here; nothing reacts to them in M3.
enum DeviceSignal: Sendable, Equatable {
    case thermalState(ProcessInfo.ThermalState)
    case lowPowerMode(Bool)
    case memoryWarning
}

@MainActor
final class DeviceSignals {
    let signals: AsyncStream<DeviceSignal>
    private let continuation: AsyncStream<DeviceSignal>.Continuation
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default, processInfo: ProcessInfo = .processInfo) {
        let (stream, continuation) = AsyncStream<DeviceSignal>.makeStream(bufferingPolicy: .bufferingNewest(8))
        self.signals = stream
        self.continuation = continuation
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [continuation] _ in
            continuation.yield(.thermalState(processInfo.thermalState))
        })
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [continuation] _ in
            continuation.yield(.lowPowerMode(processInfo.isLowPowerModeEnabled))
        })
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [continuation] _ in
            continuation.yield(.memoryWarning)
        })
    }

    deinit {
        continuation.finish()
    }
}
