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

    func testDefaultFileURLIsUnderApplicationSupportReVox() throws {
        let url = try SettingsStore.defaultFileURL()
        XCTAssertEqual(url.lastPathComponent, SettingsCodec.fileName)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "ReVox")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        XCTAssertTrue(url.path.hasPrefix(support.path))
    }
}
