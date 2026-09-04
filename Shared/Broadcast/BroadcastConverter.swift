import AVFAudio
import CoreMedia
import Foundation
import ReVoxCore

/// The fields whose change rebuilds the converter (§7.2).
struct SourceFormatKey: Equatable, Sendable {
    let sampleRate: Double
    let channels: UInt32
    let flags: UInt32
    let bitsPerChannel: UInt32
    let bytesPerFrame: UInt32
    let framesPerPacket: UInt32

    init(_ asbd: AudioStreamBasicDescription) {
        sampleRate = asbd.mSampleRate
        channels = asbd.mChannelsPerFrame
        flags = asbd.mFormatFlags
        bitsPerChannel = asbd.mBitsPerChannel
        bytesPerFrame = asbd.mBytesPerFrame
        framesPerPacket = asbd.mFramesPerPacket
    }
}

enum BroadcastConversionOutcome: Equatable {
    case converted(frames: Int)
    case formatUnsupported                 // non-PCM, > 2 channels, below 8 kHz, or the converter refused the format
    case tooManyFrames(Int)                // larger than the preallocated input buffer
    case copyFailed(OSStatus)
    case empty
}

struct BroadcastConversionResult: Equatable {
    var outcome: BroadcastConversionOutcome
    var formatChanged: Bool
}

/// `.audioApp` → 16 kHz mono Float32 with the allocation strategy of §7.3: the input buffer, the output buffer,
/// the converter and the input block are created per format, never per buffer. Not Sendable: owned by the single
/// ReplayKit callback thread (§7.3) — or, in the app's tests, by one test.
final class BroadcastConverter {
    static let inputCapacityFrames: AVAudioFrameCount = 45_192                // largest community-observed slice
    static let lowestInputRate: Double = 8_000
    static let outputCapacityFrames: AVAudioFrameCount = 90_448               // ceil(45 192 × 16 000 / 8 000) + 64
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    private(set) var formatKey: SourceFormatKey?
    private(set) var currentASBD: RingHeader.ASBD?
    private(set) var formatChangeCount = 0
    private(set) var usesByteSwap = false
    /// nil until a big-endian format is described; then whether `AVAudioConverter.init` accepted that description.
    /// A measurement only (M5 row 5) — the samples are swapped by hand either way, see `rebuild(for:key:)`.
    private(set) var converterAcceptedBigEndian: Bool?

    private var converter: AVAudioConverter?
    private var inputBuffer: AVAudioPCMBuffer?
    private let outputBuffer: AVAudioPCMBuffer
    private var inputHandedOver = false
    private var inputBlock: AVAudioConverterInputBlock?

