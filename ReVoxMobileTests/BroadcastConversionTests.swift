import XCTest
import AVFAudio
import CoreMedia
import Darwin
import ReVoxCore
@testable import ReVoxMobile

/// §7.2 / §7.3 over fabricated `.audioApp` buffers (§10.2 `BroadcastConversionTests`).
final class BroadcastConversionTests: XCTestCase {
    private static let toneHz = 1_000.0

    private func tone(frames: Int, sampleRate: Double, channels: Int, bigEndian: Bool, offset: Int) throws -> CMSampleBuffer {
        try SampleBufferFactory.int16(frames: frames, sampleRate: sampleRate, channels: channels, bigEndian: bigEndian,
                                      presentationFrame: Int64(offset)) { frame in
            Float(0.5 * sin(2 * .pi * Self.toneHz * Double(offset + frame) / sampleRate))
        }
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for index in 1 ..< samples.count where (samples[index - 1] < 0) != (samples[index] < 0) {
            crossings += 1
        }
        return crossings
    }

    func testConstantsAndTargetFormat() {
        XCTAssertEqual(BroadcastConverter.inputCapacityFrames, 45_192)
        XCTAssertEqual(BroadcastConverter.outputCapacityFrames, 90_448)
        XCTAssertEqual(BroadcastConverter.lowestInputRate, 8_000)
        XCTAssertEqual(BroadcastConverter.targetFormat.sampleRate, 16_000)
        XCTAssertEqual(BroadcastConverter.targetFormat.channelCount, 1)
        XCTAssertEqual(BroadcastConverter.targetFormat.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(BroadcastConverter.targetFormat.isInterleaved)
    }

    func testBigEndianStereo44kBecomes16kMonoFloat() throws {
        let converter = BroadcastConverter()
        var output: [Float] = []
        var totalFrames = 0
        for index in 0 ..< 10 {
            let buffer = try tone(frames: 1_024, sampleRate: 44_100, channels: 2, bigEndian: true, offset: index * 1_024)
            let result = converter.convert(buffer) { run in output.append(contentsOf: run) }
            XCTAssertEqual(result.formatChanged, index == 0)
            if case .converted(let frames) = result.outcome {
                totalFrames += frames
            } else {
                XCTFail("buffer \(index): \(result.outcome)")
            }
        }
        print("MEASUREMENT bigEndian converterAccepted=\(String(describing: converter.converterAcceptedBigEndian)) byteSwap=\(converter.usesByteSwap)")
        XCTAssertEqual(converter.formatChangeCount, 1)
        XCTAssertTrue(converter.usesByteSwap, "big-endian 16-bit always takes the deterministic swap branch (§7.2)")
        XCTAssertEqual(converter.currentASBD?.sampleRate, 44_100)
        XCTAssertEqual(converter.currentASBD?.channelsPerFrame, 2)
        XCTAssertEqual(output.count, totalFrames)
        let expected = (10_240.0 * 16_000 / 44_100).rounded()          // 3 715
        XCTAssertEqual(Double(output.count), expected, accuracy: 64, "10 buffers of 1 024 frames at 44.1 kHz")
        let steady = Array(output.dropFirst(256))
        let peak = steady.map { abs($0) }.max() ?? 0
        XCTAssertEqual(peak, 0.5, accuracy: 0.08, "amplitude survives (garbage from misread endianness would not)")
        let rms = (steady.reduce(0) { $0 + Double($1 * $1) } / Double(steady.count)).squareRoot()
        XCTAssertEqual(rms, 0.354, accuracy: 0.05)
        let crossings = zeroCrossings(steady)
        XCTAssertEqual(Double(crossings), Double(steady.count) / 8, accuracy: Double(steady.count) / 8 * 0.15, "1 kHz at 16 kHz = one crossing every 8 samples")
    }

    func testFormatChangeRebuildsTheConverterAndResetsTheSwap() throws {
        let converter = BroadcastConverter()
        var output: [Float] = []
        _ = converter.convert(try tone(frames: 1_024, sampleRate: 44_100, channels: 2, bigEndian: true, offset: 0)) { output.append(contentsOf: $0) }
        let firstKey = converter.formatKey
        output.removeAll()
        let mono48 = try tone(frames: 960, sampleRate: 48_000, channels: 1, bigEndian: false, offset: 0)
        let result = converter.convert(mono48) { output.append(contentsOf: $0) }
        XCTAssertTrue(result.formatChanged)
        XCTAssertNotEqual(converter.formatKey, firstKey)
        XCTAssertEqual(converter.formatChangeCount, 2)
        XCTAssertFalse(converter.usesByteSwap, "little-endian input needs no swap")
        XCTAssertNil(converter.converterAcceptedBigEndian, "the probe is cleared with the format it described")
        XCTAssertEqual(converter.currentASBD?.sampleRate, 48_000)
        if case .converted(let frames) = result.outcome {
            XCTAssertEqual(Double(frames), 320, accuracy: 40)
        } else {
            XCTFail("\(result.outcome)")
        }
        let again = converter.convert(try tone(frames: 960, sampleRate: 48_000, channels: 1, bigEndian: false, offset: 960)) { _ in }
        XCTAssertFalse(again.formatChanged, "same key: no rebuild")
        XCTAssertEqual(converter.formatChangeCount, 2)
    }

    func testUnsupportedAndOversizedInputAreReportedNotConverted() throws {
        let converter = BroadcastConverter()
        let sixChannels = try SampleBufferFactory.int16(frames: 64, sampleRate: 44_100, channels: 6, bigEndian: false) { _ in 0 }
        let result = converter.convert(sixChannels) { _ in XCTFail("nothing may be emitted") }
        XCTAssertEqual(result.outcome, .formatUnsupported)
        XCTAssertTrue(result.formatChanged)
        let secondTry = converter.convert(sixChannels) { _ in }
        XCTAssertEqual(secondTry.outcome, .formatUnsupported)
        XCTAssertFalse(secondTry.formatChanged, "the unsupported format is remembered; no rebuild per buffer")

        let huge = try SampleBufferFactory.int16(frames: 45_193, sampleRate: 44_100, channels: 1, bigEndian: false) { _ in 0 }
        let oversized = converter.convert(huge) { _ in XCTFail("nothing may be emitted") }
        XCTAssertEqual(oversized.outcome, .tooManyFrames(45_193))
    }

    func testNoAllocationGrowthAcrossAThousandBuffers() throws {
        let converter = BroadcastConverter()
        let buffers = try (0 ..< 8).map { try tone(frames: 1_024, sampleRate: 44_100, channels: 2, bigEndian: true, offset: $0 * 1_024) }
        var sum: Float = 0
        for index in 0 ..< 20 {                                      // warm-up: converter, buffers, first conversions
            _ = converter.convert(buffers[index % buffers.count]) { run in sum += run.first ?? 0 }
        }
        let before = try XCTUnwrap(Self.residentBytes())
        for index in 0 ..< 1_000 {
            _ = converter.convert(buffers[index % buffers.count]) { run in sum += run.first ?? 0 }
        }
        let after = try XCTUnwrap(Self.residentBytes())
        print("MEASUREMENT conversion residentBefore=\(before) residentAfter=\(after) sum=\(sum)")
        XCTAssertLessThan(Int64(after) - Int64(before), 1_048_576, "no per-buffer allocation (§7.3): resident size must not grow by more than 1 MB")
    }

    /// `mach_task_basic_info.resident_size` of this process (§10.2).
    static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
}
