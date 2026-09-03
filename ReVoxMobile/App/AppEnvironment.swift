import AVFAudio
import Foundation
import SwiftData
import ReVoxCore

/// Everything the app owns for its lifetime, built once at launch (§6.9, §6.11) or, for tests, over a temporary root.
@MainActor
final class AppEnvironment {
    let configuration: AppConfiguration
    let deviceInfo: DeviceInfo
    let settings: SettingsStore
    let layout: ModelLayout
    let installer: ModelInstaller
    let modelManager: ModelManager
    let sessionController: AudioSessionController
    let interruptions: InterruptionObserver
    let transcriptContainer: ModelContainer
    let mute: PlaybackMute
    let signals: DeviceSignals
    let assembler: PipelineAssembler
    let live: LiveViewModel
    let models: ModelsViewModel
    let settingsModel: SettingsViewModel
    private var interruptionTask: Task<Void, Never>?

    /// Breaks the manager ↔ live-view-model cycle: the manager asks whether the pipeline is busy through this box.
    /// `@MainActor` is required: a nested type does not inherit the enclosing class's isolation, and `isBusy` reads
    /// `LiveViewModel.state`, which is main-actor isolated (Task 35).
    @MainActor
    private final class LiveActivity {
        weak var live: LiveViewModel?
        var isBusy: Bool {
            guard let live else { return false }
            return live.state == .running || live.state == .preparing
        }
    }

    init(configuration: AppConfiguration, deviceInfo: DeviceInfo, settingsURL: URL, modelRoot: URL, transcriptContainer: ModelContainer,
         sessionSeam: any AudioSessionSeam, installSteps: InstallSteps, installHost: any InstallHost, verifiedLoads: VerifiedLoadRecord,
         permission: MicrophonePermission) throws {
        self.configuration = configuration
        self.deviceInfo = deviceInfo
        self.settings = SettingsStore(fileURL: settingsURL)
        self.layout = ModelLayout(root: modelRoot)
        try ModelLayout.excludeFromBackup(modelRoot)
        self.installer = ModelInstaller(layout: layout, steps: installSteps, verifiedLoads: verifiedLoads)
        self.transcriptContainer = transcriptContainer
        self.sessionController = AudioSessionController(session: sessionSeam)
        self.interruptions = InterruptionObserver()
        self.mute = PlaybackMute()
        self.signals = DeviceSignals()
        let activity = LiveActivity()
        self.modelManager = ModelManager(layout: layout, installer: installer, isPipelineRunning: { activity.isBusy }, availableBytes: nil, host: installHost)
        self.assembler = PipelineAssembler(layout: layout, sessionController: sessionController, transcriptContainer: transcriptContainer)
        let manager = modelManager
        self.live = LiveViewModel(settings: settings, mute: mute, permission: permission,
                                  modelReady: { id in await manager.isWhisperReady(id) },
                                  supplier: assembler.supplier())
        activity.live = live
        self.models = ModelsViewModel(manager: modelManager, settings: settings, deviceInfo: deviceInfo, isPipelineRunning: { activity.isBusy })
        self.settingsModel = SettingsViewModel(store: settings, mute: mute)
        live.observe(sessionEvents: sessionController.events)
        let controller = sessionController
        let events = interruptions.events
        interruptionTask = Task {
            for await event in events {
                await controller.handle(event)
            }
        }
    }

    /// The production environment; every failure here is a build-configuration error, so it is fatal (§6.11).
    static func live() throws -> AppEnvironment {
        let configuration = AppConfiguration.load()
        let deviceInfo = DeviceInfo.current()
        deviceInfo.logOnce()
        return try AppEnvironment(
            configuration: configuration,
            deviceInfo: deviceInfo,
            settingsURL: try SettingsStore.defaultFileURL(),
            modelRoot: try ModelLayout.defaultRoot(),
            transcriptContainer: try TranscriptContainer.make(inMemory: false),
            sessionSeam: LiveAudioSessionSeam(),
            installSteps: .production,
            installHost: UIApplicationInstallHost(),
            verifiedLoads: VerifiedLoadRecord(),
            permission: .live
        )
    }

    /// Tests and previews: temporary root, in-memory store, recording session seam, no network, granted permission.
    static func testing(root: URL) throws -> AppEnvironment {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let modelRoot = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        let recorded = InstallSteps(
            downloadWhisperVariant: { _, _, _ in throw URLError(.notConnectedToInternet) },
            downloadTokenizer: { _, _, _ in throw URLError(.notConnectedToInternet) },
            downloadVAD: { _, _ in throw URLError(.notConnectedToInternet) },
            verifyWhisper: { _, _ in },
            verifyVAD: { _ in },
            deleteVAD: { _ in },
            setOfflineMode: { _ in }
        )
        return try AppEnvironment(
            configuration: AppConfiguration(appGroup: "group.test.revox", broadcastExtensionBundleID: "test.revox.broadcast"),
            deviceInfo: DeviceInfo(physicalMemoryBytes: 6 * 1_073_741_824),
            settingsURL: root.appendingPathComponent(SettingsCodec.fileName),
            modelRoot: modelRoot,
            transcriptContainer: try TranscriptContainer.make(inMemory: true),
            sessionSeam: RecordingSeamForTesting(),
            installSteps: recorded,
            installHost: NoopInstallHost(),
            verifiedLoads: VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxAppEnvironmentTesting-\(UUID().uuidString)")!),
            permission: .fixed(.granted)
        )
    }

    func applicationDidBecomeActive() {
        modelManager.applicationDidBecomeActive()
    }
}

/// App-side stand-ins for `testing(root:)` (the test bundle's recorders live in `ReVoxMobileTests/Support`).
final class RecordingSeamForTesting: AudioSessionSeam, @unchecked Sendable {
    func setCategory(_ mask: SessionMask) throws {}
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {}
    func makeEngine() -> any AudioEngineSeam { LiveAudioEngineSeam() }
}

@MainActor
final class NoopInstallHost: InstallHost {
    private var next = 1
    var isIdleTimerDisabled = false
    func beginBackgroundTask(name: String, expiration: @escaping @MainActor () -> Void) -> Int { defer { next += 1 }; return next }
    func endBackgroundTask(_ identifier: Int) {}
}
