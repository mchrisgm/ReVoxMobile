import Foundation
import Observation
import ReVoxCore

/// State behind the Voices screen (§8.4): the pocket-tts row (download / voices / delete / sample) and the English
/// system voices; selection writes R11's `voice` and `systemVoiceIdentifier`, which `SpeakerAssembly.selection()`
/// reads at the next Start or sample.
@MainActor
@Observable
final class VoicesViewModel {
    static let sampleText = "This is ReVox."
    static let engineFooterText = "ReVox uses the system voice until pocket-tts is downloaded, and falls back to it automatically if pocket-tts fails."
    static let stopToDeleteText = "Stop translation to delete voices"
    static let stopToPlaySampleText = "Stop translation to play a sample"
    /// M10: verifying pocket-tts loads it; beside a running session that is a second model resident (§9).
    static let stopToDownloadText = "Stop translation to download voices"
    static let confirmDeleteMessage = "ReVox will use the system voice until you download it again."
    static let pocketTTSName = "pocket-tts"
    static let systemVoiceValue = "system"

    static var pocketTTSSizeText: String { ModelsViewModel.sizeText(ModelCatalog.pocketTTS.approximateBytes) }
    static var confirmDeleteTitle: String { "Delete \(pocketTTSName) (\(pocketTTSSizeText))?" }

    /// M10: the not-installed row's caption, with the voice list read from the catalog rather than typed in.
    static var downloadRowDescription: String {
        "\(voiceListText(ModelCatalog.pocketTTS.offeredVoices)) Downloaded on demand; the system voice is used until then."
    }

    /// "Voices alba, azelma, cosette and javert." for the catalog's list; degrades sensibly for one or none.
    static func voiceListText(_ voices: [String]) -> String {
        switch voices.count {
        case 0: return "No voices."
        case 1: return "Voice \(voices[0])."
        default: return "Voices \(voices.dropLast().joined(separator: ", ")) and \(voices[voices.count - 1])."
        }
    }

    private let manager: ModelManager
    private let settings: SettingsStore
    private let memoryTierGB: Int
    private let speakerStatus: SpeakerStatusRelay
    private let samplePlayer: SamplePlayer
    private let selection: @MainActor () async -> SpeakerSelection
    private let systemVoiceSource: () -> [SystemVoiceOption]
    private let isPipelineRunning: @MainActor () -> Bool

    private(set) var isPlayingSample = false
    private(set) var systemVoices: [SystemVoiceOption]
    var sampleError: String?
    var lowStorageAlert: String?
    /// A delete the manager refused — the pipeline started while the confirmation dialog was open (§6.9).
    var deleteFailureAlert: String?
    var lowStorageWarning: String?
    var downloadFailureAlert: String?
    /// M10: the "Can't download now" alert; only the running-session refusal produces it.
    var downloadRefusedAlert: String?
    @ObservationIgnored private var awaitingUserResult = false

    init(manager: ModelManager, settings: SettingsStore, deviceInfo: DeviceInfo, speakerStatus: SpeakerStatusRelay,
         samplePlayer: SamplePlayer, selection: @escaping @MainActor () async -> SpeakerSelection,
         systemVoices: @escaping () -> [SystemVoiceOption] = SystemVoiceOption.installedEnglishVoices,
         isPipelineRunning: @escaping @MainActor () -> Bool) {
        self.manager = manager
        self.settings = settings
        self.memoryTierGB = deviceInfo.memoryTierGB
        self.speakerStatus = speakerStatus
        self.samplePlayer = samplePlayer
        self.selection = selection
        self.systemVoiceSource = systemVoices
        self.isPipelineRunning = isPipelineRunning
        // §6.6: the screen's order is the view model's responsibility, not the source's. `sorted(_:)` is idempotent on
        // the already-sorted output of `installedEnglishVoices()`, and orders any other source (tests, a future source).
        self.systemVoices = SystemVoiceOption.sorted(systemVoices())
    }

    // MARK: pocket-tts

    var pocketTTSState: ModelDownloadState { manager.state(for: .pocketTTS) }
    var isPocketTTSInstalled: Bool { manager.pocketTTSInstalled }
    var offeredVoices: [String] { ModelCatalog.pocketTTS.offeredVoices }

    /// The catalog estimate before the download, the measured size once installed (§8.4; §6.9 storage accounting, M7).
    var pocketTTSSizeLine: String {
        if isPocketTTSInstalled, let bytes = manager.storage.bytes(for: .pocketTTS) {
            return ModelsViewModel.measuredSizeText(bytes)
        }
        return Self.pocketTTSSizeText
    }

    var storageFooterText: String { ModelsViewModel.storageFooterText(for: manager.storage) }

    /// §11: pocket-tts is downloaded from FluidAudio's `main`; a changed file set is captioned in the footer.
    var pocketTTSNoticeText: String? { manager.upstreamChangeText(for: .pocketTTS) }

