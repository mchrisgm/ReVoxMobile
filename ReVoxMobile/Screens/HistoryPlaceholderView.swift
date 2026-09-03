import SwiftUI

/// M6 replaces this with `HistoryView` (§8.6); the tab is never hidden (HIG).
struct HistoryPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("No Transcripts", systemImage: "text.bubble", description: Text("Sessions you translate appear here."))
            .navigationTitle("History")
    }
}
