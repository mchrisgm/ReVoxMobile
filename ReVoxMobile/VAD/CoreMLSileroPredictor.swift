import CoreML
import Foundation

typealias SileroPrediction = (probability: Float, hidden: [Float], cell: [Float])

/// One `MLModel` over the 512-sample bundle with preallocated inputs; feature names as in the bundle's
/// `model.mil` (`audio_input`, `hidden_state`, `cell_state`, `vad_output`, `new_hidden_state`, `new_cell_state`).
/// Never handed to FluidAudio's `VadManager` (it would build 4 160-sample inputs, R1).
final class CoreMLSileroPredictor: @unchecked Sendable {
    static let audioInputName = "audio_input"
    static let hiddenStateName = "hidden_state"
    static let cellStateName = "cell_state"
    static let vadOutputName = "vad_output"
    static let newHiddenStateName = "new_hidden_state"
    static let newCellStateName = "new_cell_state"

    private let model: MLModel
    private let audioInput: MLMultiArray
    private let hiddenState: MLMultiArray
    private let cellState: MLMultiArray

    init(model: MLModel) throws {
        self.model = model
        audioInput = try MLMultiArray(shape: [1, NSNumber(value: SileroInputAssembler.inputSamples)], dataType: .float32)
        hiddenState = try MLMultiArray(shape: [1, NSNumber(value: SileroInputAssembler.stateSize)], dataType: .float32)
        cellState = try MLMultiArray(shape: [1, NSNumber(value: SileroInputAssembler.stateSize)], dataType: .float32)
    }

    func predict(input: [Float], hidden: [Float], cell: [Float]) throws -> SileroPrediction {
        Self.fill(audioInput, with: input)
        Self.fill(hiddenState, with: hidden)
        Self.fill(cellState, with: cell)
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.audioInputName: audioInput,
            Self.hiddenStateName: hiddenState,
            Self.cellStateName: cellState,
        ])
        let output = try model.prediction(from: provider)
        let probabilityArray = try Self.feature(named: Self.vadOutputName, in: output)
        let newHidden = try Self.feature(named: Self.newHiddenStateName, in: output)
        let newCell = try Self.feature(named: Self.newCellStateName, in: output)
        return (
            probability: probabilityArray.dataPointer.assumingMemoryBound(to: Float.self)[0],
            hidden: Self.floats(newHidden, count: SileroInputAssembler.stateSize),
            cell: Self.floats(newCell, count: SileroInputAssembler.stateSize)
        )
    }

    private static func fill(_ array: MLMultiArray, with values: [Float]) {
        let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
        let count = min(values.count, array.count)
        values.withUnsafeBufferPointer { source in
            pointer.update(from: source.baseAddress!, count: count)
        }
    }

    private static func floats(_ array: MLMultiArray, count: Int) -> [Float] {
        let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: pointer, count: min(count, array.count)))
    }

    /// Exact name first, then a case-insensitive substring match (exports may suffix output names).
    private static func feature(named name: String, in provider: MLFeatureProvider) throws -> MLMultiArray {
        if let value = provider.featureValue(for: name)?.multiArrayValue {
            return value
        }
        let target = name.lowercased()
        if let match = provider.featureNames.first(where: { $0.lowercased().contains(target) }),
           let value = provider.featureValue(for: match)?.multiArrayValue {
            return value
        }
        throw SileroVADError.missingFeature(name)
    }
}
