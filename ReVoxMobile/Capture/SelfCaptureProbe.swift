import Foundation

/// The M5 measurement of `captureLatencyFrames` (§5.2, §10.4): after the player's speaking-false edge (stamped with the
/// ring `writeCursor`), how many more ring frames still carry ReVox's own voice. Fed with one RMS/peak per 512-frame
/// chunk the capture reads; reports once per phrase when the 2 s window after the false edge has passed.
struct SelfCaptureProbe: Equatable, Sendable {
    static let voiceThresholdLevel: Float = 0.01     // −40 dBFS
    static let windowFrames: Int64 = 32_000          // 2 s at 16 kHz

    struct Measurement: Equatable, Sendable {
        let edgePosition: Int64                      // writeCursor at the speaking-false edge
        let lastVoiceEnd: Int64                      // end position of the last chunk above the threshold inside the window
        let peakWhileSpeaking: Float                 // re-capture present when clearly above the threshold
        let peakAfterEdge: Float
        var tailFrames: Int64 { lastVoiceEnd - edgePosition }
    }

    private var speaking = false
    private var edgePosition: Int64?
    private var lastVoiceEnd: Int64?
    private var peakWhileSpeaking: Float = 0
    private var peakAfterEdge: Float = 0

    init() {}

    mutating func speakingChanged(_ speaking: Bool, atPosition position: Int64) {
        if speaking {
            self.speaking = true
            edgePosition = nil
            lastVoiceEnd = nil
            peakWhileSpeaking = 0
            peakAfterEdge = 0
        } else if self.speaking {
            self.speaking = false
            edgePosition = position
            lastVoiceEnd = nil
            peakAfterEdge = 0
        }
    }

    mutating func observe(chunkEndingAt position: Int64, rms: Float, peak: Float) -> Measurement? {
        if speaking {
            peakWhileSpeaking = max(peakWhileSpeaking, peak)
            return nil
        }
        guard let edge = edgePosition else { return nil }
        if position <= edge + Self.windowFrames {
            if rms >= Self.voiceThresholdLevel {
                lastVoiceEnd = position
                peakAfterEdge = max(peakAfterEdge, peak)
            }
            return nil
        }
        let measurement = Measurement(edgePosition: edge, lastVoiceEnd: lastVoiceEnd ?? edge,
                                      peakWhileSpeaking: peakWhileSpeaking, peakAfterEdge: peakAfterEdge)
        edgePosition = nil
        lastVoiceEnd = nil
        return measurement
    }
}
