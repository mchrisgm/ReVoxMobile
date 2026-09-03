import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class ModelManagerTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReVoxModelLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: fabricated layouts

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    private func fabricateWhisper(_ id: WhisperModelID, tokenizer: Bool = true, coremldata: Bool = true) throws {
        let descriptor = ModelCatalog.whisper(id)
        let folder = layout.whisperFolder(descriptor)
        for bundle in ModelLayout.whisperBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(coremldata ? "coremldata.bin" : "model.mil"))
        }
        try touch(folder.appendingPathComponent("config.json"))
        if tokenizer {
            for file in ModelLayout.tokenizerFiles {
                try touch(layout.tokenizerFolder(descriptor).appendingPathComponent(file))
            }
        }
    }

    func testLayoutPathsFollowTheLibraries() {
        let small = ModelCatalog.whisper(.small)
        XCTAssertEqual(layout.whisperFolder(small).path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-small").path)
        XCTAssertEqual(layout.tokenizerFolder(small).path, root.appendingPathComponent("models/openai/whisper-small").path)
        XCTAssertEqual(layout.whisperSidecarCache(small).path, root.appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/openai_whisper-small").path)
        XCTAssertEqual(layout.vadRepoDirectory.path, root.appendingPathComponent("Models/silero-vad").path)
        XCTAssertEqual(layout.vadBundle.lastPathComponent, ModelCatalog.vad.subdirectory)
        XCTAssertEqual(layout.pocketTTSLanguageFolder.path, root.appendingPathComponent("Models/pocket-tts/v2.1/english").path)
    }

    func testWhisperInstalledWhenAllRequiredFilesPresent() throws {
        try fabricateWhisper(.small)
        XCTAssertTrue(layout.isWhisperInstalled(.small))
        XCTAssertEqual(layout.installedWhisperModels(), [.small])
    }

    func testWhisperNotInstalledWhenTokenizerMissing() throws {
        try fabricateWhisper(.base, tokenizer: false)
        XCTAssertFalse(layout.isWhisperInstalled(.base))
    }

    func testWhisperNotInstalledWhenCoremldataMissing() throws {
        try fabricateWhisper(.tiny, coremldata: false)
        XCTAssertFalse(layout.isWhisperInstalled(.tiny))
    }

    func testVADInstalledRequiresCoremldataAndNoPartials() throws {
        XCTAssertFalse(layout.isVADInstalled())
        try touch(layout.vadBundle.appendingPathComponent("coremldata.bin"))
        try touch(layout.vadBundle.appendingPathComponent("weights/weight.bin"))
        XCTAssertTrue(layout.isVADInstalled())
        try touch(layout.vadBundle.appendingPathComponent("weights/weight.bin.partial"))
        XCTAssertFalse(layout.isVADInstalled())
    }

    func testInstalledWhisperModelsKeepCatalogOrder() throws {
        try fabricateWhisper(.medium)
        try fabricateWhisper(.tiny)
        XCTAssertEqual(layout.installedWhisperModels(), [.tiny, .medium])
    }

    // MARK: ModelDownloadState bridging

    func testWhisperVariantProgressFillsTheFirst98Percent() {
        let progress = Progress(totalUnitCount: 4)
        progress.completedUnitCount = 2
        let state = ModelDownloadState.whisperVariant(progress, bytesExpected: 486_500_000)
        XCTAssertEqual(state.phase, .downloading(completedFiles: nil, totalFiles: nil))
        XCTAssertEqual(state.fraction!, 0.49, accuracy: 0.0001)
        XCTAssertEqual(state.bytesExpected, 486_500_000)
    }

    func testTokenizerProgressFillsTheLastTwoPercent() {
        let progress = Progress(totalUnitCount: 3)
        progress.completedUnitCount = 3
        let state = ModelDownloadState.whisperTokenizer(progress, bytesExpected: 1)
        XCTAssertEqual(state.fraction!, 1.0, accuracy: 0.0001)
        progress.completedUnitCount = 0
        XCTAssertEqual(ModelDownloadState.whisperTokenizer(progress, bytesExpected: 1).fraction!, 0.98, accuracy: 0.0001)
    }

    func testFluidAudioPhasesBridge() {
        let listing = ModelDownloadState.fluidAudio(fractionCompleted: 0, phase: .listing, bytesExpected: 950_000)
        XCTAssertEqual(listing.phase, .listing)
        XCTAssertEqual(listing.fraction, 0)
        let downloading = ModelDownloadState.fluidAudio(fractionCompleted: 0.4, phase: .downloading(completedFiles: 2, totalFiles: 6), bytesExpected: 950_000)
        XCTAssertEqual(downloading.phase, .downloading(completedFiles: 2, totalFiles: 6))
        XCTAssertEqual(downloading.fraction, 0.4)
        let compiling = ModelDownloadState.fluidAudio(fractionCompleted: 0.9, phase: .compiling("silero-vad-unified-v6.0.0.mlmodelc"), bytesExpected: 950_000)
        XCTAssertEqual(compiling.phase, .compiling("silero-vad-unified-v6.0.0.mlmodelc"))
    }

    func testIdleStateHasNoFraction() {
        let idle = ModelDownloadState.idle(bytesExpected: 76_600_000)
        XCTAssertEqual(idle.phase, .idle)
        XCTAssertNil(idle.fraction)
    }

    func testPartialScanFindsNestedPartials() throws {
        let folder = root.appendingPathComponent("scan", isDirectory: true)
        try touch(folder.appendingPathComponent("a/b/c.bin"))
        XCTAssertFalse(ModelLayout.containsPartialFiles(under: folder))
        try touch(folder.appendingPathComponent("a/b/d.bin.partial"))
        XCTAssertTrue(ModelLayout.containsPartialFiles(under: folder))
    }
}
