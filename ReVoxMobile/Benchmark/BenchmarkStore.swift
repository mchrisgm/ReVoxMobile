import Foundation
import Observation
import os
import ReVoxCore

/// What identifies a run as this iPhone's (M11 §5): the hardware identifier, the iOS version and the memory tier.
struct BenchmarkHost: Sendable, Equatable {
    let device: String
    let iOSVersion: String
    let memoryTierGB: Int

    /// `utsname.machine` ("iPhone17,1"; the simulator reports its Mac's architecture) — not a required-reason API.
    static func hardwareIdentifier() -> String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { buffer -> String in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }

    static func current(deviceInfo: DeviceInfo, processInfo: ProcessInfo = .processInfo) -> BenchmarkHost {
        let version = processInfo.operatingSystemVersion
        return BenchmarkHost(device: hardwareIdentifier(),
                             iOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                             memoryTierGB: deviceInfo.memoryTierGB)
    }
}

/// The saved runs: one JSON file per run under `<Application Support>/ReVox/Benchmarks` (M11 §5), newest first.
/// `latest` is the newest run made on this iPhone with this WhisperKit, so a restored backup from another iPhone
/// or a pin bump is ignored, as `VerifiedLoadRecord` ignores stale versions.
@MainActor
@Observable
final class BenchmarkStore {
    static let folderName = "Benchmarks"
    private static let logger = Logger(subsystem: "revox", category: "models")

    let directory: URL
    let host: BenchmarkHost
    let whisperKitVersion: String
    private(set) var runs: [BenchmarkRun] = []

    init(directory: URL, host: BenchmarkHost, whisperKitVersion: String = LibraryVersions.whisperKit) {
        self.directory = directory
        self.host = host
        self.whisperKitVersion = whisperKitVersion
        self.runs = Self.load(from: directory)
    }

    /// `<Application Support>/ReVox/Benchmarks`, created; next to the models and settings, never in Documents.
    static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent(ModelLayout.rootFolderName, isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "1700000000.json": the run's date in seconds; a run takes far longer than a second.
    static func fileName(for run: BenchmarkRun) -> String {
        "\(Int(run.date.timeIntervalSince1970)).json"
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    var latest: BenchmarkRun? {
        runs.first { $0.device == host.device && $0.whisperKitVersion == whisperKitVersion }
    }

    func save(_ run: BenchmarkRun) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder().encode(run).write(to: directory.appendingPathComponent(Self.fileName(for: run)), options: .atomic)
        runs.append(run)
        runs.sort { $0.date > $1.date }
    }

    /// Every decodable `.json` in the folder, newest first; an undecodable file is logged and skipped.
    static func load(from directory: URL) -> [BenchmarkRun] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var runs: [BenchmarkRun] = []
        for file in files where file.pathExtension == "json" {
            do {
                runs.append(try decoder().decode(BenchmarkRun.self, from: try Data(contentsOf: file)))
            } catch {
                logger.error("skipping benchmark file \(file.lastPathComponent, privacy: .public): \(UserFacingErrorText.describe(error), privacy: .public)")
            }
        }
        return runs.sorted { $0.date > $1.date }
    }
}
