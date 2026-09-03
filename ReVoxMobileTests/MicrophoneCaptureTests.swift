import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

final class MicrophoneCaptureTests: XCTestCase {
    private func makeCapture(permission: MicrophonePermission) -> (MicrophoneCapture, RecordingAudioSessionSeam) {
        let seam = RecordingAudioSessionSeam()
        let controller = AudioSessionController(session: seam)
        return (MicrophoneCapture(controller: controller, permission: permission), seam)
    }

    func testDeniedPermissionThrowsWithoutTouchingTheEngine() async {
        let (capture, seam) = makeCapture(permission: .fixed(.denied))
        do {
            try await capture.start(.microphone)
            XCTFail("expected microphoneDenied")
        } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }
        XCTAssertEqual(seam.calls, [])
    }

    func testUndeterminedPermissionIsRequestedAndRefusalIsDenied() async {
        let (capture, _) = makeCapture(permission: .fixed(.undetermined, requestGrants: false))
        do {
            try await capture.start(.microphone)
            XCTFail("expected microphoneDenied")
        } catch {
            XCTAssertEqual(error as? CaptureError, .microphoneDenied)
        }
    }

    func testBroadcastModeIsRejectedByTheMicrophoneSource() async {
        let (capture, _) = makeCapture(permission: .fixed(.granted))
        do {
            try await capture.start(.broadcast)
            XCTFail("expected unsupportedMode")
        } catch {
            XCTAssertEqual(error as? CaptureError, .unsupportedMode(.broadcast))
        }
    }

    func testGrantedPermissionWithoutAConfiguredEngineIsEngineUnavailable() async {
        let (capture, _) = makeCapture(permission: .fixed(.granted))
        do {
            try await capture.start(.microphone)
            XCTFail("expected engineUnavailable")
        } catch {
            XCTAssertEqual(error as? CaptureError, .engineUnavailable)
        }
    }

    func testFramesReturnsAFreshStreamAndPositionsAccumulate() async {
        let (capture, _) = makeCapture(permission: .fixed(.granted))
        let first = capture.frames()
        capture.deliver([Float](repeating: 0.1, count: 480))
        capture.deliver([Float](repeating: 0.2, count: 1_120))
        var iterator = first.makeAsyncIterator()
        let a = await iterator.next()
        let b = await iterator.next()
        XCTAssertEqual(a?.samples.count, 480)
        XCTAssertEqual(a?.endPosition, 480)
        XCTAssertEqual(b?.endPosition, 1_600)
        let position = await capture.capturePosition()
        XCTAssertEqual(position, 1_600, "capturePosition equals the last endPosition in mic mode (§5.2)")

        let second = capture.frames()
        let finished = await iterator.next()
        XCTAssertNil(finished, "the previous stream finishes when frames() is called again")
        capture.deliver([Float](repeating: 0, count: 512))
        var secondIterator = second.makeAsyncIterator()
        let c = await secondIterator.next()
        XCTAssertEqual(c?.endPosition, 2_112)

        await capture.stop()
        let afterStop = await secondIterator.next()
        XCTAssertNil(afterStop, "stop() finishes the current stream")
    }

    func testEmptyDeliveriesAreIgnored() async {
        let (capture, _) = makeCapture(permission: .fixed(.granted))
        _ = capture.frames()
        capture.deliver([])
        let position = await capture.capturePosition()
        XCTAssertEqual(position, 0)
    }

    /// §6.1 / §6.8 / §9 "Route change → Rebuild tap/converter for device changes; ignore `.categoryChange`".
    /// The rebuild re-installs the tap on the new hardware format; the run-long capture counter must survive it,
    /// because the `CaptureGate` compares speaking edges with chunk positions on one continuous timeline (§5.2).
    func testRouteChangeRebuildsTheTapWithoutResettingThePosition() async {
        let (capture, _) = makeCapture(permission: .fixed(.granted))
        let stream = capture.frames()
        capture.deliver([Float](repeating: 0.1, count: 1_600))
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.endPosition, 1_600)

        capture.handleRouteChange(.categoryChange)
        XCTAssertEqual(capture.routeRebuildCount, 0, "a category change never touches the tap")
        capture.handleRouteChange(.routeConfigurationChange)
        XCTAssertEqual(capture.routeRebuildCount, 0)

        capture.handleRouteChange(.oldDeviceUnavailable)
        XCTAssertEqual(capture.routeRebuildCount, 1, "the headset was unplugged: remove and re-install the tap")
        capture.handleRouteChange(.newDeviceAvailable)
        XCTAssertEqual(capture.routeRebuildCount, 2)

        // The stream survives the rebuild and the counter carries on from where it was.
        let position = await capture.capturePosition()
        XCTAssertEqual(position, 1_600, "the capture counter is not reset by a rebuild")
        capture.deliver([Float](repeating: 0.2, count: 512))
        let second = await iterator.next()
        XCTAssertEqual(second?.endPosition, 2_112)

        await capture.stop()
    }

    /// §6.1: "if the input becomes unavailable the pipeline continues with silence and the status line shows
    /// 'No microphone input'". Right after `.oldDeviceUnavailable` the input node's sample rate is often still 0,
    /// so the rebuild retries; only when the retries are exhausted does the status line appear, and a later
    /// rebuild that finds an input clears it again. The `TapSeam` keeps the whole path off hardware.
    func testRebuildWithoutAnInputRetriesThenReportsTheStatusUntilTheInputReturns() async throws {
        let engine = AVAudioEngine()
        let seam = RecordingAudioSessionSeam()
        seam.engineFactory = {
            let fake = FakeEngineSeam()
            fake.engine = engine
            return fake
        }
        let controller = AudioSessionController(session: seam)
        try await controller.configure(for: .microphone)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let probe = TapProbe(format: format)
        let statuses = StatusRecorder()
        let capture = MicrophoneCapture(controller: controller, permission: .fixed(.granted),
                                        tap: probe.seam(), onStatus: { statuses.record($0) })
        _ = capture.frames()
        try await capture.start(.microphone)
        XCTAssertEqual(probe.formatCalls, 1)
        XCTAssertEqual(probe.installCount, 1)
        XCTAssertEqual(statuses.all, [], "a healthy tap says nothing")

        probe.inputAvailable = false
        capture.handleRouteChange(.oldDeviceUnavailable)
        await waitUntil("the status line reports the missing input", timeout: 5) { statuses.all.count == 1 }
        XCTAssertEqual(probe.formatCalls, 1 + MicrophoneCapture.rebuildRetryLimit,
                       "three attempts \(MicrophoneCapture.rebuildRetryDelay)s apart, then the report")
        XCTAssertEqual(probe.installCount, 1, "no tap is installed while the input is gone")
        XCTAssertEqual(statuses.all, ["No microphone input"])
        XCTAssertEqual(statuses.all.first ?? nil, CaptureError.noInput.description)

        probe.inputAvailable = true
        capture.handleRouteChange(.newDeviceAvailable)
        await waitUntil("the status line clears", timeout: 5) { statuses.all.count == 2 }
        XCTAssertEqual(statuses.all, ["No microphone input", nil])
        XCTAssertEqual(probe.installCount, 2, "the tap is back on the new route")
        XCTAssertEqual(capture.routeRebuildCount, 2)

        // The run-long counter is untouched by either rebuild (§5.2).
        capture.deliver([Float](repeating: 0.1, count: 512))
        let position = await capture.capturePosition()
        XCTAssertEqual(position, 512)

        await capture.stop()
    }
}

