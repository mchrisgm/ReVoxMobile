import SwiftUI
import ReVoxCore

/// Placeholder root screen. Milestone 3 replaces it with the real Main screen.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "ReVox Mobile",
                systemImage: "waveform.and.mic",
                description: Text("Live speech-to-English translation, entirely on this iPhone.\nPipeline sample rate: \(ReVoxCore.sampleRate) Hz")
            )
            .navigationTitle("ReVox")
        }
    }
}

#Preview {
    ContentView()
}
