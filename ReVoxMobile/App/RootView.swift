import SwiftUI

/// The single tab container (§8.1, R14); `.tabItem` is the iOS 17 API (`Tab` is iOS 18) and the iOS 27 seam of §12.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack {
                LiveView(model: environment.live, models: environment.models, broadcastExtensionBundleID: environment.configuration.broadcastExtensionBundleID)
            }
            .tabItem { Label("Live", systemImage: "waveform") }

            NavigationStack {
                HistoryView(exporter: environment.exporter)
            }
            .tabItem { Label("History", systemImage: "clock") }

            NavigationStack {
                SettingsView(model: environment.settingsModel, models: environment.models, voices: environment.voices, diagnostics: environment.diagnostics)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
