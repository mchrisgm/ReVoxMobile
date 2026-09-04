import AVFAudio
import Foundation
import os

/// A complete `setCategory(_:mode:options:)` argument set (§6.8). Masks are always passed whole; `.mixWithOthers` is explicit.
struct SessionMask: Equatable, @unchecked Sendable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
}

/// The engine operations the controller performs; the production seam wraps one `AVAudioEngine`.
protocol AudioEngineSeam: AnyObject {
    var isRunning: Bool { get }
    /// The real engine for graph work (input tap, player node); nil in test fakes.
    var engine: AVAudioEngine? { get }
    func prepare()
    func start() throws
    func pause()
    func stop()
}

/// The session operations the controller performs; recorded (and suspended, in M4) by the tests.
protocol AudioSessionSeam: AnyObject, Sendable {
    func setCategory(_ mask: SessionMask) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    func makeEngine() -> any AudioEngineSeam
}

final class LiveAudioEngineSeam: AudioEngineSeam {
    private let live: AVAudioEngine

    init() {
        live = AVAudioEngine()
        live.isAutoShutdownEnabled = false   // R8: the I/O unit never stops during silence
    }

    var isRunning: Bool { live.isRunning }
    var engine: AVAudioEngine? { live }
    func prepare() { live.prepare() }
    func start() throws { try live.start() }
    func pause() { live.pause() }
    func stop() { live.stop() }
}

final class LiveAudioSessionSeam: AudioSessionSeam, @unchecked Sendable {
    private static let logger = Logger(subsystem: "revox", category: "ducking")

    func setCategory(_ mask: SessionMask) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(mask.category, mode: mask.mode, options: mask.options)
        // The evidence for "no .duckOthers resident once the cycle ends": what the session reports, not what we asked for.
        Self.logger.info("session categoryOptions=\(session.categoryOptions.rawValue, privacy: .public) duckOthers=\(session.categoryOptions.contains(.duckOthers), privacy: .public) otherAudioPlaying=\(session.isOtherAudioPlaying, privacy: .public)")
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try AVAudioSession.sharedInstance().setActive(active, options: options)
    }

    func makeEngine() -> any AudioEngineSeam {
        LiveAudioEngineSeam()
    }
}

extension SessionMask {
    /// The same category, mode and route options with `option` added — the "duck on" masks of §6.8.
    func adding(_ option: AVAudioSession.CategoryOptions) -> SessionMask {
        var copy = self
        copy.options.insert(option)
        return copy
    }
}
