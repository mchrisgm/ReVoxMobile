import Foundation

/// Which mechanism `duck()` applies on the speaking-true edge (§6.8): the options-only `setCategory` that R8
/// prescribes (A-on, the default) or the full deactivation cycle (B-on), the fallback for the case where the
/// on-device measurement shows A-on does not duck. The off-edge is always the deactivation cycle with
/// `.notifyOthersOnDeactivation` (B-off).
enum DuckingOnEdge: String, Equatable, Sendable {
    case optionsOnly
    case fullCycle
}
