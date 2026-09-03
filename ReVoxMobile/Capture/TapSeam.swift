import AVFAudio
import Foundation

/// The three engine-graph operations `MicrophoneCapture` performs on the input node (§6.1), behind closures so
/// the tap and its rebuild — including the `.noInput` branch — are exercised in the simulator without hardware.
struct TapSeam: Sendable {
    /// The hardware tap format, or nil when the input is unavailable: `inputFormat(forBus: 0).sampleRate == 0`,
    /// the transient iOS leaves behind while it re-seats a route. The tap format must equal the hardware format
    /// because the input node does no conversion.
    var inputFormat: @Sendable (AVAudioEngine) -> AVAudioFormat?
    /// Installs the tap on bus 0 with the given format and buffer size.
    var install: @Sendable (AVAudioEngine, AVAudioFormat, AVAudioFrameCount, @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Void
    /// Removes the tap from bus 0. Removing a tap that is not installed is a no-op in AVFAudio.
    var remove: @Sendable (AVAudioEngine) -> Void

    static let live = TapSeam(
        inputFormat: { engine in
            guard engine.inputNode.inputFormat(forBus: 0).sampleRate > 0 else { return nil }
            return engine.inputNode.outputFormat(forBus: 0)
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
