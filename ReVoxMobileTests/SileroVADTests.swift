import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class SileroVADTests: XCTestCase {
    func testShapesMatchTheExport() {
        XCTAssertEqual(SileroInputAssembler.contextSamples, 64)
        XCTAssertEqual(SileroInputAssembler.chunkSamples, Segmenter.chunkSamples)
        XCTAssertEqual(SileroInputAssembler.inputSamples, 576)
        XCTAssertEqual(SileroInputAssembler.stateSize, 128)
    }

    func testFirstInputIsZeroContextThenChunkAndContextCarriesTheLast64Samples() throws {
        var assembler = SileroInputAssembler()
        let first = (0..<512).map { Float($0) }
        let input1 = try assembler.input(for: first)
        XCTAssertEqual(input1.count, 576)
        XCTAssertEqual(Array(input1[0..<64]), [Float](repeating: 0, count: 64))
        XCTAssertEqual(Array(input1[64...]), first)

        let second = [Float](repeating: -1, count: 512)
        let input2 = try assembler.input(for: second)
        XCTAssertEqual(Array(input2[0..<64]), Array(first[448..<512]), "context = last 64 samples of the previous chunk")
        XCTAssertEqual(Array(input2[64...]), second)
    }

    func testWrongChunkLengthIsRejected() {
        var assembler = SileroInputAssembler()
        XCTAssertThrowsError(try assembler.input(for: [Float](repeating: 0, count: 511))) { error in
            XCTAssertEqual(error as? SileroVADError, .invalidChunkLength(511))
        }
    }

    func testStatesAreCarriedBetweenCallsAndClearedByReset() async throws {
        let calls = LockedBox<[(hidden: Float, cell: Float)]>([])
        let vad = SileroVAD(predictor: { input, hidden, cell in
            calls.mutate { $0.append((hidden[0], cell[0])) }
            let level = input[64...].reduce(0) { $0 + abs($1) } / 512
            return (probability: level > 0.1 ? 0.9 : 0.05,
                    hidden: [Float](repeating: hidden[0] + 1, count: 128),
                    cell: [Float](repeating: cell[0] + 2, count: 128))
        })
        let loud = [Float](repeating: 0.5, count: 512)
        let quiet = [Float](repeating: 0, count: 512)
        let p1 = try await vad.probability(of: loud)
        let p2 = try await vad.probability(of: quiet)
        XCTAssertEqual(p1, 0.9)
        XCTAssertEqual(p2, 0.05)
        await vad.reset()
        _ = try await vad.probability(of: quiet)
        let seen = calls.value
        XCTAssertEqual(seen.map(\.hidden), [0, 1, 0], "hidden state carried, then zeroed by reset()")
        XCTAssertEqual(seen.map(\.cell), [0, 2, 0])
    }

    func testBadStateLengthFromThePredictorIsAnError() async {
        let vad = SileroVAD(predictor: { _, _, _ in (probability: 0.5, hidden: [0], cell: [0]) })
        do {
            _ = try await vad.probability(of: [Float](repeating: 0, count: 512))
            XCTFail("expected badStateLength")
        } catch {
            XCTAssertEqual(error as? SileroVADError, .badStateLength(1))
        }
    }

    func testUnloadedBundleWrapperThrowsNotLoaded() async {
        let vad = SileroVAD(bundleURL: FileManager.default.temporaryDirectory.appendingPathComponent("missing.mlmodelc"))
        let loaded = await vad.isLoaded
        XCTAssertFalse(loaded)
        do {
            _ = try await vad.probability(of: [Float](repeating: 0, count: 512))
            XCTFail("expected notLoaded")
        } catch {
            XCTAssertEqual(error as? SileroVADError, .notLoaded)
        }
    }
}

/// Minimal lock-guarded box for values written from `@Sendable` closures.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout Value) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}
