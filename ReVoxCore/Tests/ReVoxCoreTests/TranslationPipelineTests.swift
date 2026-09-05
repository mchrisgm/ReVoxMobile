import Dispatch
import XCTest
@testable import ReVoxCore

/// Mirrors `tests/pipeline/test_pipeline.py` plus the R9/R12 cases. Every test uses `FakeSegmenter` (every fed
/// 512-sample chunk is one segment) unless it asks for the real `Segmenter` over `EnergyVAD`.
final class TranslationPipelineTests: XCTestCase {
    private struct Harness {
        let pipeline: TranslationPipeline
        let source: FakeAudioSource
        let vad: EnergyVAD
        let translator: FakeTranslator
        let speaker: FakeSpeaker
        let ducker: FakeDucker
        let transcript: FakeTranscriptSink
        let sleep: FakeSleep
        let players: LockedBox<[FakePlayer]>
        let events: EventCollector

        var player: FakePlayer? { players.value.first }
    }

    /// The capture source must be started before the player.
    ///
    /// On iOS the source's `start` installs the tap on the audio engine's input node and the player's `start`
    /// starts that engine. An engine started with no tap on its input never pulls the microphone, and installing
    /// the tap afterwards does not make it start — the app shipped in build 8 recorded silence for exactly this
    /// reason. The order is a contract of the pipeline, not an accident of the adapters.
    func testSourceIsStartedBeforeThePlayerSoTheTapPrecedesTheEngine() async {
        let order = StartOrderLog()
        let source = FakeAudioSource()
        source.startOrder = order
        let players = LockedBox<[FakePlayer]>([])
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: FakeTranslator(),
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in
                let player = FakePlayer(onSpeaking: onSpeaking, startOrder: order)
                players.update { $0.append(player) }
                return player
            },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        let pipeline = TranslationPipeline(dependencies: dependencies)

        await pipeline.start(PipelineConfiguration(captureMode: .microphone, preset: .balanced))
        defer { Task { await pipeline.stop() } }

