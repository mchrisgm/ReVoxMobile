import SwiftUI

@main
struct ReVoxMobileApp: App {
    @State private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            _environment = State(initialValue: try AppEnvironment.live())
        } catch {
            fatalError("ReVox cannot start: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
        .modelContainer(environment.transcriptContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                environment.applicationDidBecomeActive()
            }
        }
    }
}
