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
                             transcriber: (any Transcriber)? = nil, secondary: (any SecondaryTranslator)? = nil) -> Harness {
        let source = FakeAudioSource()
        let vad = EnergyVAD()
        let speaker = FakeSpeaker()
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
}