        XCTAssertEqual(order.recorded, ["source", "player"],
                       "the tap must be installed before the engine is started")
    }

    private func makeHarness(translator: FakeTranslator = FakeTranslator(), realSegmenter: Bool = false,
                             transcriber: (any Transcriber)? = nil, secondary: (any SecondaryTranslator)? = nil,
                             speaker: FakeSpeaker = FakeSpeaker(), vad: EnergyVAD = EnergyVAD()) -> Harness {
        let source = FakeAudioSource()
        let ducker = FakeDucker()
        let transcript = FakeTranscriptSink()
        let sleep = FakeSleep()
        let players = LockedBox<[FakePlayer]>([])
        var dependencies = PipelineDependencies(
            source: source, vad: vad, detector: FakeLanguageDetector(), translator: translator, speaker: speaker,
            transcriber: transcriber,
            secondaryTranslator: secondary,
            playerFactory: { _, onSpeaking in
                let player = FakePlayer(onSpeaking: onSpeaking)
                players.update { $0.append(player) }
                return player
            },
            ducker: ducker,
            transcriptFactory: { transcript },
            clock: FakeClock().now,
            sleep: sleep.sleep)
        if !realSegmenter {
            dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)
        return Harness(pipeline: pipeline, source: source, vad: vad, translator: translator, speaker: speaker,
                       ducker: ducker, transcript: transcript, sleep: sleep, players: players, events: events)
    }

    private func configuration(_ mode: CaptureMode = .microphone, maxPending: Int = 3) -> PipelineConfiguration {
        PipelineConfiguration(captureMode: mode, preset: .balanced, maxPending: maxPending)
    }

    /// The Windows `segment()`: 1 600 ones (three 512-sample chunks after re-framing).
    private func segment() -> [Float] {
        [Float](repeating: 1, count: 1600)
    }

    func testHappyPathTranslatesAndSpeaks() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        let state = await h.pipeline.state
        XCTAssertEqual(state, .running)
        XCTAssertEqual(h.source.started, [.microphone])
        h.source.feed(segment())
        let spoke = await eventually { await h.player?.enqueued.isEmpty == false }
        XCTAssertTrue(spoke)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.english, "text-1")
        XCTAssertEqual(entries.first?.language, "es")
        XCTAssertEqual(entries.first?.original, "")
        XCTAssertEqual(entries.first?.isGuess, false)
        let entryEmitted = await eventually { h.events.hasEntry }
        XCTAssertTrue(entryEmitted)
        let spokenTexts = await h.speaker.texts
        XCTAssertEqual(spokenTexts.first, "text-1")
        await h.pipeline.stop()
        let finalState = await h.pipeline.state
        XCTAssertEqual(finalState, .idle)
        let idleEmitted = await eventually { h.events.states == [.running, .idle] }
        XCTAssertTrue(idleEmitted, "\(h.events.states)")
    }

    func testBackpressureDropsOldestAndReportsLag() async throws {
        let translator = FakeTranslator(blocked: true)
        let h = makeHarness(translator: translator)
        await h.pipeline.start(configuration(maxPending: 2))
        // One 512-sample chunk per feed, so `FakeSegmenter` makes exactly six segments — the six the spec's
        // count analysis assumes. Feeding 1 600 samples would re-frame into three chunks and give eighteen.
        for _ in 0 ..< 6 {
            h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        }
        let lagged = await eventually { h.events.hasLag }
        XCTAssertTrue(lagged)
        let dropped = await eventually { await h.transcript.drops >= 1 }
        XCTAssertTrue(dropped)                                              // the Windows assertion
        // Capacity 2 and at most one popped segment mean six pushes always drop 3 or 4. Waiting for the third
        // drop leaves at most one push still in flight when the gate opens, which is what keeps `calls <= 4`
        // sound on a loaded CI runner; opening after the first drop lets late pushes be translated too.
        let allPushesLanded = await eventually { await h.transcript.drops >= 3 }
        XCTAssertTrue(allPushesLanded)
        await translator.openGate()
        let translated = await eventually { await translator.calls.count >= 1 }
        XCTAssertTrue(translated)
        await h.pipeline.stop()
        // far fewer translations than fed segments: the rest were dropped
        let calls = await translator.calls.count
        XCTAssertLessThanOrEqual(calls, 4)
        let drops = await h.transcript.drops
        // `EventCollector` drains the stream on its own task, so read it through `eventually`, never directly.
        let lagsMatchDrops = await eventually { h.events.events.filter { $0 == .lag }.count == drops }
        XCTAssertTrue(lagsMatchDrops)                                       // one .lag per drop marker
    }

    func testSpeakingTransitionsDriveDucking() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration(.microphone))
        let player = try XCTUnwrap(h.player)
        player.onSpeaking(true)
        let ducked = await eventually { await h.ducker.ducked == 1 }
        XCTAssertTrue(ducked)
        player.onSpeaking(false)
        let holding = await eventually { h.sleep.pendingCount == 1 }
        XCTAssertTrue(holding)
        let restoredEarly = await h.ducker.restored
        XCTAssertEqual(restoredEarly, 0)                      // W5: not before the hold
        h.sleep.resumeAll()
        let restored = await eventually { await h.ducker.restored == 1 }
        XCTAssertTrue(restored)
        let edges = await eventually { h.events.speakingEdges == [true, false] }
        XCTAssertTrue(edges, "\(h.events.speakingEdges)")
        await h.pipeline.stop()
    }

    func testBothModesDuck() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration(.broadcast))
        let player = try XCTUnwrap(h.player)
        player.onSpeaking(true)
        let ducked = await eventually { await h.ducker.ducked == 1 }
        XCTAssertTrue(ducked)                                 // W6: no target pid; everything else is ducked
        await h.pipeline.stop()
    }

    func testMuteForwardsToPlayerAndRestoresDucking() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        await h.pipeline.setMuted(true)
        let muted = await h.player?.muted
        XCTAssertEqual(muted, true)
        let isMuted = await h.pipeline.isMuted
        XCTAssertTrue(isMuted)
        let restored = await h.ducker.restored
        XCTAssertEqual(restored, 1)                           // forwarded even though nothing was ducked
        await h.pipeline.setMuted(false)
        let unmuted = await h.player?.muted
        XCTAssertEqual(unmuted, false)
        await h.pipeline.stop()
    }

    func testTranslatorErrorEmitsErrorState() async throws {
        let h = makeHarness(translator: FakeTranslator(fail: true))
        await h.pipeline.start(configuration())
        h.source.feed(segment())
        let failed = await eventually { h.events.hasError }
        XCTAssertTrue(failed)
        let state = await h.pipeline.state
        XCTAssertEqual(state, .error)
        await h.pipeline.stop()
        let finalState = await h.pipeline.state
        XCTAssertEqual(finalState, .idle)                     // stop() from error goes to idle
    }

    func testStopCleansUpAndIsIdempotent() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        let player = try XCTUnwrap(h.player)
        await h.pipeline.stop()
        await h.pipeline.stop()                               // idempotent
        XCTAssertTrue(h.source.stopped)
        let stopped = await player.stopped
        XCTAssertTrue(stopped)
        let closed = await h.transcript.closed
        XCTAssertTrue(closed)
        let restored = await h.ducker.restored
        XCTAssertGreaterThanOrEqual(restored, 1)
        // `stop()` yields `.state(.idle)`; the collector task appends it a moment later, so fence the read.
        let settled = await eventually { h.events.states == [.running, .idle] }
        XCTAssertTrue(settled, "\(h.events.states)")          // exactly one .idle, and it is the last state
    }

    func testSpeakingClosesCaptureGateFor300ms() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration(.broadcast))
        let player = try XCTUnwrap(h.player)
        let chunk = Segmenter.chunkSamples

        h.source.feed([Float](repeating: 0.1, count: chunk), endingAt: 5_000)           // before ReVox speaks: passes
        let first = await eventually { await h.translator.calls.count == 1 }
        XCTAssertTrue(first)

        h.source.setCapturePosition(10_000)
        player.onSpeaking(true)
        let closed = await eventually { h.events.speakingEdges == [true] }
        XCTAssertTrue(closed)
        h.source.feed([Float](repeating: 0.25, count: chunk), endingAt: 10_512)         // ReVox's own voice: dropped

        h.source.setCapturePosition(20_000)
        player.onSpeaking(false)                                                        // hold until 24 800
        let opened = await eventually { h.events.speakingEdges == [true, false] }
        XCTAssertTrue(opened)
        h.source.feed([Float](repeating: 0.5, count: chunk), endingAt: 24_000)          // inside the 300 ms hold: dropped
        h.source.feed([Float](repeating: 0.75, count: chunk), endingAt: 24_800)         // first chunk after the hold: passes

        let second = await eventually { await h.translator.calls.count == 2 }
        XCTAssertTrue(second)
        let calls = await h.translator.calls
        XCTAssertEqual(calls[0].first, 0.1)
        XCTAssertEqual(calls[1].first, 0.75)
        await h.pipeline.stop()
        let finalCalls = await h.translator.calls.count
        XCTAssertEqual(finalCalls, 2)
    }

    func testSpeakingEdgesApplyInOrder() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        let player = try XCTUnwrap(h.player)
        h.source.setCapturePosition(10_000)
        for index in 0 ..< 50 {
            player.onSpeaking(index % 2 == 0)                 // 25 true/false pairs, back to back
        }
        let drained = await eventually { h.events.speakingEdges.count == 50 }
        XCTAssertTrue(drained)
        XCTAssertEqual(h.events.speakingEdges, (0 ..< 50).map { $0 % 2 == 0 })   // strictly alternating
        let ducked = await h.ducker.ducked
        XCTAssertEqual(ducked, 1)                             // re-triggers inside the hold never re-duck
        let lastHold = await eventually { h.sleep.pendingCount == 1 && h.sleep.requested.count == 25 }
        XCTAssertTrue(lastHold)
        h.sleep.resumeAll()
        let restored = await eventually { await h.ducker.restored == 1 }
        XCTAssertTrue(restored)                               // ducking restored after the fake hold
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples), endingAt: 20_000)   // beyond 14 800: gate open
        let translated = await eventually { await h.translator.calls.count == 1 }
        XCTAssertTrue(translated)
        await h.pipeline.stop()
    }

    func testStopDoesNotFlushPartialPhrase() async throws {
        let h = makeHarness(realSegmenter: true)
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: 16_000 * 800 / 1000))               // 800 ms of speech, no silence
        let scored = await eventually { await h.vad.callCount == 25 }
        XCTAssertTrue(scored)
        await h.pipeline.stop()
        let calls = await h.translator.calls
        XCTAssertTrue(calls.isEmpty)
        let entries = await h.transcript.entries
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(h.events.hasEntry)
    }

    func testNoteCaptureGapEmitsLagAndMarker() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration(.broadcast))
        await h.pipeline.noteCaptureGap()
        let lagged = await eventually { h.events.hasLag }
        XCTAssertTrue(lagged)
        let drops = await h.transcript.drops
        XCTAssertEqual(drops, 1)
        let calls = await h.translator.calls
        XCTAssertTrue(calls.isEmpty)                          // no segment was dropped
        await h.pipeline.stop()
    }

    func testStartResetsSegmenterAndVADOnce() async throws {
        let h = makeHarness(realSegmenter: true)
        await h.pipeline.start(configuration())
        let afterStart = await h.vad.resetCount
        XCTAssertEqual(afterStart, 1)
        let phrase = [Float](repeating: 0.5, count: 32 * Segmenter.chunkSamples) + [Float](repeating: 0, count: 15 * Segmenter.chunkSamples)
        h.source.feed(phrase)
        h.source.feed(phrase)
        let translated = await eventually { await h.translator.calls.count == 2 }
        XCTAssertTrue(translated)
        let afterPhrases = await h.vad.resetCount
        XCTAssertEqual(afterPhrases, 1)
        await h.pipeline.stop()
        await h.pipeline.start(configuration())
        let afterRestart = await h.vad.resetCount
        XCTAssertEqual(afterRestart, 2)                       // exactly one reset per start
        await h.pipeline.stop()
    }

    func testRestartAfterStopReadsFreshStream() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        h.source.feed(segment())
        let firstRun = await eventually { await h.translator.calls.count == 3 }
        XCTAssertTrue(firstRun)
        await h.pipeline.stop()
        await h.pipeline.start(configuration())
        XCTAssertEqual(h.source.framesCalls, 2)
        XCTAssertEqual(h.players.value.count, 2)
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let secondRun = await eventually { await h.translator.calls.count == 4 }
        XCTAssertTrue(secondRun)
        await h.pipeline.stop()
        let states = await eventually { h.events.states == [.running, .idle, .running, .idle] }
        XCTAssertTrue(states, "\(h.events.states)")
    }

    func testStartWhileRunningIsNoOp() async throws {
        let h = makeHarness()
        await h.pipeline.start(configuration())
        await h.pipeline.start(configuration())
        XCTAssertEqual(h.source.framesCalls, 1)
        let oneRunningEvent = await eventually { h.events.states == [.running] }
        XCTAssertTrue(oneRunningEvent, "\(h.events.states)")
        await h.pipeline.stop()
    }

    /// A translator whose first call takes 3 s and cannot be shortened by cancellation — the shape of an M3
    /// `WhisperKit.transcribe` prediction on medium/large, which routinely outlives the 2 s bounded join of
    /// `stop()`. Later calls return immediately.
    ///
    /// The delay must be a `withCheckedContinuation` resumed off a `DispatchQueue` timer, **not**
    /// `try? await Task.sleep(nanoseconds:)`: `Task.sleep` throws `CancellationError` the moment the task is
    /// cancelled and `try?` only swallows that error, so the sleep would return early on `stop()`'s
    /// `task.cancel()` and the test would pass even against the unguarded pipeline. A non-throwing checked
    /// continuation with no cancellation handler ignores cancellation, exactly like a synchronous model call.
    private actor SlowFirstCallTranslator: Translator {
        private(set) var calls = 0
        private let throwOnFirstCall: Bool

        /// `throwOnFirstCall` makes the first call throw once its 3 s delay is over — the §9 "Whisper failure
        /// mid-run" case arriving after `stop()` has already returned from its bounded join.
        init(throwOnFirstCall: Bool = false) {
            self.throwOnFirstCall = throwOnFirstCall
        }

        func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate {
            calls += 1
            let index = calls
            if index == 1 {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                if throwOnFirstCall {
                    throw FakeTranslatorError()
                }
            }
            return TranslationCandidate(
                language: "es",
                languageProbability: nil,
                segments: [TranslationSegment(text: "text-\(index)", noSpeechProbability: 0, averageLogProbability: 0)])
        }
    }

    private struct StragglerHarness {
        let pipeline: TranslationPipeline
        let source: FakeAudioSource
        let translator: SlowFirstCallTranslator
        let sinks: LockedBox<[FakeTranscriptSink]>
        let events: EventCollector
    }

    /// The harness of both generation-token tests: a `SlowFirstCallTranslator` whose first call outlives the 2 s
    /// join of `stop()`, one `FakeTranscriptSink` recorded per run, and an `EventCollector` draining the stream.
    private func makeStragglerHarness(throwOnFirstCall: Bool = false) -> StragglerHarness {
        let source = FakeAudioSource()
        let translator = SlowFirstCallTranslator(throwOnFirstCall: throwOnFirstCall)
        let sinks = LockedBox<[FakeTranscriptSink]>([])
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: translator,
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in FakePlayer(onSpeaking: onSpeaking) },
            ducker: FakeDucker(),
            transcriptFactory: {
                let sink = FakeTranscriptSink()
                sinks.update { $0.append(sink) }
                return sink
            },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)
        return StragglerHarness(pipeline: pipeline, source: source, translator: translator, sinks: sinks, events: events)
    }

    /// R12 restart contract: `stop()` abandons a stage task that outlives its 2 s join, so the abandoned task must
    /// be fenced out of the *next* run. Without the per-run generation token of `PipelineActor`, run 1's straggling
    /// translation lands in run 2's `TranscriptSink`, emits an `.entry` event and is spoken during run 2 — the
    /// previous session's audio transcribed into and spoken over the new one, because `LiveViewModel` reuses one
    /// cached pipeline across restarts (§10.1 `test_pipeline_cached_across_restarts`).
    func testStragglerFromTheStoppedRunNeverTouchesTheNextRun() async throws {
        let h = makeStragglerHarness()
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let entered = await eventually { await h.translator.calls == 1 }
        XCTAssertTrue(entered)                                   // run 1 is inside the 3 s translator call
        await h.pipeline.stop()                                  // returns after the 2 s join, straggler still running
        await h.pipeline.start(configuration())                  // run 2 begins while run 1's translate is in flight
        XCTAssertEqual(h.sinks.value.count, 2)                   // one sink per run

        // Poll past the straggler's 3 s sleep. The window runs to completion and yields `false` when the run token
        // fenced it out; it returns early only if run 1's translation leaked into run 2.
        let leaked = await eventually(timeout: 3.5) { await h.sinks.value[1].entries.isEmpty == false }
        XCTAssertFalse(leaked)
        let secondRunEntries = await h.sinks.value[1].entries
        XCTAssertTrue(secondRunEntries.isEmpty)                  // nothing from run 1 in run 2's transcript
        let state = await h.pipeline.state
        XCTAssertEqual(state, .running)                          // and no straggler drove run 2 to .error
        await h.pipeline.stop()
    }

    /// R12 idle window: the same abandoned stage task, but the pipeline is never re-started and the straggling
    /// translation *throws* when it finally returns (spec §9, "Whisper failure mid-run: `transcribe` throws" —
    /// the stages only special-case `CancellationError`, and this is not one). Unless `stop()` retired the run's
    /// generation, `fail(_:run:)` still matches and writes `.error` + an `.error` event into a pipeline the user
    /// already stopped, so §8.2 shows the "Try again" banner over an idle session until the next `start`.
    func testStragglerErrorAfterStopDoesNotErrorTheIdlePipeline() async throws {
        let h = makeStragglerHarness(throwOnFirstCall: true)
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let entered = await eventually { await h.translator.calls == 1 }
        XCTAssertTrue(entered)                                   // run 1 is inside the 3 s translator call
        await h.pipeline.stop()                                  // returns after the 2 s join; no restart
        let state = await h.pipeline.state
        XCTAssertEqual(state, .idle)

        // Poll past the straggler's 3 s sleep and the throw that follows it. The window runs to completion and
        // yields `false` when the run was retired; it returns early only if the throw reached `fail`.
        let errored = await eventually(timeout: 3.5) { h.events.hasError }
        XCTAssertFalse(errored)                                  // the straggler's throw is fenced out
        let finalState = await h.pipeline.state
        XCTAssertEqual(finalState, .idle)
        // `EventCollector` drains the stream on its own task, so read it through `eventually`, never directly.
        let settled = await eventually { h.events.states == [.running, .idle] }
        XCTAssertTrue(settled, "\(h.events.states)")             // the session still ended cleanly
        let entries = await h.sinks.value[0].entries
        XCTAssertTrue(entries.isEmpty)                           // and nothing was transcribed after the stop
    }

    // MARK: start/stop overlap (actor reentrancy)

    /// An `AudioPlayer` whose `start()` can be held open, so a test can run `stop()` while the pipeline's `start()` is
    /// suspended inside it. Only the first player a factory builds is gated; later ones start at once.
    private actor GatedPlayer: AudioPlayer {
        nonisolated let onSpeaking: SpeakingCallback
        private let gated: Bool
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var startEntered = false
        private(set) var stopped = false

        init(onSpeaking: @escaping SpeakingCallback, gated: Bool) {
            self.onSpeaking = onSpeaking
            self.gated = gated
        }

        func start() async throws {
            startEntered = true
            guard gated, !released else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            released = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }

        func enqueue(_ clip: AudioClip) async {}
        func setMuted(_ muted: Bool) async {}
        func clear() async {}
        func stop() async { stopped = true }
        var isSpeaking: Bool { get async { false } }
    }

    /// `PipelineActor` is re-entrant at every `await` inside `start()`. A `stop()` that lands while `start()` is
    /// suspended in `player.start()` used to retire the run, finish the wake/text/edge streams and stop the player —
    /// and then the resumed `start()` set `running = true` and reported `.running` over a run whose streams were
    /// already finished. `start()` is a no-op while running, so nothing could bring the pipeline back except a
    /// second `stop()`. The two must be serialised in call order: the start completes, then the stop tears it down.
    func testStopDuringStartWinsAndTheNextStartWorks() async throws {
        let source = FakeAudioSource()
        let translator = FakeTranslator()
        let players = LockedBox<[GatedPlayer]>([])
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: translator,
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in
                let player = players.update { existing -> GatedPlayer in
                    let player = GatedPlayer(onSpeaking: onSpeaking, gated: existing.isEmpty)
                    existing.append(player)
                    return player
                }
                return player
            },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)

        let starting = Task { await pipeline.start(self.configuration()) }
        let entered = await eventually { await players.value.first?.startEntered == true }
        XCTAssertTrue(entered)                                   // start() is suspended inside player.start()
        let stopping = Task { await pipeline.stop() }
        try await Task.sleep(nanoseconds: 50_000_000)            // give stop() every chance to interleave
        await players.value[0].release()
        await starting.value
        await stopping.value

        let state = await pipeline.state
        XCTAssertEqual(state, .idle, "the stop that followed the start must win")
        XCTAssertTrue(source.stopped)
        let firstPlayerStopped = await players.value[0].stopped
        XCTAssertTrue(firstPlayerStopped)

        await pipeline.start(configuration())                    // and the pipeline is not stuck: it starts again
        let restarted = await pipeline.state
        XCTAssertEqual(restarted, .running)
        XCTAssertEqual(source.framesCalls, 2)
        XCTAssertEqual(players.value.count, 2)
        source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let translated = await eventually { await translator.calls.count == 1 }
        XCTAssertTrue(translated)
        await pipeline.stop()
        let settled = await eventually { events.states == [.running, .idle, .running, .idle] }
        XCTAssertTrue(settled, "\(events.states)")
    }

    // MARK: a speaking edge that outlives its run

    /// An `AudioSource` over `FakeAudioSource` whose `capturePosition()` can be held open, so a speaking edge of one
    /// run is still suspended there when that run is stopped and the next one starts. Every stored property is
    /// guarded by one `NSLock`, taken only in the synchronous helpers.
    private final class HoldablePositionSource: AudioSource, @unchecked Sendable {
        let inner = FakeAudioSource()
        private let lock = NSLock()
        private var holding = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var held = 0
        private var reads = 0

        var heldCount: Int { lock.lock(); defer { lock.unlock() }; return held }
        var positionReads: Int { lock.lock(); defer { lock.unlock() }; return reads }

        func frames() -> AsyncStream<CapturedAudio> { inner.frames() }

        func capturePosition() async -> Int64 {
            lock.lock()
            let shouldHold = holding
            lock.unlock()
            if shouldHold {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    waiters.append(continuation)
                    held += 1
                    lock.unlock()
                }
            }
            let position = await inner.capturePosition()
            lock.lock()
            reads += 1
            lock.unlock()
            return position
        }

        func start(_ mode: CaptureMode) async throws { try await inner.start(mode) }
        func stop() async { await inner.stop() }

        func hold() { lock.lock(); holding = true; lock.unlock() }

        func release() {
            lock.lock()
            holding = false
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            for waiter in pending { waiter.resume() }
        }
    }

    /// `applySpeakingEdge` checks the run token, then suspends on `source.capturePosition()`. If the run is stopped
    /// and a new one started while it is suspended (`stop()`'s join is bounded), the edge used to resume and close
    /// the **new** run's capture gate from the old player's speaking edge — every chunk of the new run at or past
    /// that position was dropped before the VAD, so the fresh session heard nothing — and leak a stale `.speaking`
    /// event into it. The token must be re-checked after the await, like every other hand-off.
    func testASpeakingEdgeStillInFlightWhenItsRunEndsDoesNotCloseTheNextRunsGate() async throws {
        let source = HoldablePositionSource()
        let translator = FakeTranslator()
        let ducker = FakeDucker()
        let players = LockedBox<[FakePlayer]>([])
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: translator,
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in
                let player = FakePlayer(onSpeaking: onSpeaking)
                players.update { $0.append(player) }
                return player
            },
            ducker: ducker,
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)

        await pipeline.start(configuration())
        source.hold()
        players.value[0].onSpeaking(true)                        // run 1's player starts speaking
        let held = await eventually { source.heldCount == 1 }
        XCTAssertTrue(held)                                      // the edge is suspended in capturePosition()
        await pipeline.stop()                                    // bounded join: the edge task is abandoned
        await pipeline.start(configuration())                    // run 2
        source.release()                                         // run 1's edge resumes now
        let resumed = await eventually { source.positionReads == 1 }
        XCTAssertTrue(resumed)
        try await Task.sleep(nanoseconds: 100_000_000)           // let the resumed edge reach the actor

        source.inner.feed([Float](repeating: 1, count: Segmenter.chunkSamples))   // position 512: past the stale edge
        let translated = await eventually { await translator.calls.count == 1 }
        XCTAssertTrue(translated, "run 2's gate must not be closed by run 1's speaking edge")
        XCTAssertEqual(events.speakingEdges, [], "no stale .speaking event leaks into run 2")
        let ducked = await ducker.ducked
        XCTAssertEqual(ducked, 0, "run 1's ducking is not driven after run 1 ended")
        await pipeline.stop()
    }

    // MARK: the source after a failure

    /// `fail` leaves the player and the source to `stop()`, as on Windows — but the view model does not stop the
    /// pipeline on `.error`, it shows a banner and waits for "Try again", and the source keeps yielding 16 kHz
    /// Float32 the whole time. The capture stage returns on its next `isRunning` check; what keeps that from
    /// growing an unbounded `AsyncStream` buffer at 64 KB/s under the banner is that returning drops the stream's
    /// last iterator, which cancels the stream, after which every yield is refused (`.terminated`). This pins that
    /// mechanism: nothing is buffered, nothing is segmented, and `stop()` still lands on `.idle`.
    func testAfterAFailureTheAbandonedSourceStreamIsCancelledSoNothingBuffers() async throws {
        let source = FakeAudioSource(bufferLimit: 2)
        let segmenter = FakeSegmenter()
        let translator = FakeTranslator(fail: true)
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: translator,
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in FakePlayer(onSpeaking: onSpeaking) },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in segmenter }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)

        await pipeline.start(configuration())
        source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let failed = await eventually { events.hasError }
        XCTAssertTrue(failed)
        let state = await pipeline.state
        XCTAssertEqual(state, .error)
        XCTAssertFalse(source.stopped, "the source is left to stop(), as on Windows")

        for _ in 0 ..< 20 {                                      // the source keeps capturing under the banner
            source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(source.droppedFeeds, 0, "the stream must still be read, or its buffer grows for as long as the error banner is up")
        XCTAssertEqual(source.terminatedStreams, 1, "the abandoned stream was cancelled, not left buffering")
        let fed = await segmenter.feedCount
        XCTAssertEqual(fed, 1, "nothing is segmented after the failure")
        await pipeline.stop()
        let final = await pipeline.state
        XCTAssertEqual(final, .idle)
    }

    // MARK: the rest of the start/stop/fail contract

    func testMuteSetBeforeStartIsAppliedToTheNewPlayer() async throws {
        let h = makeHarness()
        await h.pipeline.setMuted(true)                          // no player, no ducking coordinator yet
        let isMuted = await h.pipeline.isMuted
        XCTAssertTrue(isMuted)
        let restoredBeforeStart = await h.ducker.restored
        XCTAssertEqual(restoredBeforeStart, 0)                   // nothing to restore before a run exists
        await h.pipeline.start(configuration())
        let muted = await h.player?.muted
        XCTAssertEqual(muted, true, "the player built by start() inherits the mute")
        await h.pipeline.stop()
    }

    func testNoteCaptureGapWhileIdleEmitsLagWithoutATranscript() async throws {
        let h = makeHarness()
        await h.pipeline.noteCaptureGap()
        let lagged = await eventually { h.events.hasLag }
        XCTAssertTrue(lagged)
        let drops = await h.transcript.drops
        XCTAssertEqual(drops, 0, "no run, no transcript sink to mark")
    }

    /// §9: a denied microphone or a failed engine surfaces from `source.start`. The player was built but is never
    /// started, the pipeline reports `.error` without ever having been `.running`, and `stop()` returns it to idle.
    func testSourceStartFailureEmitsErrorAndStopReturnsToIdle() async throws {
        let h = makeHarness()
        h.source.startError = FakeTranslatorError()
        await h.pipeline.start(configuration())
        let state = await h.pipeline.state
        XCTAssertEqual(state, .error)
        let failed = await eventually { h.events.hasError }
        XCTAssertTrue(failed)
        XCTAssertEqual(h.source.started, [.microphone])          // the attempt was made
        let playerStarted = await h.player?.started
        XCTAssertEqual(playerStarted, false, "the player is only started after the source")
        XCTAssertFalse(h.events.states.contains(.running))
        await h.pipeline.stop()
        let final = await h.pipeline.state
        XCTAssertEqual(final, .idle)
        let settled = await eventually { h.events.states == [.idle] }
        XCTAssertTrue(settled, "\(h.events.states)")
    }

    private actor FailingStartPlayer: AudioPlayer {
        func start() async throws { throw FakeTranslatorError() }
        func enqueue(_ clip: AudioClip) async {}
        func setMuted(_ muted: Bool) async {}
        func clear() async {}
        func stop() async {}
        var isSpeaking: Bool { get async { false } }
    }

    /// The source was started before the player, so a player that fails to start must not leave the capture tap
    /// installed behind it.
    func testPlayerStartFailureStopsTheSourceAndEmitsError() async throws {
        let source = FakeAudioSource()
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: FakeTranslator(),
            speaker: FakeSpeaker(),
            playerFactory: { _, _ in FailingStartPlayer() },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, _ in FakeSegmenter() }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        let events = EventCollector()
        events.start(pipeline)
        await pipeline.start(configuration())
        let state = await pipeline.state
        XCTAssertEqual(state, .error)
        XCTAssertEqual(source.started, [.microphone])
        XCTAssertTrue(source.stopped, "the tap is not left behind")
        let failed = await eventually { events.hasError }
        XCTAssertTrue(failed)
        await pipeline.stop()
        let final = await pipeline.state
        XCTAssertEqual(final, .idle)
    }

    /// A speaker that throws fails the run like a translator that throws; the phrase was already transcribed.
    func testSpeakerFailureEmitsErrorState() async throws {
        let h = makeHarness(speaker: FakeSpeaker(fail: true))
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let failed = await eventually { h.events.hasError }
        XCTAssertTrue(failed)
        let state = await h.pipeline.state
        XCTAssertEqual(state, .error)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.count, 1, "the transcript entry precedes the voice")
        await h.pipeline.stop()
    }

    /// A VAD that throws fails the run from the capture stage.
    func testVADFailureEmitsErrorState() async throws {
        let h = makeHarness(realSegmenter: true, vad: EnergyVAD(fail: true))
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let failed = await eventually { h.events.hasError }
        XCTAssertTrue(failed)
        let state = await h.pipeline.state
        XCTAssertEqual(state, .error)
        let calls = await h.translator.calls
        XCTAssertTrue(calls.isEmpty)
        await h.pipeline.stop()
        let final = await h.pipeline.state
        XCTAssertEqual(final, .idle)
    }

    func testStopOnANeverStartedPipelineEmitsNoStateEvent() async throws {
        let h = makeHarness()
        await h.pipeline.stop()
        let state = await h.pipeline.state
        XCTAssertEqual(state, .idle)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.events.states, [])
        let closed = await h.transcript.closed
        XCTAssertFalse(closed, "no transcript sink was ever built")
    }

    func testSegmenterFactoryReceivesTheConfiguredPreset() async throws {
        let presets = LockedBox<[SegmenterPreset]>([])
        let source = FakeAudioSource()
        var dependencies = PipelineDependencies(
            source: source, vad: EnergyVAD(), detector: FakeLanguageDetector(), translator: FakeTranslator(),
            speaker: FakeSpeaker(),
            playerFactory: { _, onSpeaking in FakePlayer(onSpeaking: onSpeaking) },
            ducker: FakeDucker(),
            transcriptFactory: { FakeTranscriptSink() },
            clock: FakeClock().now,
            sleep: FakeSleep().sleep)
        dependencies.segmenterFactory = { _, preset in
            presets.update { $0.append(preset) }
            return FakeSegmenter()
        }
        let pipeline = TranslationPipeline(dependencies: dependencies)
        await pipeline.start(PipelineConfiguration(captureMode: .broadcast, preset: .veryFast))
        XCTAssertEqual(presets.value, [.veryFast])
        XCTAssertEqual(source.started, [.broadcast])
        await pipeline.stop()
    }

    // MARK: Two-way routing through the pipeline (M8, §8.2)

    private actor StubTranscriber: Transcriber {
        func transcribe(_ audio: [Float], language: String) async throws -> TranslationCandidate {
            TranslationCandidate(language: language, languageProbability: nil,
                                 segments: [TranslationSegment(text: " Good morning.", noSpeechProbability: 0,
                                                               averageLogProbability: -0.1)])
        }
    }

    private actor StubSecondary: SecondaryTranslator {
        private let result: String?
        init(result: String?) { self.result = result }
        func translate(_ text: String, from source: String, to target: String) async throws -> String? { result }
    }

    /// `FakeLanguageDetector` reports "es", so ignoring "es" with two-way off must drop the phrase entirely:
    /// nothing transcribed, nothing spoken.
    func testAnIgnoredPhraseReachesNeitherTheTranscriptNorTheVoice() async throws {
        let h = makeHarness()
        var config = configuration()
        config.ignoredLanguage = "es"
        await h.pipeline.start(config)
        h.source.feed(segment())
        _ = await eventually(timeout: 0.5) { await h.speaker.texts.isEmpty == false }
        let entries = await h.transcript.entries
        XCTAssertTrue(entries.isEmpty, "an ignored phrase is not transcribed")
        let spoken = await h.speaker.texts
        XCTAssertTrue(spoken.isEmpty, "an ignored phrase is not spoken")
        await h.pipeline.stop()
    }

    func testATwoWayPhraseIsTranscribedAndSpokenInTheTargetLanguage() async throws {
        let h = makeHarness(transcriber: StubTranscriber(), secondary: StubSecondary(result: "Buenos días."))
        var config = configuration()
        config.ignoredLanguage = "es"
        config.twoWay = true
        config.twoWayLanguage = "fr"
        await h.pipeline.start(config)
        h.source.feed(segment())
        let spoke = await eventually { await h.speaker.texts.isEmpty == false }
        XCTAssertTrue(spoke)
        let spoken = await h.speaker.phrases
        XCTAssertEqual(spoken.first, SpokenPhrase(text: "Buenos días.", language: "fr"),
                       "the reply is spoken in the target language, not in English")
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.english, "Buenos días.")
        XCTAssertEqual(entries.first?.language, "fr", "tagged with the language the row is written in")
        await h.pipeline.stop()
    }

    /// The half of §8.2 that only shows up without an engine: the phrase is kept in the transcript so both sides
    /// of the conversation are readable, and the voice stays silent rather than saying it in the wrong language.
    func testAPhraseWithNoEngineForTheTargetIsTranscribedButNotSpoken() async throws {
        let h = makeHarness(transcriber: StubTranscriber(), secondary: StubSecondary(result: nil))
        var config = configuration()
        config.ignoredLanguage = "es"
        config.twoWay = true
        config.twoWayLanguage = "cy"
        await h.pipeline.start(config)
        h.source.feed(segment())
        let transcribed = await eventually { await h.transcript.entries.isEmpty == false }
        XCTAssertTrue(transcribed)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.english, "Good morning.")
        XCTAssertEqual(entries.first?.language, "es")
        _ = await eventually(timeout: 0.5) { await h.speaker.texts.isEmpty == false }
        let spoken = await h.speaker.texts
        XCTAssertTrue(spoken.isEmpty, "nothing is spoken when no engine can reach the target language")
        await h.pipeline.stop()
    }

    /// M9: with Learning on, the words as spoken reach the transcript row next to the translation.
    func testLearningPutsTheOriginalInTheTranscriptEntry() async throws {
        let h = makeHarness(transcriber: StubTranscriber())
        var config = configuration()
        config.wantsOriginal = true
        await h.pipeline.start(config)
        h.source.feed(segment())
        let recorded = await eventually { await h.transcript.entries.isEmpty == false }
        XCTAssertTrue(recorded)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.original, "Good morning.")
        XCTAssertFalse(entries.first?.english.isEmpty ?? true)
        await h.pipeline.stop()
    }

    // MARK: Unsure phrases (M11, §3)

    private func guessSegments() -> [TranslationSegment] {
        [TranslationSegment(text: " maybe", noSpeechProbability: 0, averageLogProbability: -2.0)]
    }

    private func confidentSegments() -> [TranslationSegment] {
        [TranslationSegment(text: " sure", noSpeechProbability: 0, averageLogProbability: -0.1)]
    }

    /// The entry that carries `isGuess` in the collected events, if any.
    private func guessEntry(in events: EventCollector) -> TranscriptEntry? {
        for event in events.events {
            if case .entry(let entry) = event, entry.isGuess { return entry }
        }
        return nil
    }

    func testAGuessReachesTheTranscriptAndTheEntryEventButNeverTheVoice() async throws {
        let h = makeHarness(translator: FakeTranslator(segments: guessSegments()))
        await h.pipeline.start(configuration())
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let recorded = await eventually { await h.transcript.entries.isEmpty == false }
        XCTAssertTrue(recorded)
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.first?.english, "maybe")
        XCTAssertEqual(entries.first?.isGuess, true, "with the default configuration a guess is kept")
        let emitted = await eventually { self.guessEntry(in: h.events) != nil }
        XCTAssertTrue(emitted, "\(h.events.events)")
        _ = await eventually(timeout: 0.5) { await h.speaker.texts.isEmpty == false }
        let spoken = await h.speaker.texts
        XCTAssertTrue(spoken.isEmpty, "a guess is never spoken")
        let enqueued = await h.player?.enqueued ?? []
        XCTAssertTrue(enqueued.isEmpty)
        XCTAssertFalse(h.events.events.contains { if case .transcriptOnly = $0 { return true }; return false },
                       "a guess is not a transcript-only phrase; the Live note must not fire")
        await h.pipeline.stop()
    }

    /// With `keepsGuesses` off the guess still reaches the `.entry` event (the Live screen shows it) but not the
    /// sink; the confident phrase behind it reaches both and is spoken.
    func testWithKeepsGuessesOffAGuessReachesTheEventButNotTheSink() async throws {
        let h = makeHarness(translator: FakeTranslator(segmentsPerCall: [guessSegments(), confidentSegments()]))
        var config = configuration()
        config.keepsGuesses = false
        await h.pipeline.start(config)
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let spoke = await eventually { await h.speaker.texts.isEmpty == false }
        XCTAssertTrue(spoke)
        let spoken = await h.speaker.texts
        XCTAssertEqual(spoken, ["sure"], "only the confident phrase is spoken")
        let entries = await h.transcript.entries
        XCTAssertEqual(entries.map(\.english), ["sure"], "the guess never reached the sink")
        XCTAssertEqual(entries.first?.isGuess, false)
        let guess = guessEntry(in: h.events)
        XCTAssertEqual(guess?.english, "maybe", "the Live screen still gets the guess: \(h.events.events)")
        await h.pipeline.stop()
    }

    /// The `.transcriptOnly` event carries the stage's reason, so the Live screen can say why the voice is silent.
    func testTranscriptOnlyEventCarriesTheReason() async throws {
        let h = makeHarness(transcriber: StubTranscriber(), secondary: StubSecondary(result: nil))
        var config = configuration()
        config.ignoredLanguage = "es"
        config.twoWay = true
        config.twoWayLanguage = "cy"
        await h.pipeline.start(config)
        h.source.feed([Float](repeating: 1, count: Segmenter.chunkSamples))
        let expected = PipelineEvent.transcriptOnly(reason: TranslationStage.unavailablePairReason(from: "es", to: "cy"))
        let noted = await eventually { h.events.events.contains(expected) }
        XCTAssertTrue(noted, "\(h.events.events)")
        await h.pipeline.stop()
    }
}
