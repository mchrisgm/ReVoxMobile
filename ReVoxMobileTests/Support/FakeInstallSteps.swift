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

    /// Creates every missing component of `directory` one at a time with the path-based API.
    ///
    /// `createDirectory(at:withIntermediateDirectories:)` fails on the simulator with ENOTDIR naming the model
    /// root, while `fileExists` reports that same root as an existing directory and the folders below it as
    /// missing (run 33777714285). Creating each component separately avoids whatever that URL-based call does
    /// with the path, and names the exact component if one is genuinely rejected.
    static func makeDirectory(_ directory: URL) throws {
        var components: [String] = []
        var probe = directory
        while probe.path != "/", !FileManager.default.fileExists(atPath: probe.path) {
            components.append(probe.path)
            probe = probe.deletingLastPathComponent()
        }
        for path in components.reversed() {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue   // another task created it first
            } catch {
                throw NSError(domain: "FakeInstallSteps", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "mkdir \(path) failed: \(error); ancestors: \(ancestorReport(URL(fileURLWithPath: path)))",
                ])
            }
        }
    }

    /// Each ancestor of `url`, innermost first, as `name(exists,dir)`.
    static func ancestorReport(_ url: URL) -> String {
        var parts: [String] = []
        var probe = url.deletingLastPathComponent()
        while probe.path != "/", parts.count < 10 {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: probe.path, isDirectory: &isDirectory)
            parts.append("\(probe.lastPathComponent)(\(exists ? "exists" : "missing"),\(isDirectory.boolValue ? "dir" : "file"))")
            probe = probe.deletingLastPathComponent()
        }
        return parts.joined(separator: " < ")
    }

    /// Errors name the step and the path: a bare Cocoa write error names only the volume's top folder, which
    /// is not enough to tell which fabricated file failed.
    static func touch(_ url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        do {
            try Data([0]).write(to: url)
        } catch {
            throw NSError(domain: "FakeInstallSteps", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "write \(url.path) failed: \(error); ancestors: \(ancestorReport(url))",
            ])
        }
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
