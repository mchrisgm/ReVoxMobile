import AVFAudio
import Foundation

/// The three engine-graph operations `MicrophoneCapture` performs on the input node (§6.1), behind closures so
/// the tap and its rebuild — including the `.noInput` branch — are exercised in the simulator without hardware.
struct TapSeam: Sendable {
    /// The hardware tap format, or nil when the input is unavailable — the transient iOS leaves behind while it
    /// re-seats a route. The tap format must equal the hardware format because the input node does no conversion.
    var inputFormat: @Sendable (AVAudioEngine) -> AVAudioFormat?
    /// Installs the tap on bus 0 with the given format and buffer size.
    var install: @Sendable (AVAudioEngine, AVAudioFormat, AVAudioFrameCount, @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Void
    /// Removes the tap from bus 0. Removing a tap that is not installed is a no-op in AVFAudio.
    var remove: @Sendable (AVAudioEngine) -> Void

    static let live = TapSeam(
        inputFormat: { engine in
            // Validate the value that is actually passed to `installTap`, not a different one. This used to guard
            // on `inputFormat(forBus: 0).sampleRate` and then return `outputFormat(forBus: 0)`; iOS does not update
            // the two together while a route moves, so the guard could pass while the returned format still had a
            // zero sample rate or zero channels. AVFAudio answers that with `IsFormatSampleRateAndChannelCountValid`
            // failing inside `installTapOnBus`, which is an NSException — uncatchable from Swift, so SIGABRT.
            // That is TestFlight build 15's crash, on a route change (docs/measurements/m3-microphone-mode.md).
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
            return format
        },
        install: { engine, format, bufferSize, handler in
            engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
                handler(buffer)
            }
        },
        remove: { engine in
            engine.inputNode.removeTap(onBus: 0)
        }
    )
}