    /// The checkmarked pocket-tts voice, nil when the system voice is selected.
    var selectedPocketVoice: String? {
        settings.settings.usesPocketTTSVoice ? settings.settings.voice : nil
    }

    /// §5.6: shown below the 6 GB tier; never a gate.
    var advisoryText: String? { DeviceRecommendation.pocketTTSAdvisory(memoryTierGB: memoryTierGB) }

    /// The same text as the Live status line (§8.2): which engine speaks and why.
    var statusText: String { speakerStatus.text }

    /// §9: a pocket-tts load or synthesis failure shows Retry here.
    var showsRetry: Bool { speakerStatus.status.isFallback }

    var canDelete: Bool { isPocketTTSInstalled && !isPipelineRunning() }
    var canPlaySample: Bool { !isPipelineRunning() && !isPlayingSample }
    var canDownload: Bool { !isPipelineRunning() }

    /// M10: why Play sample is disabled, for the caption under it (a disabled control never goes unexplained).
    /// nil while a sample plays: the spinner beside the button is the reason then.
    var sampleUnavailableReason: String? { isPipelineRunning() ? Self.stopToPlaySampleText : nil }

    var footerText: String? {
        if manager.hasActiveDownload || !manager.pausedKinds.isEmpty { return ModelsViewModel.keepOpenText }
        if isPocketTTSInstalled && isPipelineRunning() { return Self.stopToDeleteText }
        return nil
    }

    func download() {
        lowStorageWarning = nil
        guard canDownload else {
            downloadRefusedAlert = Self.stopToDownloadText
            return
        }
        switch manager.freeSpaceVerdict(for: .pocketTTS) {
        case .refuse(let message):
            lowStorageAlert = message
            return
        case .lowRemaining(let remaining):
            lowStorageWarning = "Only \(ModelManager.gigabytesText(remaining)) will remain after this download"
        case .ok:
            break
        }
        awaitingUserResult = true
        manager.install(.pocketTTS)
    }

    func cancel() {
        awaitingUserResult = false
        manager.cancel(.pocketTTS)
    }

    /// Same policy as `ModelsViewModel.reconcileFailures()` (§8.8) for the single pocket-tts row.
    func reconcileFailures() {
        guard awaitingUserResult else { return }
        switch pocketTTSState.phase {
        case .failed(let message):
            awaitingUserResult = false
            downloadFailureAlert = ModelsViewModel.downloadFailureText(name: Self.pocketTTSName, message: message)
        case .installed, .idle, .paused:
            awaitingUserResult = false
        case .listing, .downloading, .compiling, .verifying:
            break
        }
    }

    /// What the confirmation dialog calls; a refusal becomes the "Can't delete now" alert instead of a storage alert.
    func deleteConfirmed() {
        deleteFailureAlert = nil
        do {
            try delete()
        } catch {
            deleteFailureAlert = Self.deleteFailureText(error)
        }
    }

    /// M10: the manager's refusal is worded for the Models screen ("… delete models"); on this screen the footer
    /// says "… delete voices", and the alert must say the same. Every other error prints itself.
    static func deleteFailureText(_ error: Error) -> String {
        if let refusal = error as? ModelManagerError, refusal == .pipelineRunning { return stopToDeleteText }
        return ModelsViewModel.deleteFailureText(error)
    }

    /// Behind the screen's `confirmationDialog`; refused while the pipeline runs (§6.9). The voice setting is kept.
    func delete() throws {
        try manager.delete(.pocketTTS, activeModel: settings.settings.whisperModel)
    }

    func selectPocketVoice(_ voice: String) {
        guard offeredVoices.contains(voice) else { return }
        settings.update { $0.voice = voice }
    }

    /// Idle only (§8.4). Prepares the effective speaker with the current selection, so the status line updates and a
    /// pocket-tts failure surfaces here as a fallback status with Retry.
    func playSample() async {
        guard canPlaySample else { return }
        isPlayingSample = true
        sampleError = nil
        defer { isPlayingSample = false }
        let chosen = await selection()
        do {
            try await samplePlayer.play(chosen, Self.sampleText)
        } catch {
            sampleError = String(describing: error)
        }
    }

    func retryPocketTTS() async {
        await playSample()
    }

    // MARK: System voices

    var selectedSystemVoiceIdentifier: String? {
        isSystemVoiceSelected ? settings.settings.systemVoiceIdentifier : nil
    }

    var isSystemVoiceSelected: Bool { !settings.settings.usesPocketTTSVoice }

    /// Called on appear: the list changes when the user installs a voice in Settings > Accessibility. Sorted here for
    /// the same reason as in `init`: `VoicesView` renders `ForEach(model.systemVoices)` verbatim (§6.6).
    func refreshSystemVoices() {
        systemVoices = SystemVoiceOption.sorted(systemVoiceSource())
    }

    func selectSystemVoice(_ option: SystemVoiceOption) {
        settings.update {
            $0.voice = Self.systemVoiceValue
            $0.systemVoiceIdentifier = option.id
        }
    }
}
