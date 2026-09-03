import Foundation

/// Ring file "RVXRING1" (R10): a 4 096-byte header followed by a 60 s ring of mono 16 kHz Float32 samples.
public struct RingLayout: Sendable, Equatable {
    public static let v1 = RingLayout(magic: "RVXRING1", headerBytes: 4_096, capacityFrames: 960_000, sampleRate: 16_000)
    public static let fileName = "audio-ring-v1.bin"

    public let magic: String
    public let headerBytes: Int
    public let capacityFrames: Int
    public let sampleRate: Int

    public init(magic: String, headerBytes: Int, capacityFrames: Int, sampleRate: Int) {
        self.magic = magic
        self.headerBytes = headerBytes
        self.capacityFrames = capacityFrames
        self.sampleRate = sampleRate
    }

    public var dataBytes: Int { capacityFrames * MemoryLayout<Float>.size }   // 3 840 000
    public var totalBytes: Int { headerBytes + dataBytes }                      // 3 844 096
}

/// The bytes of the ring plus atomic cursor accessors. The app and the extension map the file and implement the
/// accessors with a C11 atomics shim; tests use `HeapRingStorage`.
public protocol RingStorage: AnyObject, Sendable {
    var base: UnsafeMutableRawPointer { get }
    var count: Int { get }
    /// Acquire load of the 64-bit cursor at `offset` (8-byte aligned).
    func loadCursor(at offset: Int) -> UInt64
    /// Release store of the 64-bit cursor at `offset`.
    func storeCursor(_ value: UInt64, at offset: Int)
}

/// `@unchecked Sendable`: owns one fixed allocation for its lifetime; the cursor accessors take an `NSLock`
/// (lock acquire = acquire, unlock = release), giving tests the ordering the C11 shim gives production.
public final class HeapRingStorage: RingStorage, @unchecked Sendable {
    public let base: UnsafeMutableRawPointer
    public let count: Int
    private let lock = NSLock()

    public convenience init(layout: RingLayout) {
        self.init(bytes: layout.totalBytes)
    }

    /// For "too small" tests.
    public init(bytes: Int) {
        count = bytes
        base = UnsafeMutableRawPointer.allocate(byteCount: max(bytes, 8), alignment: 8)
        base.initializeMemory(as: UInt8.self, repeating: 0, count: max(bytes, 8))
    }

    deinit {
        base.deallocate()
    }

    public func loadCursor(at offset: Int) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return UInt64(littleEndian: base.load(fromByteOffset: offset, as: UInt64.self))
    }

    public func storeCursor(_ value: UInt64, at offset: Int) {
        lock.lock()
        defer { lock.unlock() }
        base.storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt64.self)
    }
}

public struct RingHeader: Sendable, Equatable {
    public enum State: UInt32, Sendable {
        case idle = 0, running, paused, finished, failed
    }

    /// AudioStreamBasicDescription snapshot, 40 bytes.
    public struct ASBD: Sendable, Equatable {
        public var sampleRate: Double
        public var formatID: UInt32
        public var formatFlags: UInt32
        public var bytesPerPacket: UInt32
        public var framesPerPacket: UInt32
        public var bytesPerFrame: UInt32
        public var channelsPerFrame: UInt32
        public var bitsPerChannel: UInt32
        public var reserved: UInt32

        public init(sampleRate: Double = 0, formatID: UInt32 = 0, formatFlags: UInt32 = 0, bytesPerPacket: UInt32 = 0,
                    framesPerPacket: UInt32 = 0, bytesPerFrame: UInt32 = 0, channelsPerFrame: UInt32 = 0,
                    bitsPerChannel: UInt32 = 0, reserved: UInt32 = 0) {
            self.sampleRate = sampleRate
            self.formatID = formatID
            self.formatFlags = formatFlags
            self.bytesPerPacket = bytesPerPacket
            self.framesPerPacket = framesPerPacket
            self.bytesPerFrame = bytesPerFrame
            self.channelsPerFrame = channelsPerFrame
            self.bitsPerChannel = bitsPerChannel
            self.reserved = reserved
        }
    }

    public struct PTS: Sendable, Equatable {
        public var value: Int64
        public var timescale: Int32
        public var flags: UInt32

