import XCTest
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// Runs only on a device with the models installed through the app (the test bundle is hosted by the app, so
/// `ModelLayout.defaultRoot()` is the app's own root). Every case skips in the simulator and without models.
final class DeviceMeasurementTests: XCTestCase {
    private func installedLayout() throws -> ModelLayout {
        #if targetEnvironment(simulator)
        throw XCTSkip("device only")
        #else
        return ModelLayout(root: try ModelLayout.defaultRoot())
        #endif
    }

    /// §10.1: `SileroVAD` scores zeros below the 0.5 threshold (the Windows integration check).
    func testSileroScoresSilenceBelowThreshold() async throws {
        let layout = try installedLayout()
        try XCTSkipUnless(layout.isVADInstalled(), "download a Whisper model in the app first (the VAD comes with it)")
        let vad = SileroVAD(bundleURL: layout.vadBundle)
        try await vad.load()
        let silence = [Float](repeating: 0, count: 512)
        for index in 0..<20 {
            let probability = try await vad.probability(of: silence)
            XCTAssertLessThan(probability, 0.5, "chunk \(index)")
        }
        let cpuAndANE = SileroVAD(bundleURL: layout.vadBundle, computeUnits: .cpuAndNeuralEngine)
        try await cpuAndANE.load()
        let probability = try await cpuAndANE.probability(of: silence)
        XCTAssertLessThan(probability, 0.5, ".cpuAndNeuralEngine numerics on silence")
    }

    /// §10.4: a hesitant opening still yields text with `firstTokenLogProbThreshold: nil`; the WhisperKit default may return "".
    /// Fixture: record "eh… buenos días" on the iPhone (Voice Memos), export as WAV, add it to the test target as
    /// `ReVoxMobileTests/Fixtures/hesitant-es.wav` (any rate; converted to 16 kHz here).
    func testFirstTokenThresholdComparison() async throws {
        let layout = try installedLayout()
        try XCTSkipUnless(layout.isWhisperInstalled(.small), "download small in the app first")
        guard let url = Bundle(for: DeviceMeasurementTests.self).url(forResource: "hesitant-es", withExtension: "wav") else {
            throw XCTSkip("add ReVoxMobileTests/Fixtures/hesitant-es.wav (see the doc comment)")
        }
        let samples = try Self.samples16k(from: url)
        let translator = WhisperKitTranslator(layout: layout, model: .small)
        try await translator.load { _ in }

        let withoutThreshold = try await translator.translate(samples, language: "es")
        let textWithout = SpeechGate.evaluate(withoutThreshold)?.english
        await translator.setFirstTokenLogProbThreshold(-1.5)
        let withDefault = try await translator.translate(samples, language: "es")
        let textWithDefault = SpeechGate.evaluate(withDefault)?.english

        print("MEASUREMENT firstToken nil → \(textWithout ?? "<dropped>") | default -1.5 → \(textWithDefault ?? "<dropped>")")
        XCTAssertNotNil(textWithout, "R3: with the threshold off the hesitant phrase must produce text")
    }

    private static func samples16k(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw PCMConversionError.bufferAllocationFailed
        }
        try file.read(into: buffer)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: PCMConverterDriver.pipelineFormat) else {
            throw PCMConversionError.conversionFailed
        }
        return try PCMConverterDriver.convertToMono(buffer, with: converter)
    }

    /// §10.4 (M4) and §10.1 `test_real_pocket_tts_generates_audio`: with the pack installed from the Voices screen and
    /// airplane mode on, `initialize()` and one synthesis per offered voice succeed without a request. Prints the RTF
    /// per voice and the resident memory for the measurement record.
    func testPocketTTSSynthesisesEveryOfferedVoiceOffline() async throws {
        let layout = try installedLayout()
        try XCTSkipUnless(layout.isPocketTTSInstalled(), "download pocket-tts in Settings > Voices first, then enable airplane mode")
        let speaker = PocketTTSSpeaker.make(voice: "alba", fluidBaseDirectory: layout.fluidBaseDirectory)
        let loadStarted = ContinuousClock.now
        try await speaker.load()
        print("MEASUREMENT pocket-tts load ms=\(Int((ContinuousClock.now - loadStarted) / .milliseconds(1)))")
        for voice in ModelCatalog.pocketTTS.offeredVoices {
            await speaker.setVoice(voice)
            let started = ContinuousClock.now
            let clip = try await speaker.synthesize("This is ReVox.")
            let elapsed = ContinuousClock.now - started
            let audioSeconds = Double(clip.samples.count) / Double(clip.sampleRate)
            let synthesisSeconds = elapsed / .seconds(1)
            print("MEASUREMENT pocket-tts voice=\(voice) audio_s=\(audioSeconds) synthesis_s=\(synthesisSeconds) rtf=\(synthesisSeconds / max(audioSeconds, 0.001))")
            XCTAssertEqual(clip.sampleRate, 24_000)
            XCTAssertGreaterThan(audioSeconds, 0.3, "\(voice): at least 0.3 s of audio for the sample sentence")
            XCTAssertGreaterThan(clip.samples.map { abs($0) }.max() ?? 0, 0.01, "\(voice): not silent")
        }
        print("MEASUREMENT pocket-tts resident_mb=\((MemoryMeter.residentBytes() ?? 0) / 1_048_576) peak_mb=\((MemoryMeter.peakBytes() ?? 0) / 1_048_576)")
    }
}