/// A `TapSeam` whose input can be switched off, so the `.noInput` rebuild branch runs without hardware.
final class TapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let format: AVAudioFormat
    private var available = true
    private var formats = 0
    private var installs = 0
    private var removals = 0

    init(format: AVAudioFormat) {
        self.format = format
    }

    var inputAvailable: Bool {
        get { lock.lock(); defer { lock.unlock() }; return available }
        set { lock.lock(); available = newValue; lock.unlock() }
    }

    var formatCalls: Int { lock.lock(); defer { lock.unlock() }; return formats }
    var installCount: Int { lock.lock(); defer { lock.unlock() }; return installs }
    var removeCount: Int { lock.lock(); defer { lock.unlock() }; return removals }

    func seam() -> TapSeam {
        TapSeam(
            inputFormat: { [self] _ in
                lock.lock()
                formats += 1
                let ok = available
                lock.unlock()
                return ok ? format : nil
            },
            install: { [self] _, _, _, _ in lock.lock(); installs += 1; lock.unlock() },
            remove: { [self] _ in lock.lock(); removals += 1; lock.unlock() }
        )
    }
}

/// Lock-guarded recorder for the capture status line, which is published from the rebuild queue.
final class StatusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []
    func record(_ status: String?) { lock.lock(); values.append(status); lock.unlock() }
    var all: [String?] { lock.lock(); defer { lock.unlock() }; return values }
}