        public init(value: Int64 = 0, timescale: Int32 = 0, flags: UInt32 = 0) {
            self.value = value
            self.timescale = timescale
            self.flags = flags
        }
    }

    public var magic: String
    public var headerBytes: UInt32
    public var capacityFrames: UInt32
    public var sampleRate: UInt32
    public var channels: UInt16
    public var sampleFormat: UInt16
    public var generation: UInt64
    public var writeCursor: UInt64
    public var readCursor: UInt64
    public var state: State
    public var asbdChangeCount: UInt32
    public var lastWriteAt: Double
    public var startedAt: Double
    public var lastPTS: PTS
    public var lastAsbdChangeAt: Double
    public var sourceASBD: ASBD
    public var droppedInputFrames: UInt64
    public var micBuffersSeen: UInt64
    public var overrunCount: UInt64
    public var peakLevel1s: Float
    public var rmsLevel1s: Float
    public var writerPID: UInt32

    public init(magic: String, headerBytes: UInt32, capacityFrames: UInt32, sampleRate: UInt32, channels: UInt16,
                sampleFormat: UInt16, generation: UInt64, writeCursor: UInt64, readCursor: UInt64, state: State,
                asbdChangeCount: UInt32, lastWriteAt: Double, startedAt: Double, lastPTS: PTS, lastAsbdChangeAt: Double,
                sourceASBD: ASBD, droppedInputFrames: UInt64, micBuffersSeen: UInt64, overrunCount: UInt64,
                peakLevel1s: Float, rmsLevel1s: Float, writerPID: UInt32) {
        self.magic = magic
        self.headerBytes = headerBytes
        self.capacityFrames = capacityFrames
        self.sampleRate = sampleRate
        self.channels = channels
        self.sampleFormat = sampleFormat
        self.generation = generation
        self.writeCursor = writeCursor
        self.readCursor = readCursor
        self.state = state
        self.asbdChangeCount = asbdChangeCount
        self.lastWriteAt = lastWriteAt
        self.startedAt = startedAt
        self.lastPTS = lastPTS
        self.lastAsbdChangeAt = lastAsbdChangeAt
        self.sourceASBD = sourceASBD
        self.droppedInputFrames = droppedInputFrames
        self.micBuffersSeen = micBuffersSeen
        self.overrunCount = overrunCount
        self.peakLevel1s = peakLevel1s
        self.rmsLevel1s = rmsLevel1s
        self.writerPID = writerPID
    }

    /// Byte offsets of every header field (all little-endian; 8-byte fields 8-byte aligned).
    public enum Offset {
        public static let magic = 0                 // [8]UInt8
        public static let headerBytes = 8           // UInt32
        public static let capacityFrames = 12       // UInt32
        public static let sampleRate = 16           // UInt32
        public static let channels = 20             // UInt16
        public static let sampleFormat = 22         // UInt16
        public static let generation = 24           // UInt64
        public static let writeCursor = 32          // UInt64
        public static let readCursor = 40           // UInt64
        public static let state = 48                // UInt32
        public static let asbdChangeCount = 52      // UInt32
        public static let lastWriteAt = 56          // Float64
        public static let startedAt = 64            // Float64
        public static let lastPTSValue = 72         // Int64
        public static let lastPTSTimescale = 80     // Int32
        public static let lastPTSFlags = 84         // UInt32
        public static let lastAsbdChangeAt = 88     // Float64
        public static let sourceASBD = 96           // 40 bytes
        public static let droppedInputFrames = 136  // UInt64
        public static let micBuffersSeen = 144      // UInt64
        public static let overrunCount = 152        // UInt64
        public static let peakLevel1s = 160         // Float32
        public static let rmsLevel1s = 164          // Float32
        public static let writerPID = 168           // UInt32
        public static let reservedStart = 172       // zero up to headerBytes
    }

