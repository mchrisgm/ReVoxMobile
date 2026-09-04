import Foundation
import ReVoxCore

/// Which model ReVox drops to when the selected one cannot be loaded (§9 row 1) or when the device asks for less
/// (§9 memory and thermal rows). Catalog order is the size order: tiny, base, small, medium, large-v3.
enum ModelFallback {
    /// The largest installed model strictly smaller than `id`; nil when nothing smaller is installed.
    static func smallerInstalledModel(than id: WhisperModelID, installed: [WhisperModelID]) -> WhisperModelID? {
        let order = ModelCatalog.whisperModels.map(\.id)
        guard let index = order.firstIndex(of: id) else { return nil }
        return order[..<index].last { installed.contains($0) }
    }
}
