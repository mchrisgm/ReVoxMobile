import XCTest
import ReVoxCore
@testable import ReVoxMobile

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func temporaryFile() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReVoxSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(SettingsCodec.fileName)
    }

    func testMissingFileGivesDefaults() {
        let store = SettingsStore(fileURL: temporaryFile())
        XCTAssertEqual(store.settings, Settings())
        XCTAssertNil(store.lastSaveError)
    }

    func testEveryChangeIsSavedAndReadBack() {
        let url = temporaryFile()
        let store = SettingsStore(fileURL: url)
        store.update { $0.model = "medium" }
        store.update { $0.language = "fr" }
        store.update { $0.latencyMode = "fast" }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reread = SettingsStore(fileURL: url)
        XCTAssertEqual(reread.settings.model, "medium")
        XCTAssertEqual(reread.settings.language, "fr")
        XCTAssertEqual(reread.settings.preset, .fast)
        XCTAssertEqual(reread.settings.whisperModel, .medium)
    }

    /// R11 / §5.7: a corrupt or wrongly typed `settings.json` is never a launch failure. The store comes up with the
    /// defaults, and the next change rewrites the file whole, so the corruption does not survive it.
    func testACorruptFileGivesDefaultsAndTheNextChangeRewritesIt() throws {
        let url = temporaryFile()
        try Data("{ \"model\": 42, not json".utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings, Settings())
        XCTAssertNil(store.lastSaveError)

        store.update { $0.ducking = false }
        XCTAssertNil(store.lastSaveError)
        let reread = SettingsStore(fileURL: url)
        XCTAssertFalse(reread.settings.ducking)
        XCTAssertEqual(reread.settings.model, Settings().model, "the rest of the defaults were written with it")
    }

    /// A wrong type for one key discards the file, not just the key (Windows: `TypeError` → defaults).
    func testAWrongTypeForOneKeyFallsBackToEveryDefault() throws {
        let url = temporaryFile()
        try Data("{ \"model\": \"medium\", \"ducking\": \"yes\" }".utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertEqual(store.settings, Settings())
    }

    func testAnUnchangedUpdateWritesNothing() {
        let url = temporaryFile()
        let store = SettingsStore(fileURL: url)
        store.update { _ in }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "no change, no write")
    }

    func testDefaultFileURLIsUnderApplicationSupportReVox() throws {
        let url = try SettingsStore.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, SettingsCodec.fileName)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ReVox")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        XCTAssertTrue(url.path.hasPrefix(support.path))
    }
}