    /// Reads the header; nil on bad magic or a storage shorter than the fixed fields.
    public static func read(from storage: any RingStorage) -> RingHeader? {
        guard storage.count >= Offset.reservedStart else { return nil }
        let base = storage.base
        let magicBytes = (0 ..< 8).map { base.load(fromByteOffset: Offset.magic + $0, as: UInt8.self) }
        guard let magic = String(bytes: magicBytes, encoding: .ascii), magic == RingLayout.v1.magic else { return nil }
        let asbdBase = Offset.sourceASBD
        let asbd = ASBD(sampleRate: base.loadDouble(asbdBase),
                        formatID: base.loadUInt32(asbdBase + 8),
                        formatFlags: base.loadUInt32(asbdBase + 12),
                        bytesPerPacket: base.loadUInt32(asbdBase + 16),
                        framesPerPacket: base.loadUInt32(asbdBase + 20),
                        bytesPerFrame: base.loadUInt32(asbdBase + 24),
                        channelsPerFrame: base.loadUInt32(asbdBase + 28),
                        bitsPerChannel: base.loadUInt32(asbdBase + 32),
                        reserved: base.loadUInt32(asbdBase + 36))
        return RingHeader(magic: magic,
                          headerBytes: base.loadUInt32(Offset.headerBytes),
                          capacityFrames: base.loadUInt32(Offset.capacityFrames),
                          sampleRate: base.loadUInt32(Offset.sampleRate),
                          channels: base.loadUInt16(Offset.channels),
                          sampleFormat: base.loadUInt16(Offset.sampleFormat),
                          generation: base.loadUInt64(Offset.generation),
                          writeCursor: storage.loadCursor(at: Offset.writeCursor),
                          readCursor: storage.loadCursor(at: Offset.readCursor),
                          state: State(rawValue: base.loadUInt32(Offset.state)) ?? .failed,
                          asbdChangeCount: base.loadUInt32(Offset.asbdChangeCount),
                          lastWriteAt: base.loadDouble(Offset.lastWriteAt),
                          startedAt: base.loadDouble(Offset.startedAt),
                          lastPTS: PTS(value: Int64(bitPattern: base.loadUInt64(Offset.lastPTSValue)),
                                       timescale: Int32(bitPattern: base.loadUInt32(Offset.lastPTSTimescale)),
                                       flags: base.loadUInt32(Offset.lastPTSFlags)),
                          lastAsbdChangeAt: base.loadDouble(Offset.lastAsbdChangeAt),
                          sourceASBD: asbd,
                          droppedInputFrames: base.loadUInt64(Offset.droppedInputFrames),
                          micBuffersSeen: base.loadUInt64(Offset.micBuffersSeen),
                          overrunCount: base.loadUInt64(Offset.overrunCount),
                          peakLevel1s: base.loadFloat(Offset.peakLevel1s),
                          rmsLevel1s: base.loadFloat(Offset.rmsLevel1s),
                          writerPID: base.loadUInt32(Offset.writerPID))
    }

    /// Writes every field; cursors go through the storage accessors, the magic is written first. Used by `RingWriter.begin`.
    func write(to storage: any RingStorage) {
        let base = storage.base
        let magicBytes = Array(magic.utf8.prefix(8))
        for index in 0 ..< 8 {
            base.storeBytes(of: index < magicBytes.count ? magicBytes[index] : 0, toByteOffset: Offset.magic + index, as: UInt8.self)
        }
        base.storeUInt32(headerBytes, Offset.headerBytes)
        base.storeUInt32(capacityFrames, Offset.capacityFrames)
        base.storeUInt32(sampleRate, Offset.sampleRate)
        base.storeUInt16(channels, Offset.channels)
        base.storeUInt16(sampleFormat, Offset.sampleFormat)
        base.storeUInt64(generation, Offset.generation)
        storage.storeCursor(writeCursor, at: Offset.writeCursor)
        storage.storeCursor(readCursor, at: Offset.readCursor)
        base.storeUInt32(state.rawValue, Offset.state)
        base.storeUInt32(asbdChangeCount, Offset.asbdChangeCount)
        base.storeDouble(lastWriteAt, Offset.lastWriteAt)
        base.storeDouble(startedAt, Offset.startedAt)
        base.storeUInt64(UInt64(bitPattern: lastPTS.value), Offset.lastPTSValue)
        base.storeUInt32(UInt32(bitPattern: lastPTS.timescale), Offset.lastPTSTimescale)
        base.storeUInt32(lastPTS.flags, Offset.lastPTSFlags)
        base.storeDouble(lastAsbdChangeAt, Offset.lastAsbdChangeAt)
        RingHeader.write(sourceASBD, to: base)
        base.storeUInt64(droppedInputFrames, Offset.droppedInputFrames)
        base.storeUInt64(micBuffersSeen, Offset.micBuffersSeen)
        base.storeUInt64(overrunCount, Offset.overrunCount)
        base.storeFloat(peakLevel1s, Offset.peakLevel1s)
        base.storeFloat(rmsLevel1s, Offset.rmsLevel1s)
        base.storeUInt32(writerPID, Offset.writerPID)
    }

