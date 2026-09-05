import SwiftUI
import ReVoxCore

struct ModelsView: View {
    @Bindable var model: ModelsViewModel
    @State private var pendingDelete: WhisperModelID?

    var body: some View {
        List {
            Section {
                ForEach(model.rows) { row in
                    ModelRowView(row: row,
                                 onDownload: { model.download(row.id) },
                                 onCancel: { model.cancel(row.id) },
                                 onSelect: { model.select(row.id) })
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if model.canDelete && row.state.phase == .installed {
                            Button(role: .destructive) { pendingDelete = row.id } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            } header: {
                Text("Whisper models")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.storageFooterText)
                    if let footer = model.footerText { Text(footer) }
                    if let warning = model.lowStorageWarning { Text(warning) }
                }
            }
            if let benchmark = model.benchmark {
                Section {
                    NavigationLink(BenchmarkViewModel.linkTitle) { BenchmarkView(model: benchmark) }
                        .frame(minHeight: 44)
                        .accessibilityHint(BenchmarkViewModel.linkHint)
                } footer: {
                    Text(model.benchmarkFooterText)
                }
            }
            Section("Voice detector") {
                VADRowView(row: model.vadRow)
            }
        }
        .navigationTitle("Models")
        .confirmationDialog(
            pendingDelete.map(ModelsViewModel.confirmDeleteTitle) ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { id in
            Button("Delete", role: .destructive) {
                model.deleteConfirmed(id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(ModelsViewModel.confirmDeleteMessage)
        }
        .alert("Not enough space", isPresented: Binding(get: { model.lowStorageAlert != nil }, set: { if !$0 { model.lowStorageAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lowStorageAlert ?? "")
        }
        .alert("Can't delete now", isPresented: Binding(get: { model.deleteFailureAlert != nil }, set: { if !$0 { model.deleteFailureAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.deleteFailureAlert ?? "")
        }
        .onChange(of: model.rows) { _, _ in model.reconcileFailures() }
        .alert("Can't download now", isPresented: Binding(get: { model.downloadRefusedAlert != nil }, set: { if !$0 { model.downloadRefusedAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.downloadRefusedAlert ?? "")
        }
        .alert("Download failed", isPresented: Binding(get: { model.downloadFailureAlert != nil }, set: { if !$0 { model.downloadFailureAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.downloadFailureAlert ?? "")
        }
    }
}
