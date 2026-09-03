import Foundation

/// Port of `revox/pipeline/pipeline.py:Pipeline`: capture → segment → translate → speak with backpressure.
/// Three stage tasks, one speaking-edge drain task, all state behind a private actor (R12).
public final class TranslationPipeline: Sendable {
    public let events: AsyncStream<PipelineEvent>
    private let core: PipelineActor

    public init(dependencies: PipelineDependencies) {
        let (stream, continuation) = AsyncStream.makeStream(of: PipelineEvent.self)
        events = stream
        core = PipelineActor(dependencies: dependencies, events: continuation)
    }

    public var state: PipelineState {
        get async { await core.state }
    }

    /// No-op while running.
    public func start(_ configuration: PipelineConfiguration) async {
        await core.start(configuration)
    }

    /// Idempotent; also transitions an `.error` pipeline to `.idle`.
    public func stop() async {
        await core.stop()
    }

    public func setMuted(_ muted: Bool) async {
        await core.setMuted(muted)
    }

    public var isMuted: Bool {
        get async { await core.isMuted }
    }

    /// Broadcast reader detected a ring overrun: emits `.lag` and a drop marker without dropping a segment.
    public func noteCaptureGap() async {
        await core.noteCaptureGap()
    }
}

actor PipelineActor {
    private let dependencies: PipelineDependencies
    private let events: AsyncStream<PipelineEvent>.Continuation

    private(set) var state: PipelineState = .idle
    private(set) var isMuted = false
    private var running = false
    /// Generation token: bumped by every `start` and every `stop`. `stop()`'s join is bounded (2 s), so a stage
    /// task can outlive the run that spawned it; every hand-off carries the run it belongs to and is ignored once
    /// `runID` has moved on — during the idle window after `stop()` as much as after a restart.
    private var runID = 0

    private var queue = BoundedSegmentQueue<[Float]>()
    private var captureGate = CaptureGate()
    private var ducking: DuckingCoordinator?
    private var transcript: (any TranscriptSink)?
    private var player: (any AudioPlayer)?
    private var wake: AsyncStream<Void>.Continuation?
    private var texts: AsyncStream<String>.Continuation?
    private var edges: AsyncStream<Bool>.Continuation?
    private var tasks: [Task<Void, Never>] = []

    init(dependencies: PipelineDependencies, events: AsyncStream<PipelineEvent>.Continuation) {
        self.dependencies = dependencies
        self.events = events
    }

    /// True only for the current run: an abandoned stage task from an earlier run always sees `false`.
    func isRunning(_ run: Int) -> Bool { running && run == runID }

    // MARK: start / stop

    func start(_ configuration: PipelineConfiguration) async {
        guard !running else { return }
        // Claim this run's generation before any per-run state is replaced, so a stage task abandoned by the
        // previous `stop()` cannot touch the queue, gate, transcript sink or player built below.
        runID &+= 1
        let run = runID
        let deps = dependencies

        queue = BoundedSegmentQueue(capacity: configuration.maxPending)
        let segmenter = deps.segmenterFactory(deps.vad, configuration.preset)
        await segmenter.reset()                       // the only VAD reset of the run (R1)
        captureGate = CaptureGate(holdFrames: configuration.captureGateHoldFrames,
                                  captureLatencyFrames: configuration.captureLatencyFrames)
        let ducking = DuckingCoordinator(ducker: deps.ducker, enabled: configuration.duckingEnabled,
                                         hold: configuration.duckingHoldNanoseconds, sleep: deps.sleep)
        self.ducking = ducking
        let transcript = deps.transcriptFactory()
        self.transcript = transcript
        let stage = TranslationStage(detector: deps.detector, translator: deps.translator,
                                     pinnedLanguage: configuration.pinnedLanguage)

        let (wakeStream, wakeContinuation) = AsyncStream.makeStream(of: Void.self)
        let (textStream, textContinuation) = AsyncStream.makeStream(of: String.self)
        let (edgeStream, edgeContinuation) = AsyncStream.makeStream(of: Bool.self)
        wake = wakeContinuation
        texts = textContinuation
        edges = edgeContinuation

        // The speaking callback only yields into the edge stream; the drain task applies edges in order (§4.3).
        let player = deps.playerFactory(deps.speaker.sampleRate) { speaking in
            edgeContinuation.yield(speaking)
        }
        self.player = player
        await player.setMuted(isMuted)
        do {
            try await player.start()
        } catch {
            fail(error, run: run)
            return
        }
        let frames = deps.source.frames()              // fresh stream for this run, before start(_:)
        do {
            try await deps.source.start(configuration.captureMode)
        } catch {
            fail(error, run: run)
            return
        }

        running = true
        tasks = [
            captureTask(frames: frames, segmenter: segmenter, run: run),
            translateTask(wake: wakeStream, stage: stage, run: run),
            speakTask(texts: textStream, speaker: deps.speaker, player: player, run: run),
            edgeTask(edges: edgeStream, ducking: ducking, run: run),
        ]
        setState(.running)
    }

    func stop() async {
        let wasRunning = running || state == .error
        running = false
        // Retire this run's generation: the join below is bounded, so a stage task can outlive `stop()`.
        // Bumping here (not only in `start`) fences an abandoned task out of the idle window too, so a
        // straggler that throws after `stop()` returns cannot drive a stopped pipeline to `.error`.
        runID &+= 1
        await dependencies.source.stop()
        wake?.finish()
        texts?.finish()
        edges?.finish()
        wake = nil
        texts = nil
        edges = nil
        let pending = tasks
        tasks = []
        for task in pending {
            task.cancel()
        }
        for task in pending {
            await Self.awaitBounded(task, nanoseconds: 2_000_000_000)   // Windows join(timeout=2)
        }
        if let player {
            await player.stop()
            self.player = nil
        }
        if let ducking {
            await ducking.restoreNow()                 // forwarded whenever ducking is enabled
            self.ducking = nil
        }
        if let transcript {
            await transcript.close()
            self.transcript = nil
        }
        if wasRunning || state != .idle {
            setState(.idle)
        }
    }

    func setMuted(_ muted: Bool) async {
        isMuted = muted
        if let player {
            await player.setMuted(muted)
        }
        if muted, let ducking {
            await ducking.restoreNow()                 // Windows: self._ducker.restore(), unconditional
        }
    }

    func noteCaptureGap() async {
        events.yield(.lag)
        await transcript?.addDropMarker(at: dependencies.clock())
    }

    // MARK: stage hand-offs (called from the stage tasks)

    func gateAllows(chunkEndingAt position: Int64) -> Bool {
        captureGate.allows(chunkEndingAt: position)
    }

    /// `_enqueue_segment`: one `.lag` event and one drop marker per dropped element, then a wake for the translate stage.
    func enqueueSegment(_ segment: [Float], run: Int) async {
        guard running, run == runID else { return }
        let dropped = queue.push(segment)
        for _ in 0 ..< dropped {
            events.yield(.lag)
            await transcript?.addDropMarker(at: dependencies.clock())
        }
        wake?.yield(())
    }

    /// Popped before the translator is awaited, so `queue.count` has the Windows `qsize()` meaning.
    /// No `running` check: the translate stage must still drain what it popped during its own run.
    func popSegment(run: Int) -> [Float]? {
        guard run == runID else { return nil }
        return queue.pop()
    }

    func recordTranslation(_ result: Translation, run: Int) async {
        guard running, run == runID else { return }
        let entry = TranscriptEntry(timestamp: dependencies.clock(), language: result.language,
                                    original: "", english: result.english)
        await transcript?.add(entry)
        events.yield(.entry(entry))
        texts?.yield(result.english)
    }

    func applySpeakingEdge(_ speaking: Bool, run: Int, ducking: DuckingCoordinator) async {
        guard run == runID else { return }
        let position = await dependencies.source.capturePosition()
        captureGate.speakingChanged(speaking, atPosition: position)
        await ducking.speakingChanged(speaking)
        events.yield(.speaking(speaking))
    }

    /// `_fail`: the other stages exit on their next `isRunning(_:)` check; player and source are left to `stop()`.
    /// A straggler from a stopped run never drives the pipeline to `.error`, whether it is idle or already
    /// re-started: `stop()` retires the run's generation, so `run == runID` fails for the rest of its life.
    func fail(_ error: Error, run: Int) {
        guard run == runID else { return }
        running = false
        state = .error
        events.yield(.error(String(describing: error)))
    }

    private func setState(_ newState: PipelineState) {
        state = newState
        events.yield(.state(newState))
    }

    // MARK: stage tasks

    private func captureTask(frames: AsyncStream<CapturedAudio>, segmenter: any PhraseSegmenter, run: Int) -> Task<Void, Never> {
        Task.detached { [self] in
            var reframer = ChunkReframer()
            for await captured in frames {
                for chunk in reframer.push(captured.samples, endingAt: captured.endPosition) {
                    guard await self.isRunning(run) else { return }
                    guard await self.gateAllows(chunkEndingAt: chunk.endPosition) else { continue }
                    do {
                        for phrase in try await segmenter.feed(chunk.samples) {
                            await self.enqueueSegment(phrase, run: run)
                        }
                    } catch {
                        if error is CancellationError { return }
                        await self.fail(error, run: run)
                        return
                    }
                }
            }
            // Stream finished (source stopped): no flush, the in-progress phrase is discarded, as on Windows.
        }
    }

    private func translateTask(wake: AsyncStream<Void>, stage: TranslationStage, run: Int) -> Task<Void, Never> {
        Task.detached { [self] in
            for await _ in wake {
                while let segment = await self.popSegment(run: run) {
                    guard await self.isRunning(run) else { return }
                    do {
                        guard let result = try await stage.translate(segment) else { continue }
                        // Re-checked after the await: the translator may have outlived this run's `stop()`.
                        guard await self.isRunning(run) else { continue }
                        await self.recordTranslation(result, run: run)
                    } catch {
                        if error is CancellationError { return }
                        await self.fail(error, run: run)
                        return
                    }
                }
            }
        }
    }

    private func speakTask(texts: AsyncStream<String>, speaker: any Speaker, player: any AudioPlayer, run: Int) -> Task<Void, Never> {
        Task.detached { [self] in
            for await text in texts {
                guard await self.isRunning(run) else { return }
                do {
                    let clip = try await speaker.synthesize(text)
                    await player.enqueue(clip)
                } catch {
                    if error is CancellationError { return }
                    await self.fail(error, run: run)
                    return
                }
            }
        }
    }

    private func edgeTask(edges: AsyncStream<Bool>, ducking: DuckingCoordinator, run: Int) -> Task<Void, Never> {
        Task.detached { [self] in
            for await speaking in edges {
                await self.applySpeakingEdge(speaking, run: run, ducking: ducking)
            }
        }
    }

    /// Waits for `task` but never longer than `nanoseconds` — the Windows `thread.join(timeout=2)`.
    /// The waiter and the timer are **detached**, not structured children: `withTaskGroup` would wait for
    /// every child before returning, and cancelling the child that awaits `task.value` does not make a
    /// `Task<Void, Never>` return early, so a stage stuck inside an uninterruptible model call (an M3
    /// `WhisperKit.transcribe` prediction) would hold the actor for its full duration. Here the deadline
    /// wins and the abandoned stage task finishes on its own — harmlessly, because every hand-off it can
    /// still reach carries its `run` and is rejected once `runID` has moved on.
    private static func awaitBounded(_ task: Task<Void, Never>, nanoseconds: UInt64) async {
        let (finished, continuation) = AsyncStream.makeStream(of: Void.self)
        let waiter = Task.detached { await task.value; continuation.finish() }
        let timeout = Task.detached { try? await Task.sleep(nanoseconds: nanoseconds); continuation.finish() }
        for await _ in finished { break }
        waiter.cancel()
        timeout.cancel()
    }
}
