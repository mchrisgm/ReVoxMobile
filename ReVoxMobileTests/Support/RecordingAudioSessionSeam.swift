import AVFAudio
import Foundation
@testable import ReVoxMobile

final class FakeEngineSeam: AudioEngineSeam {
    var isRunning = false
    var startFails = false
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    /// Real engine for tests that attach nodes; nil by default.
    var engine: AVAudioEngine?

    func prepare() { prepareCount += 1 }

    func start() throws {
        startCount += 1
        if startFails { throw NSError(domain: "FakeEngineSeam", code: 1, userInfo: [NSLocalizedDescriptionKey: "engine start refused"]) }
        isRunning = true
    }

    func pause() { pauseCount += 1; isRunning = false }
    func stop() { stopCount += 1; isRunning = false }
}

/// Records every session call in order; M4 adds suspension points for the ducking-cycle tests.
final class RecordingAudioSessionSeam: AudioSessionSeam, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [String] = []
    private(set) var masks: [SessionMask] = []
    private(set) var engines: [FakeEngineSeam] = []
    var engineFactory: () -> FakeEngineSeam = { FakeEngineSeam() }

    func setCategory(_ mask: SessionMask) throws {
        lock.lock(); calls.append("setCategory"); masks.append(mask); lock.unlock()
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        lock.lock()
        calls.append(active ? "setActive(true)" : (options.contains(.notifyOthersOnDeactivation) ? "setActive(false, notify)" : "setActive(false)"))
        lock.unlock()
    }

    func makeEngine() -> any AudioEngineSeam {
        let engine = engineFactory()
        lock.lock(); calls.append("makeEngine"); engines.append(engine); lock.unlock()
        return engine
    }

    var lastEngine: FakeEngineSeam? { lock.lock(); defer { lock.unlock() }; return engines.last }
}