    init() {
        outputBuffer = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: Self.outputCapacityFrames)!
    }

    static func snapshot(_ asbd: AudioStreamBasicDescription) -> RingHeader.ASBD {
        RingHeader.ASBD(sampleRate: asbd.mSampleRate, formatID: asbd.mFormatID, formatFlags: asbd.mFormatFlags,
                        bytesPerPacket: asbd.mBytesPerPacket, framesPerPacket: asbd.mFramesPerPacket, bytesPerFrame: asbd.mBytesPerFrame,
                        channelsPerFrame: asbd.mChannelsPerFrame, bitsPerChannel: asbd.mBitsPerChannel, reserved: asbd.mReserved)
    }

    /// Drops the resampler history (`broadcastResumed`, §7.1 step 4).
    func reset() {
        converter?.reset()
    }

    func convert(_ sampleBuffer: CMSampleBuffer, sink: (UnsafeBufferPointer<Float>) -> Void) -> BroadcastConversionResult {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return BroadcastConversionResult(outcome: .formatUnsupported, formatChanged: false)
        }
        let asbd = asbdPointer.pointee
        let key = SourceFormatKey(asbd)
        var formatChanged = false
        if key != formatKey {
            formatChanged = true
            rebuild(for: asbd, key: key)
        }
        guard let converter, let inputBuffer, let inputBlock else {
            return BroadcastConversionResult(outcome: .formatUnsupported, formatChanged: formatChanged)
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return BroadcastConversionResult(outcome: .empty, formatChanged: formatChanged) }
        guard frames <= Int(Self.inputCapacityFrames) else {
            return BroadcastConversionResult(outcome: .tooManyFrames(frames), formatChanged: formatChanged)
        }
        inputBuffer.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: inputBuffer.mutableAudioBufferList)
        guard status == noErr else { return BroadcastConversionResult(outcome: .copyFailed(status), formatChanged: formatChanged) }
        if usesByteSwap {
            Self.swapInt16InPlace(inputBuffer)
        }
        inputHandedOver = false
        var produced = 0
        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let outputStatus = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if outputStatus == .error {
                return BroadcastConversionResult(outcome: .formatUnsupported, formatChanged: formatChanged)
            }
            let count = Int(outputBuffer.frameLength)
            if count > 0, let channel = outputBuffer.floatChannelData?[0] {
                sink(UnsafeBufferPointer(start: channel, count: count))
                produced += count
            }
            // `.inputRanDry` (the converter drained this buffer) or a `.haveData` that produced nothing: either way
            // the input block has already said `.noDataNow`, so a further pass cannot produce more. `count == 0`
            // is what makes the loop provably terminate.
            if outputStatus != .haveData || count == 0 {
                break
            }
        }
        return BroadcastConversionResult(outcome: .converted(frames: produced), formatChanged: formatChanged)
    }

    /// A big-endian source is *always* decoded by clearing the flag and swapping the samples ourselves, even when
    /// `AVAudioConverter` accepts the big-endian description. The two paths cannot both be verified from here: a
    /// converter that accepts the flag and then reads the bytes the other way round produces plausible-looking
    /// noise, and in the extension that surfaces half an hour into a locked-phone session as untranslatable audio,
    /// with no way to tell it from a bad microphone. The swap is a few thousand `byteSwapped` per buffer and its
    /// output is asserted sample-by-sample in `BroadcastConversionTests`. `converterAcceptedBigEndian` still
    /// records what the framework said, which is the question M5 row 5 asks.
    private func rebuild(for asbd: AudioStreamBasicDescription, key: SourceFormatKey) {
        formatKey = key
        currentASBD = Self.snapshot(asbd)
        formatChangeCount += 1
        converter = nil
        inputBuffer = nil
        inputBlock = nil
        usesByteSwap = false
        converterAcceptedBigEndian = nil
        guard asbd.mFormatID == kAudioFormatLinearPCM, (1 ... 2).contains(asbd.mChannelsPerFrame),
              asbd.mSampleRate >= Self.lowestInputRate else { return }

        var description = asbd
        var swap = false
        if asbd.mFormatFlags & AudioFormatFlags(kAudioFormatFlagIsBigEndian) != 0 {
            var probe = asbd
            if let bigEndianFormat = AVAudioFormat(streamDescription: &probe) {
                converterAcceptedBigEndian = AVAudioConverter(from: bigEndianFormat, to: Self.targetFormat) != nil
            } else {
                converterAcceptedBigEndian = false
            }
            if asbd.mBitsPerChannel == 16 {
                // The Twilio approach (§7.2): describe the input as little-endian and swap the samples ourselves.
                description.mFormatFlags &= ~AudioFormatFlags(kAudioFormatFlagIsBigEndian)
                swap = true
            }
        }
        guard let format = AVAudioFormat(streamDescription: &description), let built = AVAudioConverter(from: format, to: Self.targetFormat) else { return }
        usesByteSwap = swap
        install(converter: built, format: format)
    }

    private func install(converter built: AVAudioConverter, format: AVAudioFormat) {
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.inputCapacityFrames) else { return }
        converter = built
        inputBuffer = input
        // Stored once per format (§7.3); hands the input buffer over exactly once per `convert` call.
        inputBlock = { [unowned self] _, status in
            if self.inputHandedOver {
                status.pointee = .noDataNow
                return nil
            }
            self.inputHandedOver = true
            status.pointee = .haveData
            return self.inputBuffer
        }
    }

    private static func swapInt16InPlace(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.int16ChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        if buffer.format.isInterleaved {
            let pointer = channels[0]
            for index in 0 ..< frames * channelCount {
                pointer[index] = pointer[index].byteSwapped
            }
        } else {
            for channel in 0 ..< channelCount {
                let pointer = channels[channel]
                for index in 0 ..< frames {
                    pointer[index] = pointer[index].byteSwapped
                }
            }
        }
    }
}
