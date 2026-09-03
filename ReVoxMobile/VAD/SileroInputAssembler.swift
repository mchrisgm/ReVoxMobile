import Foundation

enum SileroVADError: Error, Equatable, CustomStringConvertible {
    case invalidChunkLength(Int)
    case notLoaded
    case missingFeature(String)
    case badStateLength(Int)

    var description: String {
        switch self {
        case .invalidChunkLength(let count): return "Silero VAD expects 512 samples per chunk, got \(count)"
        case .notLoaded: return "Voice detector failed to load. Re-download it in Models."
        case .missingFeature(let name): return "Silero VAD output \(name) is missing"
        case .badStateLength(let count): return "Silero VAD state must have 128 values, got \(count)"
        }
    }
}

/// The 576-sample window and the LSTM state of the 512-sample export (§6.3): `audio_input` is the last 64
/// samples of the previous chunk (zeros at start) followed by the 512 new samples.
struct SileroInputAssembler: Equatable, Sendable {
    static let contextSamples = 64
    static let chunkSamples = 512
    static let inputSamples = contextSamples + chunkSamples
    static let stateSize = 128

    private(set) var context = [Float](repeating: 0, count: SileroInputAssembler.contextSamples)
    private(set) var hidden = [Float](repeating: 0, count: SileroInputAssembler.stateSize)
    private(set) var cell = [Float](repeating: 0, count: SileroInputAssembler.stateSize)

    mutating func input(for chunk: [Float]) throws -> [Float] {
        guard chunk.count == Self.chunkSamples else { throw SileroVADError.invalidChunkLength(chunk.count) }
        let input = context + chunk
        context = Array(chunk.suffix(Self.contextSamples))
        return input
    }

    mutating func update(hidden: [Float], cell: [Float]) throws {
        guard hidden.count == Self.stateSize else { throw SileroVADError.badStateLength(hidden.count) }
        guard cell.count == Self.stateSize else { throw SileroVADError.badStateLength(cell.count) }
        self.hidden = hidden
        self.cell = cell
    }

    mutating func reset() {
        context = [Float](repeating: 0, count: Self.contextSamples)
        hidden = [Float](repeating: 0, count: Self.stateSize)
        cell = [Float](repeating: 0, count: Self.stateSize)
    }
}
