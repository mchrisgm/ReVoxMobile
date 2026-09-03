import Foundation

/// Self-capture suppression (R9): closes the segmenter input while the player reports speaking and for
/// `holdFrames + captureLatencyFrames` capture frames after the speaking-false edge.
///
/// Keyed on capture positions (absolute 16 kHz frame indices on the source's own timeline), never on host time:
/// each chunk carries the position of its last sample and each speaking edge is stamped with the source's capture
/// position at the moment the edge is drained.
///
/// The gate remembers **one** displaced interval besides the current one. In broadcast capture the reader lags the
/// writer — by up to the `.audio` notification cadence in steady state and by up to `RingReader.defaultCatchUpFrames`
/// right after an attach — while speaking edges are stamped with the writer cursor. A second utterance therefore
/// opens a new window at a position the reader has not reached yet, and the frames of the previous utterance that
/// are still unread would otherwise be evaluated only against the new window and pass through to the VAD: ReVox's
/// own voice reaching the translator. Carrying the interval the new window displaces keeps those frames dropped.
/// One slot is enough (the next displacement replaces it, so the memory never accumulates) and the interval is
/// bounded, so it stops mattering as soon as capture positions run past its end. Mic mode is unaffected: both
/// positions coincide there, so nothing is ever still pending when an edge arrives.
public struct CaptureGate: Sendable, Equatable {
    public static let defaultHoldFrames = 4_800          // 300 ms at 16 kHz

    public let holdFrames: Int
    public let captureLatencyFrames: Int

    private var speaking = false
    /// Position of the speaking-true edge that opened the current closed window (`p₁`); nil when never closed.
    private var closedFrom: Int64?
    /// First position allowed again after a speaking-false edge (`p₀ + holdFrames + captureLatencyFrames`);
    /// nil while speaking or while no hold is pending.
    private var openAt: Int64?
    /// The completed interval displaced by the most recent new window, `[from, until)`; nil until one is displaced.
    private var displaced: ClosedWindow?

    /// One completed closed interval: closed from `from`, open again at `until`.
    private struct ClosedWindow: Equatable {
        var from: Int64
        var until: Int64
    }

    public init(holdFrames: Int = CaptureGate.defaultHoldFrames, captureLatencyFrames: Int = 0) {
        self.holdFrames = holdFrames
        self.captureLatencyFrames = captureLatencyFrames
    }

    /// Player speaking edge, stamped with the source's capture position at the moment of the edge.
    public mutating func speakingChanged(_ speaking: Bool, atPosition position: Int64) {
        if speaking {
            if let openAt, position <= openAt {
                // Re-trigger inside the hold: the closed window continues from the original edge.
            } else if !self.speaking {
                // A new window opens past the previous hold: remember the interval it displaces, so chunks of the
                // previous utterance that the reader has not delivered yet are still dropped.
                if let closedFrom, let openAt {
                    displaced = ClosedWindow(from: closedFrom, until: openAt)
                }
                closedFrom = position
            }
            openAt = nil
            self.speaking = true
        } else {
            guard self.speaking else { return }
            self.speaking = false
            openAt = position + Int64(holdFrames + captureLatencyFrames)
        }
    }

    /// True when a chunk whose last sample has capture position `position` may reach the segmenter:
    /// it ends before the speaking-true edge, or at/after the end of the hold, and it falls outside the one
    /// displaced interval the gate still remembers.
    public func allows(chunkEndingAt position: Int64) -> Bool {
        if let displaced, position >= displaced.from, position < displaced.until { return false }
        guard let closedFrom else { return true }
        if position < closedFrom { return true }
        if let openAt { return position >= openAt }
        return false
    }

    /// True while speaking or while a post-speech hold is pending. Reflects the edges seen, not chunk positions;
    /// the per-chunk decision is `allows(chunkEndingAt:)`.
    public var isClosed: Bool { speaking || openAt != nil }
}
