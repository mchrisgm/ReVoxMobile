import AVFAudio
import Foundation
import os
import ReVoxCore

/// `AudioSource` for mic mode (§6.1). The tap thread only converts and yields; the core re-frames to 512.
final class MicrophoneCapture: AudioSource, @unchecked Sendable {
    static let tapBufferSize: AVAudioFrameCount = 4_096
    /// A rebuild that finds no input tries this many times in all before the status line says so (§6.1).
    static let rebuildRetryLimit = 3
    /// The wait between rebuild attempts while iOS re-seats the route (ASSUMED, measured in M3, §13).
    static let rebuildRetryDelay: TimeInterval = 0.2
    private static let logger = Logger(subsystem: "revox", category: "microphone")

    private let controller: AudioSessionController
    private let permission: MicrophonePermission
    private let center: NotificationCenter
    private let tap: TapSeam
    private let onStatus: @Sendable (String?) -> Void
    private let lock = NSLock()
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    private var position: Int64 = 0
    private var resampler: MicrophoneResampler?
    private var tapEngine: AVAudioEngine?
    private var configurationToken: NSObjectProtocol?
    private var fallbackLogged = false
    private var routeRebuilds = 0
    /// True while "No microphone input" is on the status line, so each change is published exactly once.
    private var statusPublished = false
    private let rebuildQueue = DispatchQueue(label: "revox.microphone.rebuild")

    init(controller: AudioSessionController,
         permission: MicrophonePermission = .live,
         center: NotificationCenter = .default,
         tap: TapSeam = .live,
         onStatus: @escaping @Sendable (String?) -> Void = { _ in }) {
        self.controller = controller
        self.permission = permission
        self.center = center
        self.tap = tap
        self.onStatus = onStatus
    }

    var usedFallbackResampler: Bool {
        lock.lock(); defer { lock.unlock() }
        return tapEngine != nil && resampler == nil
    }

    /// Tap rebuilds requested by a route change (§6.1); the tap itself is only touched while one is installed.
    var routeRebuildCount: Int {
        lock.lock(); defer { lock.unlock() }
        return routeRebuilds
    }

    // MARK: AudioSource

    /// A fresh stream per call; the previous continuation is finished so the pipeline restarts cleanly.
    func frames() -> AsyncStream<CapturedAudio> {
        lock.lock(); defer { lock.unlock() }
        continuation?.finish()
        let (stream, newContinuation) = AsyncStream<CapturedAudio>.makeStream(bufferingPolicy: .unbounded)
        continuation = newContinuation
        return stream
    }