    static func write(_ asbd: ASBD, to base: UnsafeMutableRawPointer) {
        let asbdBase = Offset.sourceASBD
        base.storeDouble(asbd.sampleRate, asbdBase)
        base.storeUInt32(asbd.formatID, asbdBase + 8)
        base.storeUInt32(asbd.formatFlags, asbdBase + 12)
        base.storeUInt32(asbd.bytesPerPacket, asbdBase + 16)
        base.storeUInt32(asbd.framesPerPacket, asbdBase + 20)
        base.storeUInt32(asbd.bytesPerFrame, asbdBase + 24)
        base.storeUInt32(asbd.channelsPerFrame, asbdBase + 28)
        base.storeUInt32(asbd.bitsPerChannel, asbdBase + 32)
        base.storeUInt32(asbd.reserved, asbdBase + 36)
    }
}

public enum RingError: Error, Equatable {
    case badMagic, tooSmall, unsupportedLayout
}

/// The extension's side of the ring. Not Sendable: owned by one thread (the ReplayKit callback thread).
public final class RingWriter {
    private let storage: any RingStorage
    private let layout: RingLayout
    public private(set) var writeCursor: UInt64 = 0
    private var droppedInputFrames: UInt64 = 0
    private var micBuffersSeen: UInt64 = 0
    private var asbdChangeCount: UInt32 = 0
    // 1 s block meter
    private var meterFrames = 0
    private var meterSumSquares: Double = 0
    private var meterPeak: Float = 0

    public init(storage: any RingStorage, layout: RingLayout = .v1) throws {
        guard storage.count >= layout.totalBytes else { throw RingError.tooSmall }
        self.storage = storage
        self.layout = layout
    }

    /// Writes the full header (magic first, cursors zero), bumps generation, state = running.
    public func begin(generation: UInt64, startedAt: Double, asbd: RingHeader.ASBD, pid: UInt32) {
        writeCursor = 0
        droppedInputFrames = 0
        micBuffersSeen = 0
        asbdChangeCount = 0
        meterFrames = 0
        meterSumSquares = 0
        meterPeak = 0
        let header = RingHeader(magic: layout.magic, headerBytes: UInt32(layout.headerBytes),
                                capacityFrames: UInt32(layout.capacityFrames), sampleRate: UInt32(layout.sampleRate),
                                channels: 1, sampleFormat: 1, generation: generation, writeCursor: 0, readCursor: 0,
                                state: .running, asbdChangeCount: 0, lastWriteAt: startedAt, startedAt: startedAt,
                                lastPTS: RingHeader.PTS(), lastAsbdChangeAt: 0, sourceASBD: asbd,
                                droppedInputFrames: 0, micBuffersSeen: 0, overrunCount: 0, peakLevel1s: 0, rmsLevel1s: 0,
                                writerPID: pid)
        header.write(to: storage)
    }

