import Foundation
import Observation
import ReVoxCore

/// M11 §6: the tutorial's model for the Live strip. The same twelve members `LiveViewModel` gives the strip,
/// backed by memory instead of `SettingsStore`, so tapping a demo pill changes no setting; `start()` / `stop()`
/// flip `state` so the pills lock exactly as a session locks them. The voice note is refreshed lazily
/// (`refreshVoiceNote()`, from the page's `onAppear` and from `reset()`) and by the `theySpeak` setter, never in
/// `init`: `AppEnvironment` builds the tutorial on every launch and walking the installed voices is not free.
@MainActor
@Observable
final class OnboardingLiveControls: LiveControlsModel {
    private(set) var state: LiveState = .idle
    var captureMode: CaptureMode = .microphone
    var latencyMode: SegmenterPreset = .balanced
    var ducking: Bool = Settings().ducking
    var voiceVolume: Double = Settings().voiceVolume
    var isTwoWay = false
    var isLearning = false
    var ignoredLanguage: String? = OnboardingDemo.twoWayIgnored
    private(set) var twoWayVoiceNote: String?
    let canChooseYourLanguage = true
    let pinnedSourceNote: String? = nil

    private var storedTheySpeak: String = OnboardingDemo.twoWayTarget

    /// Computed over a stored property rather than `didSet`, so the note follows every change (the `@Observable`
    /// macro and property observers are a corner the repo avoids).
    var theySpeak: String {
        get { storedTheySpeak }
        set {
            storedTheySpeak = newValue
            refreshVoiceNote()
        }
    }

    var isRunning: Bool { state == .running }

    func start() { state = .running }
    func stop() { state = .idle }

    /// The same note Live shows: nil while this iPhone has a voice for the language.
    func refreshVoiceNote() {
        twoWayVoiceNote = LiveViewModel.voiceNote(for: storedTheySpeak)
    }

    /// Every member back to its first value, stopped, with the voice note refreshed for the default language.
    func reset() {
        stop()
        captureMode = .microphone
        latencyMode = .balanced
        ducking = Settings().ducking
        voiceVolume = Settings().voiceVolume
        isTwoWay = false
        isLearning = false
        ignoredLanguage = OnboardingDemo.twoWayIgnored
        theySpeak = OnboardingDemo.twoWayTarget
    }
}