    func capturePosition() async -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return position
    }

    func start(_ mode: CaptureMode) async throws {
        guard mode == .microphone else { throw CaptureError.unsupportedMode(mode) }
        switch permission.status() {
        case .denied:
            throw CaptureError.microphoneDenied
        case .undetermined:
            guard await permission.request() else { throw CaptureError.microphoneDenied }
        case .granted:
            break
        }
        guard let engine = await controller.engineForGraph() else { throw CaptureError.engineUnavailable }
        try installTap(on: engine)
        observeConfigurationChanges(of: engine)
        await controller.setRouteChangeHandler { [weak self] reason in
            self?.handleRouteChange(reason)
        }
    }

    func stop() async {
        lock.lock()
        let engine = tapEngine
        tapEngine = nil
        resampler = nil
        let token = configurationToken
        configurationToken = nil
        continuation?.finish()
        continuation = nil
        statusPublished = false
        lock.unlock()
        if let engine {
            tap.remove(engine)
        }
        if let token {
            center.removeObserver(token)
        }
        await controller.setRouteChangeHandler(nil)
    }

    // MARK: Tap

    private func installTap(on engine: AVAudioEngine) throws {
        guard let format = tap.inputFormat(engine) else { throw CaptureError.noInput }
        let resampler = MicrophoneResampler(inputFormat: format)
        lock.lock()
        self.resampler = resampler
        tapEngine = engine
        let logFallback = resampler == nil && !fallbackLogged
        if logFallback { fallbackLogged = true }
        lock.unlock()
        if logFallback {
            Self.logger.error("AVAudioConverter refused the tap format \(format, privacy: .public); using the linear reference resampler (W1)")
        }
        tap.install(engine, format, Self.tapBufferSize) { [weak self] buffer in
            self?.handleTap(buffer)
        }
    }

    private var loggedConversions = 0

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let resampler = self.resampler
        let shouldLog = loggedConversions < 5
        if shouldLog { loggedConversions += 1 }
        lock.unlock()
        let samples = resampler.map { $0.convert(buffer) } ?? Self.fallbackResample(buffer)
        if shouldLog {
            Self.logger.info("tap frames=\(buffer.frameLength, privacy: .public) rate=\(buffer.format.sampleRate, privacy: .public) out=\(samples.count, privacy: .public) fallback=\(resampler == nil, privacy: .public)")
        }
        deliver(samples)
    }

    /// Stamps the cumulative 16 kHz position on the run and yields it; internal so tests feed samples without hardware.
    func deliver(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock()
        position += Int64(samples.count)
        let end = position
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(CapturedAudio(samples: samples, endPosition: end))
    }

    /// W1 fallback: planar Float32 → interleaved → core `toMono16k` (linear interpolation).
    static func fallbackResample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        guard let data = buffer.floatChannelData, frames > 0, channels > 0 else { return [] }
        var interleaved = [Float](repeating: 0, count: frames * channels)
        for channel in 0..<channels {
            for frame in 0..<frames {
                interleaved[frame * channels + channel] = data[channel][frame]
            }
        }
        return AudioFormat.toMono16k(interleaved: interleaved, channels: channels, sampleRate: Int(buffer.format.sampleRate))
    }

    // MARK: Route changes (§6.1, §6.8, §9 "Route change → Rebuild tap/converter for device changes")

    /// Called by `AudioSessionController` for every `routeChangeNotification` reason while the tap is installed.
    /// A device change invalidates the tap format and the converter, so both are rebuilt; `.categoryChange` and
    /// every other reason are no-ops. The capture counter is never reset here (§5.2).
    func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            lock.lock(); routeRebuilds += 1; lock.unlock()
            rebuildQueue.async { [weak self] in self?.rebuildTap() }
        default:
            return
        }
    }

    // MARK: Configuration changes (§6.1: rebuild off the notification queue, never deallocate the engine)

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        let token = center.addObserver(forName: Notification.Name.AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.rebuildQueue.async { self?.rebuildTap() }
        }
        lock.lock(); configurationToken = token; lock.unlock()
    }

    /// Re-seats the tap on the current hardware format. `installTap(on:)` throws `CaptureError.noInput` while iOS
    /// is still moving the route, so the attempt is repeated `rebuildRetryLimit` times in all, `rebuildRetryDelay`
    /// apart; if the input is still gone the pipeline keeps running on silence and the status line shows
    /// "No microphone input" (§6.1). A rebuild that succeeds clears that line. Always runs on `rebuildQueue`.
    private func rebuildTap(attempt: Int = 1) {
        lock.lock()
        let engine = tapEngine
        lock.unlock()
        guard let engine else { return }
        tap.remove(engine)
        do {
            try installTap(on: engine)
        } catch {
            Self.logger.error("tap rebuild attempt \(attempt, privacy: .public) of \(Self.rebuildRetryLimit, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if attempt < Self.rebuildRetryLimit {
                rebuildQueue.asyncAfter(deadline: .now() + Self.rebuildRetryDelay) { [weak self] in
                    self?.rebuildTap(attempt: attempt + 1)
                }
            } else {
                publishStatus(CaptureError.noInput.description)
            }
            return
        }
        publishStatus(nil)
        let controller = self.controller
        Task {
            do {
                try await controller.startEngine()
            } catch {
                Self.logger.error("engine restart after a tap rebuild failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Publishes the capture status line once per change: the text when the input is gone, nil when it is back.
    /// Task 40 hands this to `AudioSessionController.publishCaptureStatus`, which the Live screen renders.
    private func publishStatus(_ text: String?) {
        lock.lock()
        guard (text != nil) != statusPublished else {
            lock.unlock()
            return
        }
        statusPublished = text != nil
        lock.unlock()
        onStatus(text)
    }
}
