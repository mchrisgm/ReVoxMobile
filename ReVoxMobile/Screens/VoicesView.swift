import SwiftUI
import ReVoxCore

/// The Voices screen (§8.4): both engines, pocket-tts download and confirmed delete, "Play sample", system voices.
struct VoicesView: View {
    @Bindable var model: VoicesViewModel
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                if model.isPocketTTSInstalled {
                    pocketTTSStatusRow
                    ForEach(model.offeredVoices, id: \.self) { voice in
                        Button { model.selectPocketVoice(voice) } label: {
                            HStack {
                                Text(voice)
                                Spacer()
                                if model.selectedPocketVoice == voice {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel(model.selectedPocketVoice == voice ? "\(voice), selected" : voice)
                        .accessibilityHint("pocket-tts voice")
                    }
                    sampleRow
                } else {
                    PocketTTSDownloadRow(state: model.pocketTTSState, onDownload: { model.download() }, onCancel: { model.cancel() })
                }
            } header: {
                Text("pocket-tts (Kyutai)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let advisory = model.advisoryText { Text(advisory) }
                    if let footer = model.footerText { Text(footer) }
                    if let warning = model.lowStorageWarning { Text(warning) }
                    Text(VoicesViewModel.engineFooterText)
                }
            }

            Section {
                ForEach(model.systemVoices) { option in
                    Button { model.selectSystemVoice(option) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                Text("\(option.qualityLabel) · \(option.language)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedSystemVoiceIdentifier == option.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(model.selectedSystemVoiceIdentifier == option.id ? "\(option.name), \(option.qualityLabel), selected" : "\(option.name), \(option.qualityLabel)")
                    .accessibilityHint("System voice")
                }
            } header: {
                Text("System voices")
            } footer: {
                Text("Add or upgrade English voices in Settings > Accessibility > Spoken Content.")
            }
        }
        .navigationTitle("Voices")
        .onAppear { model.refreshSystemVoices() }
        .confirmationDialog(VoicesViewModel.confirmDeleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try model.delete() } catch { model.lowStorageAlert = String(describing: error) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(VoicesViewModel.confirmDeleteMessage)
        }
        .alert("Not enough space", isPresented: Binding(get: { model.lowStorageAlert != nil }, set: { if !$0 { model.lowStorageAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lowStorageAlert ?? "")
        }
        .onChange(of: model.pocketTTSState) { _, _ in model.reconcileFailures() }
        .alert("Download failed", isPresented: Binding(get: { model.downloadFailureAlert != nil }, set: { if !$0 { model.downloadFailureAlert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.downloadFailureAlert ?? "")
        }
    }

    /// Installed: name, size, the engine status; carries the swipe-to-delete action (hidden while running, §8.4).
    private var pocketTTSStatusRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(VoicesViewModel.pocketTTSName).font(.headline)
                Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(VoicesViewModel.pocketTTSSizeText).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("pocket-tts installed, \(VoicesViewModel.pocketTTSSizeText). \(model.statusText).")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.canDelete {
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private var sampleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { Task { await model.playSample() } } label: {
                    Label("Play sample", systemImage: "play.circle")
                }
                .disabled(!model.canPlaySample)
                .frame(minHeight: 44)
                .accessibilityHint("Speaks \"\(VoicesViewModel.sampleText)\" with the selected voice")
                if model.isPlayingSample {
                    ProgressView().accessibilityLabel("Playing sample")
                }
                Spacer()
                if model.showsRetry {
                    Button("Retry") { Task { await model.retryPocketTTS() } }
                        .buttonStyle(.bordered)
                        .disabled(!model.canPlaySample)
                        .accessibilityHint("Tries pocket-tts again")
                }
            }
            if let error = model.sampleError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The not-installed row: Download / determinate progress with Cancel / Paused with Resume / Failed with Retry (§8.3 states).
private struct PocketTTSDownloadRow: View {
    let state: ModelDownloadState
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(VoicesViewModel.pocketTTSName).font(.headline)
                Spacer()
                Text(VoicesViewModel.pocketTTSSizeText).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Voices alba, azelma, cosette and javert. Downloaded on demand; the system voice is used until then.")
                .font(.caption).foregroundStyle(.secondary)
            stateView
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var stateView: some View {
        switch state.phase {
        case .idle:
            Button("Download", action: onDownload).buttonStyle(.bordered).frame(minHeight: 44)
        case .listing, .downloading, .compiling, .verifying:
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: state.fraction ?? 0)
                HStack {
                    Text(ModelsViewModel.phaseText(state.phase)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel, action: onCancel).font(.caption)
                }
            }
        case .paused:
            HStack {
                Text("Paused").font(.caption).foregroundStyle(.secondary)
                Text(ModelsViewModel.keepOpenText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Resume", action: onDownload).buttonStyle(.bordered)
            }
        case .installed:
            Text("Installed").font(.subheadline).foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.triangle").font(.subheadline)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Button("Retry", action: onDownload).buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["pocket-tts", VoicesViewModel.pocketTTSSizeText, ModelsViewModel.phaseText(state.phase)]
        if let fraction = state.fraction, state.phase.isActive { parts.append("\(Int(fraction * 100)) percent") }
        return parts.joined(separator: ". ")
    }
}
