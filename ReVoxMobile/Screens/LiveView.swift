import SwiftUI
import UIKit
import ReVoxCore

struct LiveView: View {
    static let availableSources: [CaptureMode] = [.microphone, .broadcast]
    static let broadcastEmptyStateText = "Choose Other apps, tap Start, then start the broadcast."
    private static let bottomSentinel = "live-transcript-bottom"

    @Bindable var model: LiveViewModel
    let models: ModelsViewModel
    let broadcastExtensionBundleID: String
    @Environment(\.openURL) private var openURL
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 12) {
            sourcePicker
            statusLine
            bannerView
            if model.showsBroadcastPicker {
                broadcastPicker
            }
            transcript
            startStopButton
        }
        .padding(.bottom)
        .navigationTitle("ReVox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.setMuted(!model.isMuted) }
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.slash")
                }
                .accessibilityLabel(model.isMuted ? "Unmute voice" : "Mute voice")
            }
        }
        .sensoryFeedback(.impact, trigger: model.state == .running)
    }

    private var isBusy: Bool { model.state == .running || model.state == .preparing }

    private var sourcePicker: some View {
        Picker("Source", selection: $model.captureMode) {
            ForEach(Self.availableSources, id: \.self) { mode in
                Text(Self.title(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(isBusy)
        .padding(.horizontal)
        .accessibilityLabel("Audio source")
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(model.modelStatusText, systemImage: "cpu")
                Label(model.voiceStatusText, systemImage: "speaker.wave.2")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if model.isFallingBehind {
                    Text("Falling behind")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }
                if let ducking = model.duckingStatusText {
                    Text(ducking)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((model.isDucked ? Color.accentColor : Color.secondary).opacity(0.15), in: Capsule())
                }
                if let status = model.sessionStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let broadcastStatus = model.broadcastStatusText {
                Label(broadcastStatus, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LiveStatusAccessibility.label(modelStatus: model.modelStatusText, voiceStatus: model.voiceStatusText,
                                                          isFallingBehind: model.isFallingBehind, duckingStatus: model.duckingStatusText,
                                                          sessionStatus: model.sessionStatus, broadcastStatus: model.broadcastStatusText))
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// §8.2: the system picker with the Control Center explanation and the side-button footnote (C3).
    private var broadcastPicker: some View {
        HStack(alignment: .top, spacing: 12) {
            BroadcastPickerButton(preferredExtension: broadcastExtensionBundleID)
                .frame(width: BroadcastPickerButton.size, height: BroadcastPickerButton.size)
            VStack(alignment: .leading, spacing: 4) {
                Text(BroadcastPickerButton.captionText).font(.footnote)
                Text(BroadcastPickerButton.footnoteText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var bannerView: some View {
        switch model.banner {
        case .permissionDenied:
            banner(text: "Microphone access is off for ReVox. Allow it in Settings to translate from the microphone.", buttonTitle: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .error(let message):
            banner(text: message, buttonTitle: "Try again") {
                Task { await model.start() }
            }
        case .modelMissing, nil:
            EmptyView()
        }
    }

    private func banner(text: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.footnote)
            Button(buttonTitle, action: action).buttonStyle(.bordered).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }

    @ViewBuilder
    private var transcript: some View {
        if case .modelMissing(let missing) = model.banner {
            ContentUnavailableView {
                Label("No model installed", systemImage: "arrow.down.circle")
            } description: {
                Text("ReVox needs a Whisper model to translate.")
            } actions: {
                NavigationLink("Download \(missing.displayName) (\(ModelsViewModel.sizeText(ModelCatalog.whisper(missing).approximateBytes)))") {
                    ModelsView(model: models)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if model.rows.isEmpty && model.state == .idle {
            ContentUnavailableView("Ready to translate", systemImage: "waveform.and.mic",
                                   description: Text(model.captureMode == .broadcast ? Self.broadcastEmptyStateText : "Choose a source and tap Start."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.rows) { row in
                            LiveTranscriptRowView(row: row).id(row.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomSentinel)
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    }
                    .padding(.horizontal)
                }
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation { proxy.scrollTo(Self.bottomSentinel, anchor: .bottom) }
                            isAtBottom = true
                        } label: {
                            Label("Jump to latest", systemImage: "arrow.down").font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                    }
                }
                .onChange(of: model.rows.count) { _, _ in
                    if isAtBottom, let last = model.rows.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var startStopButton: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            Label(model.state == .running ? "Stop" : "Start", systemImage: model.state == .running ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.state == .preparing)
        .keyboardShortcut(.space, modifiers: [])
        .padding(.horizontal)
        .accessibilityLabel(model.state == .running ? "Stop translating" : "Start translating")
        .accessibilityHint(model.captureMode == .broadcast && model.state == .running ? "Stops translating; the broadcast itself ends from Control Center" : "")
    }

    static func title(for mode: CaptureMode) -> String {
        switch mode {
        case .microphone: return "Microphone"
        case .broadcast: return "Other apps"
        }
    }
}
