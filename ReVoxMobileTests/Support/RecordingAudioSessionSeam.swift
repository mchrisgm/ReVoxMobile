import AVFAudio
import Foundation
import XCTest
@testable import ReVoxMobile

/// A suspension point for one seam step: when armed, the step's thread (the controller's cycle queue) blocks in
/// `pass()` until `resume()`, while the actor keeps accepting `duck()` / `restore()` calls.
final class StepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var held = false
    private let release = DispatchSemaphore(value: 0)

    func arm() {
        lock.lock(); armed = true; lock.unlock()
    }

    func pass() {
        lock.lock()
        guard armed else { lock.unlock(); return }
        armed = false
        held = true
        lock.unlock()
        release.wait()
        lock.lock(); held = false; lock.unlock()
    }

    var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return held }

    func resume() {
        release.signal()
    }

    /// Cancels an arming that was never reached, so a step arriving later is not blocked by it. Without this a test
    /// whose `waitUntilHeld` times out would hang the whole bundle on the next `pass()` instead of failing.
    func disarm() {
        lock.lock(); armed = false; lock.unlock()
    }

    func waitUntilHeld(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !isHeld {
            if Date() > deadline {
                disarm()
                XCTFail("the step was never held", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

final class FakeEngineSeam: AudioEngineSeam, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var fails = false
    private var prepares = 0
    private var starts = 0
    private var pauses = 0
    private var stops = 0
    private let startGate = StepGate()
    /// Real engine for tests that attach nodes; nil by default.
    var engine: AVAudioEngine?

    var isRunning: Bool {
        get { lock.lock(); defer { lock.unlock() }; return running }
        set { lock.lock(); running = newValue; lock.unlock() }
    }

    var startFails: Bool {
        get { lock.lock(); defer { lock.unlock() }; return fails }
        set { lock.lock(); fails = newValue; lock.unlock() }
    }

    var prepareCount: Int { lock.lock(); defer { lock.unlock() }; return prepares }
    var startCount: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var pauseCount: Int { lock.lock(); defer { lock.unlock() }; return pauses }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }

    func prepare() {
        lock.lock(); prepares += 1; lock.unlock()
    }

    func start() throws {
        lock.lock(); starts += 1; let fail = fails; lock.unlock()
        startGate.pass()
        if fail { throw NSError(domain: "FakeEngineSeam", code: 1, userInfo: [NSLocalizedDescriptionKey: "engine start refused"]) }
        lock.lock(); running = true; lock.unlock()
    }

    func pause() {
        lock.lock(); pauses += 1; running = false; lock.unlock()
    }

    func stop() {
        lock.lock(); stops += 1; running = false; lock.unlock()
    }

    /// The next `start()` blocks its thread until `resumeStart()`.
    func holdNextStart() { startGate.arm() }
    func waitUntilStartHeld(file: StaticString = #filePath, line: UInt = #line) async { await startGate.waitUntilHeld(file: file, line: line) }
    func resumeStart() { startGate.resume() }
}

/// Records every session call in order; one call name can be held (`holdNext`) or made to throw (`failNext`).
final class RecordingAudioSessionSeam: AudioSessionSeam, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [String] = []
    private var recordedMasks: [SessionMask] = []
    private var recordedEngines: [FakeEngineSeam] = []
    private var gates: [String: StepGate] = [:]
    private var failures: [String: Error] = [:]
    var engineFactory: () -> FakeEngineSeam = { FakeEngineSeam() }

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recordedCalls }
    var masks: [SessionMask] { lock.lock(); defer { lock.unlock() }; return recordedMasks }
    var engines: [FakeEngineSeam] { lock.lock(); defer { lock.unlock() }; return recordedEngines }
    var lastEngine: FakeEngineSeam? { lock.lock(); defer { lock.unlock() }; return recordedEngines.last }

    func clearCalls() {
        lock.lock(); recordedCalls = []; recordedMasks = []; lock.unlock()
    }

    /// The next call named `call` ("setCategory", "setActive(true)", "setActive(false, notify)", "setActive(false)") blocks
    /// on the controller's cycle queue until `resume()`.
    func holdNext(_ call: String) {
        gate(for: call).arm()
    }

    func waitUntilHeld(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !anyHeld {
            if Date() > deadline {
                lock.lock(); let all = Array(gates.values); lock.unlock()
                all.forEach { $0.disarm() }   // never leave an arming behind: a later step would block the bundle
                XCTFail("no session step was held", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func resume() {
        lock.lock()
        let held = gates.values.first { $0.isHeld }
        lock.unlock()
        held?.resume()
    }

    /// The next call named `call` throws `error` after being recorded.
    func failNext(_ call: String, with error: Error) {
        lock.lock(); failures[call] = error; lock.unlock()
    }

    private var anyHeld: Bool {
        lock.lock(); defer { lock.unlock() }
        return gates.values.contains { $0.isHeld }
    }

    private func gate(for call: String) -> StepGate {
        lock.lock(); defer { lock.unlock() }
        if let existing = gates[call] { return existing }
        let gate = StepGate()
        gates[call] = gate
        return gate
    }

    private func record(_ call: String, mask: SessionMask? = nil) throws {
        lock.lock()
        recordedCalls.append(call)
        if let mask { recordedMasks.append(mask) }
        let failure = failures.removeValue(forKey: call)
        let gate = gates[call]
        lock.unlock()
        gate?.pass()
        if let failure { throw failure }
    }

    func setCategory(_ mask: SessionMask) throws {
        try record("setCategory", mask: mask)
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        try record(active ? "setActive(true)" : (options.contains(.notifyOthersOnDeactivation) ? "setActive(false, notify)" : "setActive(false)"))
    }

    func makeEngine() -> any AudioEngineSeam {
        let engine = engineFactory()
        lock.lock(); recordedCalls.append("makeEngine"); recordedEngines.append(engine); lock.unlock()
        return engine
    }
}
