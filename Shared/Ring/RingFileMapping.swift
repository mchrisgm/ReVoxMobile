import Foundation
import ReVoxCore

enum RingFileError: Error, Equatable {
    case absent
    case tooSmall(actualBytes: Int)
    case openFailed(errno: Int32)
    case statFailed(errno: Int32)
    case mapFailed(errno: Int32)
    case createFailed
    case growFailed(String)
}

/// One `MAP_SHARED` mapping of the ring file "RVXRING1" (§6.2, §7.1, R10). Both processes map read/write: the
/// app writes only `readCursor` and `overrunCount`, the extension writes everything else. The app never creates,
/// truncates or grows the file (`openExisting`); the extension creates it with
/// `FileProtectionType.completeUntilFirstUserAuthentication`, excludes it from backup and only ever grows it
/// (`openCreating`). `munmap` and `close` run in `deinit`.
final class RingFileMapping {
    static let directoryComponents = "Library/Application Support/ReVox"

    let url: URL
    let base: UnsafeMutableRawPointer
    let count: Int
    private let descriptor: Int32

    private init(url: URL, descriptor: Int32, base: UnsafeMutableRawPointer, count: Int) {
        self.url = url
        self.descriptor = descriptor
        self.base = base
        self.count = count
    }

    deinit {
        munmap(base, count)
        close(descriptor)
    }

    static func ringURL(in containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent(directoryComponents, isDirectory: true)
            .appendingPathComponent(RingLayout.fileName, isDirectory: false)
    }

    /// App side. `.absent` when there is no file, `.tooSmall` when it is shorter than the layout.
    static func openExisting(at url: URL, layout: RingLayout = .v1) throws -> RingFileMapping {
        let descriptor = open(url.path, O_RDWR)
        guard descriptor >= 0 else {
            let code = errno
            throw code == ENOENT ? RingFileError.absent : RingFileError.openFailed(errno: code)
        }
        do {
            return try map(url: url, descriptor: descriptor, layout: layout)
        } catch {
            close(descriptor)
            throw error
        }
    }

    /// Extension side. Creates the directory and the file if absent, grows the file to `layout.totalBytes` if it is
    /// shorter (never shrinks), marks it excluded from backup, then maps it like `openExisting`.
    static func openCreating(at url: URL, layout: RingLayout = .v1, fileManager: FileManager = .default) throws -> RingFileMapping {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            guard fileManager.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
                throw RingFileError.createFailed
            }
        }
        let handle = try FileHandle(forUpdating: url)
        let size = try handle.seekToEnd()
        if size < UInt64(layout.totalBytes) {
            do {
                try handle.truncate(atOffset: UInt64(layout.totalBytes))
            } catch {
                try? handle.close()
                throw RingFileError.growFailed(String(describing: error))
            }
        }
        try handle.close()
        var excluded = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(&values)
        return try openExisting(at: url, layout: layout)
    }

    private static func map(url: URL, descriptor: Int32, layout: RingLayout) throws -> RingFileMapping {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw RingFileError.statFailed(errno: errno) }
        let size = Int(info.st_size)
        guard size >= layout.totalBytes else { throw RingFileError.tooSmall(actualBytes: size) }
        guard let pointer = mmap(nil, layout.totalBytes, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
              pointer != UnsafeMutableRawPointer(bitPattern: -1) else {
            throw RingFileError.mapFailed(errno: errno)
        }
        return RingFileMapping(url: url, descriptor: descriptor, base: pointer, count: layout.totalBytes)
    }

    /// Zeroes the 60 s data region and leaves the header untouched (the extension calls it on `broadcastStarted`, §11).
    func zeroDataRegion(layout: RingLayout = .v1) {
        guard count >= layout.totalBytes else { return }
        (base + layout.headerBytes).initializeMemory(as: UInt8.self, repeating: 0, count: layout.dataBytes)
    }
}
