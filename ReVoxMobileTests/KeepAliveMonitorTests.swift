import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class KeepAliveMonitorTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(KeepAliveMonitor.intervalNanoseconds, 1_000_000_000)
        XCTAssertEqual(KeepAliveMonitor.gapThresholdSeconds, 3)
        XCTAssertEqual(KeepAliveMonitor.logRingCapacity, 3_600)
    }

    func testGapIsReportedOnlyAboveThreeSeconds() {
        let now = LockedBox<Double>(1_000)
        let monitor = KeepAliveMonitor(clock: { now.value })
        XCTAssertEqual(monitor.record(position: 0), .heartbeat(.init(position: 0, at: 1_000)))
        now.mutate { $0 = 1_001 }
        XCTAssertEqual(monitor.record(position: 16_000), .heartbeat(.init(position: 16_000, at: 1_001)))
        now.mutate { $0 = 1_004 }
        XCTAssertEqual(monitor.record(position: 32_000), .heartbeat(.init(position: 32_000, at: 1_004)), "exactly 3 s is not a gap")
        now.mutate { $0 = 1_008.5 }
        let event = monitor.record(position: 40_000)
        XCTAssertEqual(event, .gap(seconds: 4.5, before: .init(position: 32_000, at: 1_004), after: .init(position: 40_000, at: 1_008.5)))
        XCTAssertEqual(monitor.gapCount, 1)
        XCTAssertEqual(monitor.lastHeartbeat, .init(position: 40_000, at: 1_008.5))
        XCTAssertEqual(monitor.heartbeats.count, 4)
    }

    func testLogRingKeepsTheNewestCapacityEntriesAndAppendsToTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keepalive-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let now = LockedBox<Double>(0)
        let monitor = KeepAliveMonitor(clock: { now.value }, logURL: url)
        for tick in 0 ..< (KeepAliveMonitor.logRingCapacity + 5) {
            now.mutate { $0 = Double(tick) }
            _ = monitor.record(position: Int64(tick) * 16_000)
        }
        XCTAssertEqual(monitor.heartbeats.count, KeepAliveMonitor.logRingCapacity)
        XCTAssertEqual(monitor.heartbeats.first?.position, 5 * 16_000)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, KeepAliveMonitor.logRingCapacity + 5)
        XCTAssertEqual(lines.first, "heartbeat position=0 at=0.000")
        XCTAssertTrue(lines.last?.hasPrefix("heartbeat position=\(3_604 * 16_000)") ?? false)
    }

    func testStartTicksAtTheIntervalAndOnGapCallsTheHandler() async {
        let now = LockedBox<Double>(100)
        let monitor = KeepAliveMonitor(clock: { now.value }, interval: 20_000_000)   // 20 ms ticks for the test
        let gaps = LockedBox<[Double]>([])
        let position = LockedBox<Int64>(0)
        monitor.start(position: { position.value }, onGap: { seconds in gaps.mutate { $0.append(seconds) } })
        var iterator = monitor.events.makeAsyncIterator()
        let first = await iterator.next()
        if case .heartbeat(let beat)? = first {
            XCTAssertEqual(beat.at, 100)
        } else {
            XCTFail("expected a heartbeat, got \(String(describing: first))")
        }
        position.mutate { $0 = 512 }
        now.mutate { $0 = 110 }             // the wall clock jumped 10 s between two ticks: the app was suspended
        var sawGap = false
        for _ in 0 ..< 5 {
            if case .gap(let seconds, _, _)? = await iterator.next() {
                XCTAssertEqual(seconds, 10, accuracy: 0.5)
                sawGap = true
                break
            }
        }
        XCTAssertTrue(sawGap)
        await waitFor("the gap to reach the handler") { gaps.value.count == 1 }
        XCTAssertEqual(gaps.value.count, 1)
        monitor.stop()
        monitor.stop()
        let countAfterStop = monitor.heartbeats.count
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(monitor.heartbeats.count, countAfterStop, "no ticks after stop")
        monitor.reset()
        XCTAssertNil(monitor.lastHeartbeat)
        XCTAssertEqual(monitor.gapCount, 0)
    }

    func testMonitoredPipelineStartsAndStopsTheMonitorAndForwardsGapsAsDropMarkers() async {
        let fake = FakeLivePipeline()
        let now = LockedBox<Double>(0)
        let monitor = KeepAliveMonitor(clock: { now.value }, interval: 20_000_000)
        let position = LockedBox<Int64>(0)
        let pipeline = MonitoredPipeline(pipeline: fake, monitor: monitor, position: { position.value })
        await pipeline.start(PipelineConfiguration(captureMode: .microphone, preset: .balanced, pinnedLanguage: nil))
        XCTAssertEqual(fake.startedWith.count, 1)
        await waitFor("the first heartbeat") { monitor.heartbeats.count >= 1 }
        now.mutate { $0 = 30 }
        await waitFor("the gap to become a drop marker on the pipeline") { fake.gapCount == 1 }
        XCTAssertEqual(fake.gapCount, 1, "the gap became a drop marker on the pipeline")
        await pipeline.setMuted(true)
        await pipeline.stop()
        XCTAssertEqual(fake.stopCount, 1)
        XCTAssertEqual(fake.muted, [true])
        let count = monitor.heartbeats.count
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(monitor.heartbeats.count, count, "stop() stops the ticks")
        await pipeline.noteCaptureGap()
        XCTAssertEqual(fake.gapCount, 2)
    }
}
