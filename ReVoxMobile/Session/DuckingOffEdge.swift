import Foundation

/// Which mechanism `restore()` applies after the coordinator's hold (§6.8): the deactivation cycle with
/// `.notifyOthersOnDeactivation` (B-off, the documented path and the default) or the options-only `setCategory`
/// with the resident mask (A-off, the measurement candidate of the §6.8 decision table: adopted for both edges only
/// if the on-device measurement shows it un-ducks without a configuration-change notification).
enum DuckingOffEdge: String, Equatable, Sendable {
    case deactivationCycle
    case optionsOnly
}
