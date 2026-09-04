import AVFAudio
import CoreMedia
import Foundation

enum SampleBufferFactoryError: Error {
    case status(OSStatus, String)
}

/// Fabricates the `.audioApp` buffers ReplayKit delivers (community-measured: 44.1 kHz, SInt16 interleaved,
/// 1–2 channels, big-endian, 1 024 frames) without ReplayKit, so the converter is tested in the simulator.
enum SampleBufferFactory {
    static func int16(frames: Int, sampleRate: Double, channels: Int, bigEndian: Bool, presentationFrame: Int64 = 0,
                      sample: (Int) -> Float) throws -> CMSampleBuffer {
        var flags = AudioFormatFlags(kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked)
        if bigEndian { flags |= AudioFormatFlags(kAudioFormatFlagIsBigEndian) }
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0
        )
        var bytes = [UInt8]()
        bytes.reserveCapacity(frames * channels * 2)
        for frame in 0 ..< frames {
            let value = Int16(max(-32_768, min(32_767, (Double(sample(frame)) * 32_767).rounded())))
            // `.bigEndian` byte-swaps on a little-endian host, so writing low byte first lays the value out big-endian.
            let pattern = bigEndian ? UInt16(bitPattern: value).bigEndian : UInt16(bitPattern: value).littleEndian
            for _ in 0 ..< channels {
                bytes.append(UInt8(truncatingIfNeeded: pattern))
                bytes.append(UInt8(truncatingIfNeeded: pattern >> 8))
            }
        }
        var description: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else { throw SampleBufferFactoryError.status(status, "format description") }
        var blockBuffer: CMBlockBuffer?
        status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
                                                    blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                    dataLength: bytes.count, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let blockBuffer else { throw SampleBufferFactoryError.status(status, "block buffer") }
        status = bytes.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard status == noErr else { throw SampleBufferFactoryError.status(status, "replace bytes") }
        var sampleBuffer: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: description, sampleCount: frames,
            presentationTimeStamp: CMTime(value: presentationFrame, timescale: CMTimeScale(sampleRate)), packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { throw SampleBufferFactoryError.status(status, "sample buffer") }
        return sampleBuffer
    }
}
