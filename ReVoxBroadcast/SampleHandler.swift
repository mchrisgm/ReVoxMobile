import CoreMedia
import Foundation
import ReplayKit
import os
import ReVoxCore

/// The ReVox Broadcast Upload Extension (design spec §7). Forwards other apps' audio (`.audioApp`) as 16 kHz mono
/// Float32 into the App Group ring file and nothing else: no models, no engine, no session, no network, no
/// per-buffer allocation, no Swift concurrency. Everything runs on the single ReplayKit callback thread.
final class SampleHandler: RPBroadcastSampleHandler {
    private static let errorDomain = "REVOXBroadcastErrorDomain"
    private static let logger = Logger(subsystem: "revox.broadcast", category: "extension")
    private static let footprintLogEveryBuffers = 1_300                  // ≈ 30 s of 23 ms buffers (measurement row 8)

    private var mapping: RingFileMapping?
    private var session: BroadcastSession?
    private var records: BroadcastRecordStore?
    private let converter = BroadcastConverter()
    private var formatLogCount = 0
    private var loggedUnsupported = false
    private var buffersSinceFootprintLog = 0

    // MARK: §7.1 flow

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let appGroup = Bundle.main.infoDictionary?["REVOXAppGroup"] as? String else {
            fail(code: 1, "ReVox could not read its App Group", records: nil)
            return
        }
        let records = BroadcastRecordStore(appGroup: appGroup)
        self.records = records
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            fail(code: 2, "ReVox could not find its shared container", records: records)
            return
        }
        do {
            let mapping = try RingFileMapping.openCreating(at: RingFileMapping.ringURL(in: container))
            let storage = MappedRingStorage(mapping: mapping)
            let previousGeneration = max(RingHeader.read(from: storage)?.generation ?? 0, records?.readBroadcastState()?.generation ?? 0)
            let writer = try RingWriter(storage: storage)
            mapping.zeroDataRegion()                                       // §11: nothing from the previous broadcast survives
            self.mapping = mapping
            session = BroadcastSession(writer: writer, records: records, notifiers: .darwin(names: BroadcastNotificationNames(appGroup: appGroup)),
                                       previousGeneration: previousGeneration, pid: getpid(), clock: { Date().timeIntervalSince1970 })
            Self.logger.info("broadcast started generation=\(previousGeneration + 1, privacy: .public) pid=\(getpid(), privacy: .public)")
        } catch {
            Self.logger.error("ring mapping failed: \(String(describing: error), privacy: .public)")
            fail(code: 3, "ReVox could not open its shared audio buffer", records: records)
        }
    }

    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable: Any]) {
        session?.annotated(bundleID: applicationInfo[RPApplicationInfoBundleIdentifierKey] as? String)
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            return
        case .audioMic:
            session?.micBuffer()                                            // ignored and counted (§11)
            return
        case .audioApp:
            break
        @unknown default:
            return
        }
        guard let session else { return }
        autoreleasepool {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let ringPTS = RingHeader.PTS(value: pts.value, timescale: pts.timescale, flags: pts.flags.rawValue)
            let result = converter.convert(sampleBuffer) { run in
                session.write(run, pts: ringPTS)
            }
            if result.formatChanged, let asbd = converter.currentASBD {
                session.formatChanged(asbd)
                logFormat(asbd, framesPerBuffer: CMSampleBufferGetNumSamples(sampleBuffer))
            }
            switch result.outcome {
            case .converted, .empty:
                break
            case .formatUnsupported:
                session.droppedInput(frames: CMSampleBufferGetNumSamples(sampleBuffer))
                if !loggedUnsupported {
                    loggedUnsupported = true
                    Self.logger.error("audioApp format not convertible; dropping input until the format changes")
                }
            case .tooManyFrames(let frames):
                session.droppedInput(frames: frames)
            case .copyFailed(let status):
                session.droppedInput(frames: CMSampleBufferGetNumSamples(sampleBuffer))
                if !loggedUnsupported {
                    loggedUnsupported = true
                    Self.logger.error("CMSampleBufferCopyPCMDataIntoAudioBufferList failed status=\(status, privacy: .public)")
                }
            }
        }
        buffersSinceFootprintLog += 1
        if buffersSinceFootprintLog >= Self.footprintLogEveryBuffers {
            buffersSinceFootprintLog = 0
            logFootprint()
        }
    }

    override func broadcastPaused() {
        session?.paused()
    }

    override func broadcastResumed() {
        converter.reset()                                                   // resampler history (§7.1 step 4)
        session?.resumed()
    }

    override func broadcastFinished() {
        session?.finished()                                                 // state, record, `stopped`; never truncates (§7.1 step 5)
        session = nil
        mapping = nil                                                       // munmap + close in deinit
        Self.logger.info("broadcast finished")
    }

    // MARK: Helpers (nothing here runs per buffer except the counters above)

    /// Real failures only (§7.1 step 6): the record gets `failed` + the reason, iOS shows the description.
    private func fail(code: Int, _ description: String, records: BroadcastRecordStore?) {
        if let session {
            session.failed(reason: description)
        } else if let records {
            var record = BroadcastStateRecord(generation: records.readBroadcastState()?.generation ?? 0, state: .failed,
                                              startedAt: Date().timeIntervalSince1970, writerPID: getpid())
            record.finishedAt = record.startedAt
            record.finishReason = description
            records.write(record)
        }
        session = nil
        mapping = nil
        finishBroadcastWithError(NSError(domain: Self.errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: description]))
    }

    /// The M5 measurement of the real `.audioApp` format (§7.2): `.info` the first time, `.error` on later changes.
    private func logFormat(_ asbd: RingHeader.ASBD, framesPerBuffer: Int) {
        formatLogCount += 1
        let text = "audioApp ASBD sampleRate=\(asbd.sampleRate) formatID=\(asbd.formatID) flags=\(asbd.formatFlags) bytesPerPacket=\(asbd.bytesPerPacket) framesPerPacket=\(asbd.framesPerPacket) bytesPerFrame=\(asbd.bytesPerFrame) channels=\(asbd.channelsPerFrame) bits=\(asbd.bitsPerChannel) framesPerBuffer=\(framesPerBuffer) converterAcceptedBigEndian=\(String(describing: converter.converterAcceptedBigEndian)) swap=\(converter.usesByteSwap)"
        if formatLogCount == 1 {
            Self.logger.info("\(text, privacy: .public)")
        } else {
            Self.logger.error("format change #\(self.formatLogCount, privacy: .public): \(text, privacy: .public)")
        }
    }

    /// `mach_task_basic_info.resident_size` of the extension (measurement rows 8 and 11); every ~30 s, never per buffer.
    private func logFootprint() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let megabytes = Double(info.resident_size) / 1_048_576
        Self.logger.info("footprint residentMB=\(megabytes, format: .fixed(precision: 1), privacy: .public) writtenFrames=\(self.session?.writtenFrames ?? 0, privacy: .public)")
    }
}
