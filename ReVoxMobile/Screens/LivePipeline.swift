/// The slice of `TranslationPipeline` the Live screen drives; tests substitute `FakeLivePipeline`.
protocol LivePipeline: Sendable {
    var events: AsyncStream<PipelineEvent> { get }
    func start(_ configuration: PipelineConfiguration) async
    func stop() async
    func setMuted(_ muted: Bool) async
    /// A capture gap (ring overrun or a keep-alive heartbeat gap): drop marker + `.lag`, no segment dropped (§5.4).
    func noteCaptureGap() async
}
