import Foundation

/// Platform-independent logic shared by the ReVox iOS app and its broadcast extension.
///
/// Everything in this module depends on Foundation only, so `swift test` runs on Linux
/// as well as inside the iOS simulator.
public enum ReVoxCore {
    /// Sample rate, in Hz, that every pipeline stage works at.
    public static let sampleRate = 16_000
}
