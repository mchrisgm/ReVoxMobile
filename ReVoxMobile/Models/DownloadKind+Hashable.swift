import ReVoxCore

/// `DownloadKind` is `Equatable` in core; the app keys its per-row state by it.
extension DownloadKind: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .whisper(let id):
            hasher.combine(0)
            hasher.combine(id.rawValue)
        case .vad:
            hasher.combine(1)
        case .pocketTTS:
            hasher.combine(2)
        }
    }
}
