import AVFAudio
import Foundation
import os

enum InterruptionEvent: Equatable, Sendable {
    case began
    case ended(shouldResume: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason)
    case mediaServicesReset
}

/// The one adapter around `interruptionNotification`, `routeChangeNotification` and
/// `mediaServicesWereResetNotification` (§6.8; the iOS 27 seam of §12). Every `.began` is logged with its
/// `AVAudioSessionInterruptionReasonKey`; the suspended key cannot fire on iOS 17 and is not read.
@MainActor
final class InterruptionObserver {
    let events: AsyncStream<InterruptionEvent>
    private let continuation: AsyncStream<InterruptionEvent>.Continuation
    private var tokens: [NSObjectProtocol] = []
    /// `nonisolated`: the notification block below runs off the main actor and both members are pure, so the
    /// class keeps `@MainActor` only for `events`, `continuation` and `tokens` (a main-actor-isolated static
    /// would make every call from the block and from the tests an `#ActorIsolatedCall` error in Swift 5 mode).
    nonisolated private static let logger = Logger(subsystem: "revox", category: "session")

    init(center: NotificationCenter = .default) {
        let (stream, continuation) = AsyncStream<InterruptionEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [continuation] notification in
                if let event = InterruptionObserver.event(from: notification) {
                    if case .began = event {
                        let reason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
                        InterruptionObserver.logger.info("interruption began reason=\(reason ?? 0, privacy: .public)")
                    }
                    continuation.yield(event)
                }
            })
        }
    }

    /// `nonisolated`: a pure `Notification` → `InterruptionEvent` mapping, called from the notification block
    /// above and directly from `AudioSessionControllerTests.testInterruptionNotificationParsing`.
    nonisolated static func event(from notification: Notification) -> InterruptionEvent? {
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
            switch type {
            case .began:
                return .began
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                return .ended(shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume))
            @unknown default:
                return nil
            }
        case AVAudioSession.routeChangeNotification:
            guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return nil }
            return .routeChanged(reason: reason)
        case AVAudioSession.mediaServicesWereResetNotification:
            return .mediaServicesReset
        default:
            return nil
        }
    }

    deinit {
        continuation.finish()
    }
}
