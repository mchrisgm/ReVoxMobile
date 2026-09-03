import Foundation
@testable import ReVoxCore

/// 100 ones at 24 kHz; an empty clip for whitespace-only text without counting an engine call.
actor FakeSpeaker: Speaker {
    nonisolated let sampleRate = 24_000
    private(set) var texts: [String] = []

    func synthesize(_ text: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        texts.append(text)
        return AudioClip(samples: [Float](repeating: 1, count: 100), sampleRate: sampleRate)
    }
}