    /// Copies frames at writeCursor % capacity (split at wrap), then stores the cursor, then lastWriteAt/levels.
    /// Returns the new cursor. A run longer than the capacity keeps only its last `capacityFrames` samples.
    public func write(_ frames: UnsafeBufferPointer<Float>, at time: Double, pts: RingHeader.PTS) -> UInt64 {
        let capacity = layout.capacityFrames
        var source = frames
        if source.count > capacity, let baseAddress = frames.baseAddress {
            writeCursor += UInt64(source.count - capacity)
            source = UnsafeBufferPointer(start: baseAddress + (source.count - capacity), count: capacity)
        }
        let data = storage.base + layout.headerBytes
        let count = source.count
        if count > 0, let sourceBase = source.baseAddress {
            let start = Int(writeCursor % UInt64(capacity))
            let firstPart = min(count, capacity - start)
            data.advanced(by: start * MemoryLayout<Float>.size)
                .copyMemory(from: sourceBase, byteCount: firstPart * MemoryLayout<Float>.size)
            if firstPart < count {
                data.copyMemory(from: sourceBase + firstPart, byteCount: (count - firstPart) * MemoryLayout<Float>.size)
            }
            for index in 0 ..< count {
                let sample = source[index]
                meterPeak = max(meterPeak, abs(sample))
                meterSumSquares += Double(sample * sample)
            }
            meterFrames += count
        }
        writeCursor += UInt64(count)
        storage.storeCursor(writeCursor, at: RingHeader.Offset.writeCursor)          // release
        storage.base.storeDouble(time, RingHeader.Offset.lastWriteAt)                // heartbeat
        storage.base.storeUInt64(UInt64(bitPattern: pts.value), RingHeader.Offset.lastPTSValue)
        storage.base.storeUInt32(UInt32(bitPattern: pts.timescale), RingHeader.Offset.lastPTSTimescale)
        storage.base.storeUInt32(pts.flags, RingHeader.Offset.lastPTSFlags)
        if meterFrames >= layout.sampleRate {
            storage.base.storeFloat(meterPeak, RingHeader.Offset.peakLevel1s)
            storage.base.storeFloat(Float((meterSumSquares / Double(meterFrames)).squareRoot()), RingHeader.Offset.rmsLevel1s)
            meterFrames = 0
            meterSumSquares = 0
            meterPeak = 0
        }
        return writeCursor
    }

    public func setState(_ state: RingHeader.State, at time: Double) {
        storage.base.storeUInt32(state.rawValue, RingHeader.Offset.state)
        storage.base.storeDouble(time, RingHeader.Offset.lastWriteAt)
    }

    public func noteFormatChange(_ asbd: RingHeader.ASBD, at time: Double) {
        asbdChangeCount += 1
        RingHeader.write(asbd, to: storage.base)
        storage.base.storeUInt32(asbdChangeCount, RingHeader.Offset.asbdChangeCount)
        storage.base.storeDouble(time, RingHeader.Offset.lastAsbdChangeAt)
    }

    public func noteDroppedInput(frames: Int) {
        droppedInputFrames += UInt64(max(0, frames))
        storage.base.storeUInt64(droppedInputFrames, RingHeader.Offset.droppedInputFrames)
    }

    public func noteMicBuffer() {
        micBuffersSeen += 1
        storage.base.storeUInt64(micBuffersSeen, RingHeader.Offset.micBuffersSeen)
    }
}

// Little-endian field accessors on the header page (offsets are aligned per the layout table).
extension UnsafeMutableRawPointer {
    func loadUInt16(_ offset: Int) -> UInt16 { UInt16(littleEndian: load(fromByteOffset: offset, as: UInt16.self)) }
    func loadUInt32(_ offset: Int) -> UInt32 { UInt32(littleEndian: load(fromByteOffset: offset, as: UInt32.self)) }
    func loadUInt64(_ offset: Int) -> UInt64 { UInt64(littleEndian: load(fromByteOffset: offset, as: UInt64.self)) }
    func loadDouble(_ offset: Int) -> Double { Double(bitPattern: loadUInt64(offset)) }
    func loadFloat(_ offset: Int) -> Float { Float(bitPattern: loadUInt32(offset)) }
    func storeUInt16(_ value: UInt16, _ offset: Int) { storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt16.self) }
    func storeUInt32(_ value: UInt32, _ offset: Int) { storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt32.self) }
    func storeUInt64(_ value: UInt64, _ offset: Int) { storeBytes(of: value.littleEndian, toByteOffset: offset, as: UInt64.self) }
    func storeDouble(_ value: Double, _ offset: Int) { storeUInt64(value.bitPattern, offset) }
    func storeFloat(_ value: Float, _ offset: Int) { storeUInt32(value.bitPattern, offset) }
}
