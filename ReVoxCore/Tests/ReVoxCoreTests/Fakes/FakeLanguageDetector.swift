import Foundation
@testable import ReVoxCore

actor FakeLanguageDetector: LanguageDetector {
    private let detection: LanguageDetection
    private(set) var calls = 0

    init(language: String = "es", probability: Float = 0.95) {
        detection = LanguageDetection(language: language, probability: probability)
    }

    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection {
        calls += 1
        return detection
    }
}
