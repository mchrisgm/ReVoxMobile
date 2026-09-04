import Foundation
import ReVoxCore
@testable import ReVoxMobile

/// The view models the screen tests host, built from one layout and settings store. Shared by
/// `ScreenHostingTests` (which proves every screen lays out) and `ScreenshotTests` (which renders the README's
/// images from the same views), so the two can never drift into showing different things.
@MainActor
struct ScreenHostingSupport {
    let layout: ModelLayout
    let store: SettingsStore

    private func manager(pipelineRunning: Bool) -> ModelManager {
        let steps = FakeInstallSteps()
        let installer = ModelInstaller(layout: layout, steps: steps.steps(layout: layout),
                                       verifiedLoads: VerifiedLoadRecord(defaults: UserDefaults(suiteName: "ReVoxScreens-\(UUID().uuidString)")!))
        return ModelManager(layout: layout, installer: installer, isPipelineRunning: { pipelineRunning },
                            availableBytes: { 50_000_000_000 }, host: FakeInstallHost())
    }

    func models(pipelineRunning: Bool = false) -> ModelsViewModel {
        ModelsViewModel(manager: manager(pipelineRunning: pipelineRunning), settings: store,
                        deviceInfo: DeviceInfo(physicalMemoryBytes: 6 * 1_073_741_824),
                        isPipelineRunning: { pipelineRunning })
    }

    func voices(installed: Bool = false, pipelineRunning: Bool = false) throws -> VoicesViewModel {
        if installed { try FakeInstallSteps.fabricatePocketTTS(in: layout) }
        let manager = manager(pipelineRunning: pipelineRunning)
        manager.refreshInstalledStates()
        return VoicesViewModel(
            manager: manager,
            settings: store,
            deviceInfo: DeviceInfo(physicalMemoryBytes: 4 * 1_073_741_824),   // shows the advisory caption
            speakerStatus: SpeakerStatusRelay(),
            samplePlayer: SamplePlayer(play: { _, _ in }),
            selection: { .system(identifier: nil) },
            systemVoices: { [SystemVoiceOption(id: "com.example.premium", name: "Ava", language: "en-US", quality: .premium),
                             SystemVoiceOption(id: "com.example.default", name: "Fred", language: "en-US", quality: .default)] },
            isPipelineRunning: { pipelineRunning }
        )
    }
}
