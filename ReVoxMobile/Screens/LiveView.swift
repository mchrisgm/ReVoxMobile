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
    /// nil in the hosting tests: with no bridge the second direction stays transcript-only, exactly as it does on
    /// an iPhone whose iOS has no translator (§8.2).
    var secondaryTranslation: TranslationBridge? = nil
    @Environment(\.openURL) private var openURL
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 12) {
            sourceCard
            twoWayCard
            statusLine
            bannerView
            transcriptOnlyNote
            if model.showsBroadcastPicker {
                broadcastPicker
            }
            transcript
            startStopButton
        }
        .padding(.bottom)
        .modifier(TwoWayTranslation(source: model.twoWayPair?.source, target: model.twoWayPair?.target,
                                    bridge: secondaryTranslation))
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

    /// §8.2: the segmented control alone did not say what either source listens to, or why it stops responding
    /// mid-run. The card names the choice, describes the selected one, and says what to do about it while busy.
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listen to")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Picker("Listen to", selection: $model.captureMode) {
                ForEach(Self.availableSources, id: \.self) { mode in
                    Text(Self.title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)
            .accessibilityLabel("Audio source")
            .accessibilityHint(isBusy ? Self.lockedWhileRunningText : "")
            Label {
                Text(isBusy ? Self.lockedWhileRunningText : Self.description(for: model.captureMode))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: Self.symbol(for: model.captureMode))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    /// §8.2 (M8): the two-way conversation controls, on the Live screen because they are turned on and off in the
    /// middle of a conversation. Both pickers are locked while a run is going, like the source: the pipeline reads
    /// them once, at Start.
    @ViewBuilder
    private var twoWayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.isTwoWay) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Two-way").font(.subheadline.weight(.semibold))
                    Text(Self.twoWaySummary(ignored: model.ignoredLanguage, target: model.twoWayLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isBusy)
            .accessibilityHint(isBusy ? Self.lockedWhileRunningText : Self.twoWayHintText)
            if model.isTwoWay {
                Divider()
                languageRow(title: "Don't translate", selection: $model.ignoredLanguage)
                languageRow(title: "Reply in", selection: $model.twoWayLanguage)
                if let note = model.twoWayVoiceNote {
                    Label(note, systemImage: "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    /// The label is carried by its own `Text`: a `.menu` picker outside a `Form` renders only its value, which
    /// left the card showing two bare language names with nothing saying which was which.
    private func languageRow(title: String, selection: Binding<String?>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline)
            Spacer(minLength: 8)
            Picker(title, selection: selection) {
                Text(Self.noLanguageTitle).tag(String?.none)
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .disabled(isBusy)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    /// The one place a transcript-only phrase is explained: it is in the transcript, and nothing said it (§8.2).
    @ViewBuilder
    private var transcriptOnlyNote: some View {
        if let note = model.transcriptOnlyNote {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary)
                Text(note).font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Dismiss") { model.dismissTranscriptOnlyNote() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
        }
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
        case .usingFallbackModel(let requested, let used):
            banner(text: LiveBanner.fallbackText(requested: requested, used: used), buttonTitle: "Dismiss") {
                model.dismissBanner()
            }
        case .modelLoadFailed(let failed):
            banner(text: LiveBanner.loadFailedText(failed), buttonTitle: "Try again") {
                Task { await model.start() }
            }
        case .vadLoadFailed:
            banner(text: LiveBanner.vadLoadFailedText, buttonTitle: "Try again") {
                Task { await model.start() }
            }
        case .degraded(let message):
            banner(text: message, buttonTitle: "Dismiss") {
                model.dismissBanner()
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
                        .frame(minHeight: 44)
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

    /// §8.2: one capsule that carries the whole state — Start, a spinner and the model's own progress line while
    /// the model loads, then a red Stop. Loading a Whisper model takes seconds on a first run, and the old button
    /// went grey and said nothing for all of them.
    private var startStopButton: some View {
        VStack(spacing: 6) {
            Button {
                Task { await model.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if model.state == .preparing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: model.state == .running ? "stop.fill" : "mic.fill")
                            .accessibilityHidden(true)
                    }
                    Text(Self.buttonTitle(for: model.state))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(model.state == .running ? .red : .accentColor)
            .disabled(model.state == .preparing)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(Self.buttonAccessibilityLabel(for: model.state))
            .accessibilityHint(model.captureMode == .broadcast && model.state == .running ? "Stops translating; the broadcast itself ends from Control Center" : "")
            if model.state == .preparing {
                Text(model.preparingMessage ?? Self.preparingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal)
        .animation(.default, value: model.state)
    }

    // MARK: Copy

    static let lockedWhileRunningText = "Stop to change this"
    static let noLanguageTitle = "None"
    static let preparingText = "Getting the model ready…"
    static let twoWayHintText = "Speaks the language ReVox is not translating back in another language"
    static let microphoneDescription = "Translates what this iPhone's microphone hears."
    static let broadcastDescription = "Translates a call, a video or anything else playing on this iPhone."

    static func title(for mode: CaptureMode) -> String {
        switch mode {
        case .microphone: return "Microphone"
        case .broadcast: return "Other apps"
        }
    }

    static func description(for mode: CaptureMode) -> String {
        switch mode {
        case .microphone: return microphoneDescription
        case .broadcast: return broadcastDescription
        }
    }

    static func symbol(for mode: CaptureMode) -> String {
        switch mode {
        case .microphone: return "mic"
        case .broadcast: return "iphone.badge.play"
        }
    }

    static func buttonTitle(for state: LiveState) -> String {
        switch state {
        case .preparing: return "Preparing…"
        case .running: return "Stop"
        case .idle, .error: return "Start"
        }
    }

    static func buttonAccessibilityLabel(for state: LiveState) -> String {
        switch state {
        case .preparing: return "Preparing the model"
        case .running: return "Stop translating"
        case .idle, .error: return "Start translating"
        }
    }

    /// The toggle's subtitle: what two-way will actually do, in the languages chosen, or what is still missing.
    static func twoWaySummary(ignored: String?, target: String?) -> String {
        guard let ignored else { return "Choose a language to leave alone" }
        let ignoredName = LanguageCatalog.displayName(ignored, whenNil: noLanguageTitle)
        guard let target, target != ignored else { return "\(ignoredName) is left alone" }
        let targetName = LanguageCatalog.displayName(target, whenNil: noLanguageTitle)
        return "\(ignoredName) is spoken back in \(targetName)"
    }

}
