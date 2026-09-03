import Foundation
import ReVoxCore
@testable import ReVoxMobile

/// A seam whose downloads can be held open (to test cancel, pause and resume) and that fabricates the
/// files a real download leaves on disk. Every closure is cancellation-aware through `Task.sleep`.
final class FakeInstallSteps: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private(set) var offlineModeHistory: [Bool] = []
    private(set) var variantDownloads: [String] = []
    private(set) var vadDownloads = 0
    private(set) var vadDeletes = 0
    var failVariantOnce = false

    var holdDownloads: Bool {
        get { lock.lock(); defer { lock.unlock() }; return held }
        set { lock.lock(); held = newValue; lock.unlock() }
    }

    private func note(_ body: () -> Void) { lock.lock(); body(); lock.unlock() }

    private func waitWhileHeld() async throws {
        while holdDownloads {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    static func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    static func fabricateWhisper(_ id: WhisperModelID, in layout: ModelLayout) throws {
        let descriptor = ModelCatalog.whisper(id)
        let folder = layout.whisperFolder(descriptor)
        for bundle in ModelLayout.whisperBundles {
            try touch(folder.appendingPathComponent(bundle).appendingPathComponent(ModelLayout.compiledMarker))
        }
        try touch(folder.appendingPathComponent("config.json"))
        for file in ModelLayout.tokenizerFiles {
            try touch(layout.tokenizerFolder(descriptor).appendingPathComponent(file))
        }
    }

    static func fabricateVAD(in layout: ModelLayout) throws {
        try touch(layout.vadBundle.appendingPathComponent(ModelLayout.compiledMarker))
    }

    func steps(layout: ModelLayout) -> InstallSteps {
        InstallSteps(
            downloadWhisperVariant: { [self] descriptor, _, progress in
                note { variantDownloads.append(descriptor.folderName) }
                if failVariantOnce {
                    failVariantOnce = false
                    throw URLError(.notConnectedToInternet)
                }
                let p = Progress(totalUnitCount: 2)
                p.completedUnitCount = 1
                progress(p)
                try await waitWhileHeld()
                try Self.fabricateWhisper(descriptor.id, in: layout)
                p.completedUnitCount = 2
                progress(p)
                return layout.whisperFolder(descriptor)
            },
            downloadTokenizer: { descriptor, _, progress in
                let p = Progress(totalUnitCount: 3)
                p.completedUnitCount = 3
                progress(p)
                return layout.tokenizerFolder(descriptor)
            },
            downloadVAD: { [self] _, progress in
                note { vadDownloads += 1 }
                progress(0, .listing)
                try await waitWhileHeld()
                progress(1, .downloading(completedFiles: 6, totalFiles: 6))
                try Self.fabricateVAD(in: layout)
            },
            verifyWhisper: { _, _ in },
            verifyVAD: { _ in },
            deleteVAD: { [self] directory in
                note { vadDeletes += 1 }
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(ModelLayout.vadFolder))
            },
            setOfflineMode: { [self] offline in note { offlineModeHistory.append(offline) } }
        )
    }
}
