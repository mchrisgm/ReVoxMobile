import AVFAudio
import Foundation
import os

/// `AVSpeechSynthesizer.write(_:toBufferCallback:)` collector (§6.6): buffers until the zero-length terminating
/// buffer (ASSUMED; Task 42 measures it) or the timeout `max(3 s, 4 × characters / 15 s)`.
final class SpeechWriteCollector: @unchecked Sendable {
    static let minimumTimeout: TimeInterval = 3
    static let charactersPerSecond: Double = 15

    private static let logger = Logger(subsystem: "revox", category: "measurements")

    private let synthesizer = AVSpeechSynthesizer()   // retained for the life of the collector (Apple: retain until speech concludes)
    private let lock = NSLock()

    static func timeout(forCharacterCount count: Int) -> TimeInterval {
        max(minimumTimeout, 4 * Double(count) / charactersPerSecond)
    }

    func collect(_ utterance: AVSpeechUtterance) async -> [AVAudioPCMBuffer] {
        let timeout = Self.timeout(forCharacterCount: utterance.speechString.count)
        let state = CollectState()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>) in
            let finish: @Sendable () -> Void = {
                if let buffers = state.finish() {
                    continuation.resume(returning: buffers)
                }
            }
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    SpeechWriteCollector.logger.info("write ended by terminating buffer")
                    finish()
                } else {
                    state.append(pcm)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if state.finishIfPending() {
                    SpeechWriteCollector.logger.error("write ended by timeout after \(timeout, privacy: .public) s")
                    continuation.resume(returning: state.collected)
                }
            }
        }
    }

    /// Lock-guarded accumulator that resolves exactly once.
    private final class CollectState: @unchecked Sendable {
        private let lock = NSLock()
        private var buffers: [AVAudioPCMBuffer] = []
        private var finished = false

        private(set) var collected: [AVAudioPCMBuffer] = []

        /// Timeout path: marks finished and reports whether it was the first to do so.
        func finishIfPending() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return false }
            finished = true
            collected = buffers
            return true
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            buffers.append(buffer)
        }

        func finish() -> [AVAudioPCMBuffer]? {
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return nil }
            finished = true
            return buffers
        }
    }
}
