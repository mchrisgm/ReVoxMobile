import Foundation

/// One row of the live transcript (§8.2): an entry with its language badge, or a muted drop marker.
struct LiveTranscriptRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// `original` is the words as spoken (M9 Learning mode); "" when learning was off for that phrase.
        case entry(language: String, original: String, english: String)
        case dropMarker
        case joinedInProgress                         // muted header: the run attached to a broadcast already in progress (§8.2)

        /// The pre-M9 shape, kept so every existing call site reads unchanged.
        static func entry(language: String, english: String) -> Kind {
            .entry(language: language, original: "", english: english)
        }
    }

    let id: UUID
    let time: Date
    let kind: Kind
    /// M11: a phrase the gates were unsure about (an unsure language, a low average log-probability). Shown greyed,
    /// never spoken, kept in History only when the setting says so. A property rather than an associated value so
    /// every `case .entry(let language, let original, let english)` match in the app and the tests reads unchanged.
    let isGuess: Bool

    init(id: UUID = UUID(), time: Date, kind: Kind, isGuess: Bool = false) {
        self.id = id
        self.time = time
        self.kind = kind
        self.isGuess = isGuess
    }
}
