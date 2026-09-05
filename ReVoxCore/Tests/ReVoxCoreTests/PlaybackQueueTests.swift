import XCTest
@testable import ReVoxCore

/// Mirrors `tests/pipeline/test_playback.py` over a `FakePlaybackSink`.
final class PlaybackQueueTests: XCTestCase {
    private func makeQueue() -> (PlaybackQueue, FakePlaybackSink, LockedBox<[Bool]>) {
        let sink = FakePlaybackSink()
        let events = LockedBox<[Bool]>([])
        let queue = PlaybackQueue(sink: sink) { speaking in
            events.update { $0.append(speaking) }
        }
        return (queue, sink, events)
    }

    private func clip(_ count: Int) -> AudioClip {
        AudioClip(samples: [Float](repeating: 1, count: count), sampleRate: 24_000)
    }

    func testEnqueuePlaysAndTogglesSpeaking() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(clip(24_000))
        XCTAssertEqual(sink.scheduled.count, 1)
        XCTAssertEqual(sink.scheduled.map(\.samples.count).reduce(0, +), 24_000)
        XCTAssertEqual(events.value, [true])
        let speakingWhilePlaying = await queue.isSpeaking
        XCTAssertTrue(speakingWhilePlaying)
        sink.completeNext()
        let toggled = await eventually { events.value == [true, false] }
        XCTAssertTrue(toggled)
        let speakingAfter = await queue.isSpeaking
        XCTAssertFalse(speakingAfter)
        await queue.stop()
    }

    func testTwoClipsProduceOneSpeakingWindow() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(clip(100))
        await queue.enqueue(clip(100))
        XCTAssertEqual(events.value, [true])
        sink.completeNext()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(events.value, [true])                  // one clip still outstanding
        sink.completeNext()
        let toggled = await eventually { events.value == [true, false] }
        XCTAssertTrue(toggled)
    }

    func testEmptyClipsIgnored() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(AudioClip(samples: [], sampleRate: 24_000))
        XCTAssertTrue(sink.scheduled.isEmpty)
        let speaking = await queue.isSpeaking
        XCTAssertFalse(speaking)
        XCTAssertTrue(events.value.isEmpty)
        await queue.stop()
    }

    func testMuteDiscardsAudio() async {
        let (queue, sink, events) = makeQueue()
        await queue.setMuted(true)
        let muted = await queue.isMuted
        XCTAssertTrue(muted)
        await queue.enqueue(clip(24_000))
        XCTAssertTrue(sink.scheduled.isEmpty)                // discarded, never paused
        XCTAssertFalse(events.value.contains(true))
        let speaking = await queue.isSpeaking
        XCTAssertFalse(speaking)
        await queue.stop()
    }

    func testMuteMidClipStopsCurrentAndEndsSpeaking() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(clip(24_000))
        await queue.setMuted(true)
        XCTAssertEqual(sink.stopCount, 1)
        XCTAssertEqual(events.value, [true, false])
        await queue.setMuted(false)
        await queue.enqueue(clip(10))
        XCTAssertEqual(sink.scheduled.count, 2)
        XCTAssertEqual(events.value, [true, false, true])
        await queue.stop()
    }

    func testStopIdempotent() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(clip(10))
        await queue.stop()
        await queue.stop()
        XCTAssertTrue(sink.stopped)
        XCTAssertEqual(sink.stopCount, 1)
        XCTAssertEqual(events.value, [true, false])
        await queue.enqueue(clip(10))                        // ignored after stop
        XCTAssertEqual(sink.scheduled.count, 1)
    }

    /// The generation guard: a completion dispatched while the queue was muted must not close the speaking
    /// window opened by the clip enqueued after unmuting. Settles before asserting, unlike the mute test.
    func testStaleCompletionCannotCloseNewSpeakingWindow() async {
        let (queue, _, events) = makeQueue()
        await queue.enqueue(clip(10))
        await queue.setMuted(true)
        await queue.setMuted(false)
        await queue.enqueue(clip(10))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(events.value, [true, false, true])
        let speaking = await queue.isSpeaking
        XCTAssertTrue(speaking)
        await queue.stop()
    }

    /// The same guard against the ordering a real `AVAudioPlayerNode` produces: the stale completion is held
    /// by the sink and delivered only after the post-unmute clip has been scheduled.
    func testStaleCompletionAfterUnmuteDoesNotEndNewSpeakingWindow() async {
        let (queue, sink, events) = makeQueue()
        sink.deferCompletions = true
        await queue.enqueue(clip(24_000))
        await queue.setMuted(true)
        await queue.setMuted(false)
        await queue.enqueue(clip(10))
        XCTAssertEqual(events.value, [true, false, true])
        sink.fireOrphaned()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(events.value, [true, false, true])
        let speaking = await queue.isSpeaking
        XCTAssertTrue(speaking)
        await queue.stop()
    }

    /// `clear()` is a mute that does not stick: the queue is discarded and speaking ends, and the next clip plays.
    func testClearDiscardsOutstandingAndEndsSpeakingButKeepsPlaying() async {
        let (queue, sink, events) = makeQueue()
        await queue.enqueue(clip(100))
        await queue.enqueue(clip(100))
        await queue.clear()
        XCTAssertEqual(sink.stopCount, 1)
        XCTAssertEqual(events.value, [true, false])
        let speaking = await queue.isSpeaking
        XCTAssertFalse(speaking)
        let muted = await queue.isMuted
        XCTAssertFalse(muted)
        await queue.enqueue(clip(10))
        XCTAssertEqual(sink.scheduled.count, 3)
        XCTAssertEqual(events.value, [true, false, true])
        await queue.stop()
    }

    func testClearAndUnmuteWithNothingOutstandingTouchNothing() async {
        let (queue, sink, events) = makeQueue()
        await queue.clear()
        await queue.setMuted(false)
        XCTAssertEqual(sink.stopCount, 0)
        XCTAssertTrue(events.value.isEmpty)
        await queue.setMuted(true)                            // muted with nothing playing: no stop either
        XCTAssertEqual(sink.stopCount, 0)
        XCTAssertTrue(events.value.isEmpty)
        await queue.stop()
    }
}
