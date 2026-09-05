import Observation
import ReVoxCore

/// M11 §1: what the control strip and its groups read and write — `LiveViewModel` on the Live tab, a small demo
/// class in the tutorial (§6), so the tutorial hosts the real controls instead of imitating them. Every member is
/// one the strip already used; the three M11 additions (`theySpeak`, `canChooseYourLanguage`, `pinnedSourceNote`)
/// are documented on `LiveViewModel`.
@MainActor
protocol LiveControlsModel: AnyObject, Observable {
    var state: LiveState { get }
    var captureMode: CaptureMode { get set }
    var latencyMode: SegmenterPreset { get set }
    var ducking: Bool { get set }
    var voiceVolume: Double { get set }
    var isTwoWay: Bool { get set }
    var isLearning: Bool { get set }
    var ignoredLanguage: String? { get set }
    var theySpeak: String { get set }
    var twoWayVoiceNote: String? { get }
    var canChooseYourLanguage: Bool { get }
    var pinnedSourceNote: String? { get }
}

extension LiveViewModel: LiveControlsModel {}
