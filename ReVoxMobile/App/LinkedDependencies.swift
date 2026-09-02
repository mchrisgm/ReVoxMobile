// Importing the third-party modules here makes the CI build prove that the pinned
// WhisperKit and FluidAudio versions resolve and compile for the iOS simulator,
// before any milestone depends on their APIs.
import FluidAudio
import ReVoxCore
import WhisperKit

enum LinkedDependencies {
    static let whisperKitVersion = "1.1.0"
    static let fluidAudioVersion = "0.15.6"
}
