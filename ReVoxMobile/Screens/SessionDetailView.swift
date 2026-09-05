import SwiftUI
import SwiftData
import ReVoxCore

/// One session (§8.6): header, the entries in the Live row style, the `ShareLink` export and the confirmed Delete.
struct SessionDetailView: View {
    static let emptyTitle = "Nothing translated"
    static let emptyDescription = "This session has no entries."

    let session: Session
    var exporter = TranscriptExporter()

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [LiveTranscriptRow] = []
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var deleteError: String?
    @State private var confirmingDelete = false

    private var summary: SessionSummary { SessionSummary(session: session) }

    var body: some View {
        List {
            Section("Session") {
                headerRow("Started", value: session.startedAt.formatted(SessionRowView.dateStyle))
                headerRow("Source", value: summary.sourceTitle)
                headerRow("Duration", value: summary.durationText)
                headerRow("Model", value: session.modelID)
                headerRow("Voice", value: session.voice)
                headerRow("Source language", value: SessionDetailRows.languagePinText(session.pinnedLanguage))
                if let skipped = summary.dropCountText {
                    headerRow("Skipped", value: skipped)   // M10: explains the "… skipped" rows below
                }
                if let unsure = summary.guessCountText {
                    headerRow("Unsure", value: unsure)     // M11: explains the greyed rows below
                }
                if session.joinedInProgress {
                    Text("Joined a broadcast already in progress").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Transcript") {
                if rows.isEmpty {
                    ContentUnavailableView(Self.emptyTitle, systemImage: "text.bubble", description: Text(Self.emptyDescription))
                } else {
                    ForEach(rows) { row in
                        // M10: a session recorded with Learning on keeps the words as spoken (the export prints
                        // them too); the row view shows them only where they exist and differ from the English.
                        // Romanization is a reading aid, not a record, so it follows the Live setting's absence here.
                        LiveTranscriptRowView(row: row, showsOriginal: true)
                    }
                }
            }
        }
        .navigationTitle(session.startedAt.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let exportURL {
                    ShareLink(item: exportURL, preview: SharePreview(exporter.fileName(for: session), image: Image(systemName: "doc.text")))
                        .accessibilityLabel("Share transcript")
                        .accessibilityHint("Exports the session as a text file")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityLabel("Delete session")
                .accessibilityHint("Deletes this session after a confirmation")
            }
        }
        .task(id: session.entries.count) {
            rows = SessionDetailRows.rows(for: session)
            writeExport()
        }
        .confirmationDialog(HistoryActions.deleteSessionTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(HistoryActions.deleteSessionMessage(entryCount: summary.entryCount))
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        // A failed delete is its own alert (same title as History's), never the export alert.
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func headerRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// The `.txt` is (re)written whenever the entry count changes, so the share sheet always carries the full session.
    private func writeExport() {
        do {
            exportURL = try exporter.export(session)
            exportError = nil
        } catch {
            exportURL = nil
            exportError = String(describing: error)
        }
    }

    private func deleteSession() {
        do {
            try HistoryActions(context: context).delete(session)
            dismiss()
        } catch {
            deleteError = "Couldn't delete the session: \(String(describing: error))"
        }
    }
}
