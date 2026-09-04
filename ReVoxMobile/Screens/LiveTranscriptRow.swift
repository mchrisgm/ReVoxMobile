import Foundation

/// One row of the live transcript (§8.2): an entry with its language badge, or a muted drop marker.
struct LiveTranscriptRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case entry(language: String, english: String)
        case dropMarker
        case joinedInProgress                         // muted header: the run attached to a broadcast already in progress (§8.2)
    }

    let id: UUID
    let time: Date
    let kind: Kind

    init(id: UUID = UUID(), time: Date, kind: Kind) {
        self.id = id
        self.time = time
        self.kind = kind
    }
}
