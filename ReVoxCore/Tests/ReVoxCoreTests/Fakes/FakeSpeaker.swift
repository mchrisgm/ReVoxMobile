import Foundation
@testable import ReVoxCore

/// 100 ones at 24 kHz; an empty clip for whitespace-only text without counting an engine call.
actor FakeSpeaker: Speaker {
    nonisolated let sampleRate = 24_000
    private(set) var texts: [String] = []
    /// Everything said, with the language it was said in (M8); `texts` stays the plain list the older tests read.
    private(set) var phrases: [SpokenPhrase] = []

    func synthesize(_ text: String) async throws -> AudioClip {
        try await synthesize(text, language: "en")
    }

    func synthesize(_ text: String, language: String) async throws -> AudioClip {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AudioClip(samples: [], sampleRate: sampleRate)
        }
        texts.append(text)
        phrases.append(SpokenPhrase(text: text, language: language))
        return AudioClip(samples: [Float](repeating: 1, count: 100), sampleRate: sampleRate)
    }
}
