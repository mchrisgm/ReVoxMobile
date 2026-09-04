import Foundation
import ReVoxCore

/// Darwin notification names derived from the App Group id (§7.4). Names only: a Darwin notification never
/// carries a payload, so nothing crosses the process boundary through this channel except the name itself.
struct BroadcastNotificationNames: Equatable, Sendable {
    let appGroup: String

    init(appGroup: String) {
        self.appGroup = appGroup
    }

    var started: String { appGroup + ".broadcast.started" }
    var paused: String { appGroup + ".broadcast.paused" }
    var resumed: String { appGroup + ".broadcast.resumed" }
    var stopped: String { appGroup + ".broadcast.stopped" }
    var formatChanged: String { appGroup + ".broadcast.formatChanged" }
    var audio: String { appGroup + ".broadcast.audio" }          // ≤ 10/s
    var appAttached: String { appGroup + ".app.attached" }       // app → extension, diagnostics only

    /// Extension → app, in the order the app's observer registers them.
    var extensionToApp: [String] { [started, paused, resumed, stopped, formatChanged, audio] }
}

enum BroadcastState: String, Codable, Sendable, Equatable {
    case running, paused, finished, failed, lost
}

/// The `sourceASBD` dictionary of the record: the `AudioStreamBasicDescription` of the current `.audioApp` stream.
struct SourceFormatRecord: Codable, Equatable, Sendable {
    var sampleRate: Double
    var formatID: UInt32
    var formatFlags: UInt32
    var bytesPerPacket: UInt32
    var framesPerPacket: UInt32
    var bytesPerFrame: UInt32
    var channelsPerFrame: UInt32
    var bitsPerChannel: UInt32

    init(_ asbd: RingHeader.ASBD) {
        sampleRate = asbd.sampleRate
        formatID = asbd.formatID
        formatFlags = asbd.formatFlags
        bytesPerPacket = asbd.bytesPerPacket
        framesPerPacket = asbd.framesPerPacket
        bytesPerFrame = asbd.bytesPerFrame
        channelsPerFrame = asbd.channelsPerFrame
        bitsPerChannel = asbd.bitsPerChannel
    }

    var asbd: RingHeader.ASBD {
        RingHeader.ASBD(sampleRate: sampleRate, formatID: formatID, formatFlags: formatFlags, bytesPerPacket: bytesPerPacket,
                        framesPerPacket: framesPerPacket, bytesPerFrame: bytesPerFrame, channelsPerFrame: channelsPerFrame,
                        bitsPerChannel: bitsPerChannel, reserved: 0)
    }
}

/// `"broadcast.state"` (§7.4): written by the extension only at transitions (started, paused, resumed, finished,
/// failed, first format, annotation, first mic buffer); the app writes it once, with `state = lost`, when the
/// heartbeat went stale (§9).
struct BroadcastStateRecord: Codable, Equatable, Sendable {
    static let key = "broadcast.state"
    static let currentContractVersion = 1

    var contractVersion: Int = BroadcastStateRecord.currentContractVersion
    var ringFile: String = RingLayout.fileName
    var generation: UInt64
    var state: BroadcastState
    var startedAt: Double
    var finishedAt: Double?
    var finishReason: String?             // only the extension's own error text (§6.2, §7.1 step 6)
    var writerPID: Int32
    var sourceASBD: SourceFormatRecord?
    var asbdChangeCount: Int = 0
    var annotatedBundleID: String?
    var micToggleSeen: Bool = false

    init(generation: UInt64, state: BroadcastState, startedAt: Double, writerPID: Int32) {
        self.generation = generation
        self.state = state
        self.startedAt = startedAt
        self.writerPID = writerPID
    }
}

/// `"capture.reader"` (§7.4): the app's last attach time, read cursor and generation.
struct CaptureReaderRecord: Codable, Equatable, Sendable {
    static let key = "capture.reader"

    var lastAttachedAt: Double
    var lastReadCursor: UInt64
    var generation: UInt64

    init(lastAttachedAt: Double, lastReadCursor: UInt64, generation: UInt64) {
        self.lastAttachedAt = lastAttachedAt
        self.lastReadCursor = lastReadCursor
        self.generation = generation
    }
}

/// The App Group suite (`UserDefaults(suiteName:)`, privacy reason 1C8F.1 in both manifests). Records are stored
/// as property-list dictionaries so `defaults read` shows them; a record that fails to decode reads as nil.
/// `@unchecked Sendable`: `UserDefaults` is thread-safe and the store holds nothing else.
final class BroadcastRecordStore: @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    convenience init?(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        self.init(defaults: defaults)
    }

    func readBroadcastState() -> BroadcastStateRecord? {
        read(BroadcastStateRecord.key)
    }

    func write(_ record: BroadcastStateRecord) {
        write(record, key: BroadcastStateRecord.key)
    }

    func readCaptureReader() -> CaptureReaderRecord? {
        read(CaptureReaderRecord.key)
    }

    func write(_ record: CaptureReaderRecord) {
        write(record, key: CaptureReaderRecord.key)
    }

    private func read<Record: Decodable>(_ key: String) -> Record? {
        guard let dictionary = defaults.dictionary(forKey: key),
              let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0) else {
            return nil
        }
        return try? PropertyListDecoder().decode(Record.self, from: data)
    }

    private func write<Record: Encodable>(_ record: Record, key: String) {
        guard let data = try? PropertyListEncoder().encode(record),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return
        }
        defaults.set(object, forKey: key)
    }
}

/// Posts one Darwin notification. The `CFNotificationName` is built once at init so the extension allocates
/// nothing when it posts (§7.3); `deliverImmediately` is always true (§7.4).
struct DarwinNotificationPoster {
    private let name: CFNotificationName

    init(name: String) {
        self.name = CFNotificationName(rawValue: name as CFString)
    }

    func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), name, nil, nil, true)
    }
}
