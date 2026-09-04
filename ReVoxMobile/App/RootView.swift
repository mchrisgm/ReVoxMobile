import SwiftUI

/// The single tab container (§8.1, R14); `.tabItem` is the iOS 17 API (`Tab` is iOS 18) and the iOS 27 seam of §12.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        @Bindable var onboarding = environment.onboarding
        TabView {
            NavigationStack {
                LiveView(model: environment.live, models: environment.models,
                         broadcastExtensionBundleID: environment.configuration.broadcastExtensionBundleID,
                         secondaryTranslation: environment.assembler.secondaryTranslation)
            }
            .tabItem { Label("Live", systemImage: "waveform") }

            NavigationStack {
                HistoryView(exporter: environment.exporter)
            }
            .tabItem { Label("History", systemImage: "clock") }

            NavigationStack {
                SettingsView(model: environment.settingsModel, models: environment.models, voices: environment.voices, diagnostics: environment.diagnostics,
                             onboarding: environment.onboarding)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // M10: the first-run tutorial, shown on appear until this version of it has been finished or skipped, and
        // again whenever Settings › "Show the tutorial" resets it. A full-screen cover: it cannot be swiped away.
        .fullScreenCover(isPresented: $onboarding.shouldShowNow) {
            OnboardingView(model: onboarding)
        }
    }
}
