import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// Records every seam call in order and fabricates the files a real download would leave behind.
final class InstallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [String] = []
    var failVariant = false
    var vadFractions: [Double] = [0, 0.5, 1]
    /// When set, the fabricated pocket-tts pack omits this voice's `.safetensors` file (the installed check must then fail).
    var pocketTTSOmitsVoice: String?

    func note(_ event: String) {
        lock.lock(); events.append(event); lock.unlock()
    }

    /// Drops everything recorded so far, so a test can assert the install window alone.
    func reset() {
        lock.lock(); events.removeAll(); lock.unlock()
    }
}

final class ModelInstallerTests: XCTestCase {
    private var root: URL!
    private var layout: ModelLayout!
    private var recorder: InstallRecorder!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ReVoxInstaller-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        layout = ModelLayout(root: root)
        recorder = InstallRecorder()
        defaults = UserDefaults(suiteName: "ReVoxInstallerTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // The seam closures are `@Sendable`, so the fabrication helpers are static and take the layout explicitly.
    private static func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    private func touch(_ url: URL) throws {
        try Self.touch(url)
    }

    private static func fabricateWhisperFiles(_ descriptor: WhisperModelDescriptor, in layout: ModelLayout) throws {
        let folder = layout.whisperFolder(descriptor)
        for bundle in ModelLayout.whisperBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(ModelLayout.compiledMarker))
        }
        try touch(folder.appendingPathComponent("config.json"))
    }

    private static func fabricateTokenizerFiles(_ descriptor: WhisperModelDescriptor, in layout: ModelLayout) throws {
        for file in ModelLayout.tokenizerFiles {
            try touch(layout.tokenizerFolder(descriptor).appendingPathComponent(file))
        }
    }

    static func fabricatePocketTTSFiles(in layout: ModelLayout, omittingVoice omitted: String?) throws {
        let folder = layout.pocketTTSLanguageFolder
        for bundle in ModelLayout.pocketTTSBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(ModelLayout.compiledMarker))
        }
        let constants = folder.appendingPathComponent(ModelLayout.pocketTTSConstantsFolder)
        for file in ModelLayout.pocketTTSConstantFiles {
            try touch(constants.appendingPathComponent(file))
        }
        for voice in ModelCatalog.pocketTTS.offeredVoices where voice != omitted {
            try touch(constants.appendingPathComponent(ModelLayout.pocketTTSVoiceFile(voice)))
        }
    }

    private func fabricateWhisperFiles(_ descriptor: WhisperModelDescriptor) throws {
        try Self.fabricateWhisperFiles(descriptor, in: layout)
    }

    private func fabricateTokenizerFiles(_ descriptor: WhisperModelDescriptor) throws {
        try Self.fabricateTokenizerFiles(descriptor, in: layout)
    }

    private func makeSteps() -> InstallSteps {
        let recorder = self.recorder!
        let layout = self.layout!
        return InstallSteps(
            downloadWhisperVariant: { descriptor, _, progress in
                recorder.note("variant:\(descriptor.folderName)")
                if recorder.failVariant { throw URLError(.notConnectedToInternet) }
                let p = Progress(totalUnitCount: 2)
                p.completedUnitCount = 1
                progress(p)
                try Self.fabricateWhisperFiles(descriptor, in: layout)
                p.completedUnitCount = 2
                progress(p)
                return layout.whisperFolder(descriptor)
            },
            downloadTokenizer: { descriptor, _, progress in
                recorder.note("tokenizer:\(descriptor.tokenizerRepo)")
                try Self.fabricateTokenizerFiles(descriptor, in: layout)
                let p = Progress(totalUnitCount: 3)
                p.completedUnitCount = 3
                progress(p)
                return layout.tokenizerFolder(descriptor)
            },
            downloadVAD: { repoDirectory, progress in
                recorder.note("vad")
                progress(0, .listing)
                for fraction in recorder.vadFractions {
                    progress(fraction, .downloading(completedFiles: Int(fraction * 6), totalFiles: 6))
                }
                try Self.touch(repoDirectory.appendingPathComponent(ModelCatalog.vad.subdirectory).appendingPathComponent(ModelLayout.compiledMarker))
            },
            verifyWhisper: { descriptor, _ in recorder.note("verifyWhisper:\(descriptor.folderName)") },
            verifyVAD: { _ in recorder.note("verifyVAD") },
            deleteVAD: { _ in recorder.note("deleteVAD") },
            setOfflineMode: { offline in recorder.note(offline ? "offline" : "online") },
            downloadPocketTTS: { fluidBaseDirectory, progress in
                recorder.note("pocketTTS")
                progress(0, .listing)
                progress(0.5, .downloading(completedFiles: 3, totalFiles: 6))
                // The production downloader appends `Models` to the base it is handed; the fake does the same
                // by fabricating through a layout, so the paths the installed check reads are the real ones.
                XCTAssertEqual(fluidBaseDirectory, layout.fluidBaseDirectory)
                try Self.fabricatePocketTTSFiles(in: layout, omittingVoice: recorder.pocketTTSOmitsVoice)
                progress(1, .compiling("flowlm_step_ane.mlmodelc"))
            },
            verifyPocketTTS: { _ in recorder.note("verifyPocketTTS") },
            deletePocketTTS: { directory in
                recorder.note("deletePocketTTS")
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(ModelLayout.pocketTTSFolder))
            }
        )
    }

    /// `ModelInstaller.init` arms offline mode (§6.9), which the seam records as `"offline"`. That first event is
    /// asserted once, by `testConstructionArmsOfflineMode`; every other test clears it here so its expected array
    /// is exactly the install window.
    private func makeInstaller() -> ModelInstaller {
        let installer = ModelInstaller(layout: layout, steps: makeSteps(), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        recorder.reset()
        return installer
    }

    func testConstructionArmsOfflineMode() {
        _ = ModelInstaller(layout: layout, steps: makeSteps(), verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        XCTAssertEqual(recorder.events, ["offline"], "offline mode is armed at construction and stays on until an install")
    }

    func testWhisperInstallSequenceAndOfflineModeWindow() async throws {
        let installer = makeInstaller()
        let states = StateCollector()
        try await installer.installWhisper(.small) { states.append($0) }

        XCTAssertEqual(recorder.events, [
            "online", "variant:openai_whisper-small", "tokenizer:openai/whisper-small", "offline", "verifyWhisper:openai_whisper-small",
        ])
        let ready = await installer.isWhisperReady(.small)
        XCTAssertTrue(ready)
        XCTAssertTrue(layout.isWhisperInstalled(.small))
    }

    func testWhisperInstallReportsDeterminateProgressThenVerifyingThenInstalled() async throws {
        let installer = makeInstaller()
        let states = StateCollector()
        try await installer.installWhisper(.tiny) { states.append($0) }
        let phases = states.all.map(\.phase)
        XCTAssertEqual(phases.first, .downloading(completedFiles: nil, totalFiles: nil))
        XCTAssertTrue(phases.contains(.verifying))
        XCTAssertEqual(phases.last, .installed)
        XCTAssertEqual(states.all.last?.fraction, 1)
        XCTAssertEqual(states.all.first?.bytesExpected, ModelCatalog.download(for: .whisper(.tiny)).expectedBytes)
        for state in states.all {
            XCTAssertNotNil(state.fraction, "the bar never turns into a spinner")
        }
        let variantStates = states.all.filter { $0.phase == .downloading(completedFiles: nil, totalFiles: nil) }
        XCTAssertLessThanOrEqual(variantStates.first!.fraction!, 0.98)
    }

    func testFailedVariantDownloadRestoresOfflineModeAndReportsFailed() async {
        recorder.failVariant = true
        let installer = makeInstaller()
        let states = StateCollector()
        do {
            try await installer.installWhisper(.base) { states.append($0) }
            XCTFail("expected the download error to propagate")
        } catch {
            XCTAssertEqual(recorder.events, ["online", "variant:openai_whisper-base", "offline"])
        }
        if case .failed(let message) = states.all.last?.phase {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("last state should be .failed, got \(String(describing: states.all.last))")
        }
        let ready = await installer.isWhisperReady(.base)
        XCTAssertFalse(ready)
    }

    func testReadyRequiresInstalledFilesAndARecordedVerifiedLoad() async throws {
        let installer = makeInstaller()
        let small = ModelCatalog.whisper(.small)
        try fabricateWhisperFiles(small)
        try fabricateTokenizerFiles(small)
        var ready = await installer.isWhisperReady(.small)
        XCTAssertFalse(ready, "installed but never verified")

        VerifiedLoadRecord(defaults: defaults).record(.whisper(.small))
        ready = await installer.isWhisperReady(.small)
        XCTAssertTrue(ready)

        try FileManager.default.removeItem(at: layout.whisperFolder(small))
        ready = await installer.isWhisperReady(.small)
        XCTAssertFalse(ready, "verified record without files is not ready")
    }

    func testVerifiedLoadRecordIsKeyedByLibraryVersion() {
        let record = VerifiedLoadRecord(defaults: defaults)
        record.record(.vad)
        XCTAssertTrue(record.isRecorded(.vad))
        XCTAssertFalse(record.isRecorded(.whisper(.small)))
        let stored = defaults.dictionary(forKey: VerifiedLoadRecord.key) as? [String: Bool]
        XCTAssertEqual(stored?["vad:\(LibraryVersions.fluidAudio)"], true)
        record.clear(.vad)
        XCTAssertFalse(record.isRecorded(.vad))
    }

    func testVADInstallBridgesFluidAudioPhases() async throws {
        let installer = makeInstaller()
        let states = StateCollector()
        try await installer.installVAD { states.append($0) }
        XCTAssertEqual(recorder.events, ["online", "vad", "offline", "verifyVAD"])
        let phases = states.all.map(\.phase)
        XCTAssertEqual(phases.first, .listing)
        XCTAssertTrue(phases.contains(.downloading(completedFiles: 3, totalFiles: 6)))
        XCTAssertEqual(phases.last, .installed)
        let ready = await installer.isVADReady()
        XCTAssertTrue(ready)
    }

    func testDeleteWhisperRemovesFolderSidecarsAndRecord() async throws {
        let installer = makeInstaller()
        try await installer.installWhisper(.small) { _ in }
        let small = ModelCatalog.whisper(.small)
        try touch(layout.whisperSidecarCache(small).appendingPathComponent("AudioEncoder.mlmodelc.metadata"))
        try await installer.deleteWhisper(.small)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.whisperFolder(small).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.whisperSidecarCache(small).path))
        XCTAssertFalse(VerifiedLoadRecord(defaults: defaults).isRecorded(.whisper(.small)))
        let ready = await installer.isWhisperReady(.small)
        XCTAssertFalse(ready)
    }

    // MARK: pocket-tts (Task 45, §6.5, §6.9)

    func testPocketTTSInstallSequenceReportsPhasesAndBecomesReady() async throws {
        let installer = makeInstaller()
        let states = StateCollector()
        try await installer.installPocketTTS { states.append($0) }

        XCTAssertEqual(recorder.events, ["online", "pocketTTS", "offline", "verifyPocketTTS"])
        let phases = states.all.map(\.phase)
        XCTAssertEqual(phases.first, .listing)
        XCTAssertTrue(phases.contains(.downloading(completedFiles: 3, totalFiles: 6)))
        XCTAssertTrue(phases.contains(.compiling("flowlm_step_ane.mlmodelc")))
        XCTAssertTrue(phases.contains(.verifying))
        XCTAssertEqual(phases.last, .installed)
        XCTAssertEqual(states.all.first?.bytesExpected, ModelCatalog.download(for: .pocketTTS).expectedBytes)
        for state in states.all {
            XCTAssertNotNil(state.fraction, "the pocket-tts bar is determinate from the first callback")
        }
        let ready = await installer.isPocketTTSReady()
        XCTAssertTrue(ready)
        XCTAssertTrue(layout.isPocketTTSInstalled())
        XCTAssertTrue(VerifiedLoadRecord(defaults: defaults).isRecorded(.pocketTTS))
    }

    func testPocketTTSInstallFailsWhenAVoiceFileIsMissingAfterDownload() async {
        recorder.pocketTTSOmitsVoice = "javert"
        let installer = makeInstaller()
        let states = StateCollector()
        do {
            try await installer.installPocketTTS { states.append($0) }
            XCTFail("expected filesMissingAfterDownload")
        } catch let error as ModelInstallError {
            XCTAssertEqual(error, .filesMissingAfterDownload(ModelLayout.pocketTTSFolder))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(recorder.events, ["online", "pocketTTS", "offline"], "no verified load without the full file set")
        if case .failed(let message) = states.all.last?.phase {
            XCTAssertTrue(message.contains(ModelLayout.pocketTTSFolder))
        } else {
            XCTFail("last state should be .failed, got \(String(describing: states.all.last))")
        }
        let ready = await installer.isPocketTTSReady()
        XCTAssertFalse(ready)
    }

    func testPocketTTSReadyRequiresInstalledFilesAndARecordedVerifiedLoad() async throws {
        let installer = makeInstaller()
        try Self.fabricatePocketTTSFiles(in: layout, omittingVoice: nil)
        var ready = await installer.isPocketTTSReady()
        XCTAssertFalse(ready, "installed but never verified")
        VerifiedLoadRecord(defaults: defaults).record(.pocketTTS)
        ready = await installer.isPocketTTSReady()
        XCTAssertTrue(ready)
        XCTAssertEqual(VerifiedLoadRecord.entryKey(for: .pocketTTS), "pocketTTS:\(LibraryVersions.fluidAudio)")
    }

    func testDeletePocketTTSClearsTheCacheAndTheRecord() async throws {
        let installer = makeInstaller()
        try await installer.installPocketTTS { _ in }
        await installer.deletePocketTTS()
        XCTAssertEqual(recorder.events.last, "deletePocketTTS")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.pocketTTSLanguageFolder.path))
        XCTAssertFalse(VerifiedLoadRecord(defaults: defaults).isRecorded(.pocketTTS))
        let ready = await installer.isPocketTTSReady()
        XCTAssertFalse(ready)
    }

    func testDefaultPocketTTSStepsRefuseInsteadOfSilentlySucceeding() async {
        let bare = InstallSteps(
            downloadWhisperVariant: { _, _, _ in throw URLError(.notConnectedToInternet) },
            downloadTokenizer: { _, _, _ in throw URLError(.notConnectedToInternet) },
            downloadVAD: { _, _ in throw URLError(.notConnectedToInternet) },
            verifyWhisper: { _, _ in },
            verifyVAD: { _ in },
            deleteVAD: { _ in },
            setOfflineMode: { _ in }
        )
        let installer = ModelInstaller(layout: layout, steps: bare, verifiedLoads: VerifiedLoadRecord(defaults: defaults))
        do {
            try await installer.installPocketTTS { _ in }
            XCTFail("the default closure must throw")
        } catch let error as ModelInstallError {
            XCTAssertEqual(error, .stepUnavailable("downloadPocketTTS"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

}

/// Thread-safe collector for the progress closure, which the installer may call off the main actor.
final class StateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ModelDownloadState] = []
    func append(_ state: ModelDownloadState) { lock.lock(); states.append(state); lock.unlock() }
    var all: [ModelDownloadState] { lock.lock(); defer { lock.unlock() }; return states }
}
