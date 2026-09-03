import XCTest
@testable import ReVoxCore

final class ModelCatalogTests: XCTestCase {
    func testFiveEntriesInOrderWithFolderNamesAndSizes() {
        XCTAssertEqual(ModelCatalog.whisperModels.map(\.id), [.tiny, .base, .small, .medium, .largeV3])
        XCTAssertEqual(ModelCatalog.whisperModels.map(\.folderName), [
            "openai_whisper-tiny", "openai_whisper-base", "openai_whisper-small",
            "openai_whisper-medium", "openai_whisper-large-v3_947MB",
        ])
        XCTAssertEqual(ModelCatalog.whisperModels.map(\.approximateBytes), [
            76_600_000, 146_700_000, 486_500_000, 1_528_000_000, 948_000_000,
        ])
        XCTAssertEqual(ModelCatalog.whisperModels.map(\.tokenizerRepo), [
            "openai/whisper-tiny", "openai/whisper-base", "openai/whisper-small",
            "openai/whisper-medium", "openai/whisper-large-v3",
        ])
        XCTAssertTrue(ModelCatalog.whisperModels.allSatisfy { $0.modelRepo == "argmaxinc/whisperkit-coreml" })
        XCTAssertEqual(WhisperModelID.allCases.map(\.displayName), ["tiny", "base", "small", "medium", "large-v3"])
        XCTAssertEqual(WhisperModelID.largeV3.rawValue, "large-v3")
        XCTAssertEqual(ModelCatalog.whisper(.largeV3).note, "Compressed weights Argmax ships for iPhone")
        XCTAssertEqual(ModelCatalog.whisper(.medium).note, "Long load time and heat on eligible devices")
        XCTAssertNil(ModelCatalog.whisper(.small).note)
    }

    func testNoTurboOrDistilAndDefaultSmall() {
        for descriptor in ModelCatalog.whisperModels {
            XCTAssertFalse(descriptor.folderName.contains("turbo"), descriptor.folderName)
            XCTAssertFalse(descriptor.folderName.contains("distil"), descriptor.folderName)
        }
        XCTAssertEqual(ModelCatalog.defaultWhisperModel, .small)
    }

    func testWhisperRevisionsArePinnedSHAs() throws {
        let sha = try NSRegularExpression(pattern: "^[0-9a-f]{40}$")
        for descriptor in ModelCatalog.whisperModels {
            for revision in [descriptor.revision, descriptor.tokenizerRevision] {
                XCTAssertNotEqual(revision, "main")
                XCTAssertEqual(sha.numberOfMatches(in: revision, range: NSRange(revision.startIndex..., in: revision)), 1, revision)
            }
        }
        XCTAssertEqual(ModelCatalog.whisper(.tiny).revision, ModelCatalog.whisper(.largeV3).revision)   // one repo, one commit
    }

    func testRequiredRelativePaths() {
        XCTAssertEqual(ModelCatalog.whisper(.small).requiredRelativePaths, [
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small/MelSpectrogram.mlmodelc/coremldata.bin",
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small/AudioEncoder.mlmodelc/coremldata.bin",
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small/TextDecoder.mlmodelc/coremldata.bin",
            "models/argmaxinc/whisperkit-coreml/openai_whisper-small/config.json",
            "models/openai/whisper-small/tokenizer.json",
            "models/openai/whisper-small/tokenizer_config.json",
            "models/openai/whisper-small/config.json",
        ])
        XCTAssertEqual(ModelCatalog.vad.requiredRelativePaths, ["Models/silero-vad/silero-vad-unified-v6.0.0.mlmodelc/coremldata.bin"])
    }

    func testVADAndPocketTTSDescriptors() {
        XCTAssertEqual(ModelCatalog.vad.repo, "FluidInference/silero-vad-coreml")
        XCTAssertEqual(ModelCatalog.vad.subdirectory, "silero-vad-unified-v6.0.0.mlmodelc")
        XCTAssertEqual(ModelCatalog.vad.approximateBytes, 950_000)
        XCTAssertEqual(ModelCatalog.pocketTTS.repo, "FluidInference/pocket-tts-coreml")
        XCTAssertEqual(ModelCatalog.pocketTTS.languageFolder, "v2.1/english")
        XCTAssertEqual(ModelCatalog.pocketTTS.approximateBytes, 527_300_000)
        XCTAssertEqual(ModelCatalog.pocketTTS.offeredVoices, ["alba", "azelma", "cosette", "javert"])
    }

    func testLicences() {
        XCTAssertEqual(ModelCatalog.licences.map(\.id), ["whisperkit", "fluidaudio", "pocket-tts", "silero-vad", "whisper"])
        XCTAssertEqual(ModelCatalog.licences.map(\.licence), ["MIT", "Apache-2.0", "CC-BY-4.0", "MIT", "MIT"])
        XCTAssertEqual(ModelCatalog.licences.map(\.url.absoluteString), [
            "https://github.com/argmaxinc/WhisperKit",
            "https://github.com/FluidInference/FluidAudio",
            "https://huggingface.co/FluidInference/pocket-tts-coreml",
            "https://github.com/snakers4/silero-vad",
            "https://github.com/openai/whisper",
        ])
        let pocketTTS = ModelCatalog.licences.first { $0.id == "pocket-tts" }
        XCTAssertEqual(pocketTTS?.attribution, "pocket-tts by Kyutai (https://kyutai.org)")
        XCTAssertEqual(ModelCatalog.licences.filter { $0.attribution != nil }.count, 1)
    }

    func testDownloadDescriptors() {
        XCTAssertEqual(ModelCatalog.download(for: .whisper(.base)),
                       DownloadDescriptor(kind: .whisper(.base), expectedBytes: 146_700_000, displayName: "Whisper base"))
        XCTAssertEqual(ModelCatalog.download(for: .vad).expectedBytes, 950_000)
        XCTAssertEqual(ModelCatalog.download(for: .pocketTTS).expectedBytes, 527_300_000)
    }

    func testHasRoomToInstallBoundaries() {
        // 400 MB × 1.25 + 200 MB = 700 MB
        XCTAssertTrue(ModelCatalog.hasRoomToInstall(expectedBytes: 400_000_000, availableBytes: 700_000_000))
        XCTAssertFalse(ModelCatalog.hasRoomToInstall(expectedBytes: 400_000_000, availableBytes: 699_999_999))
        XCTAssertTrue(ModelCatalog.hasRoomToInstall(expectedBytes: 0, availableBytes: 200_000_000))
        XCTAssertFalse(ModelCatalog.hasRoomToInstall(expectedBytes: 0, availableBytes: 199_999_999))
    }
}
