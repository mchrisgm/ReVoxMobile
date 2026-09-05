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
    /// M10: the volume slider and the details panel are unfolded per launch only — never a Settings field.
    @State private var showsVolumeSlider = false
    @State private var isMoreExpanded = false

    /// M10: one control strip, a one-line status, then the transcript takes every point that is left. The
    /// three cards this replaced left two rows of transcript on an iPhone 12.
    var body: some View {
        VStack(spacing: 8) {
            LiveControlStrip(model: model, showsVolumeSlider: $showsVolumeSlider, isMoreExpanded: $isMoreExpanded)
            if isMoreExpanded {
                LiveDetailsPanel(model: model)
            }
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

    /// M10: one line. The parts that change during a run — the lag badge, the ducking badge, the session and
    /// broadcast status — keep their full width; the model name yields next; the voice, the longest and least
    /// urgent part, truncates first. VoiceOver reads the whole sentence whatever was cut. "Ducking off" moved to
    /// the strip's own pill, so the badge here appears only while other audio is actually being lowered.
    private var statusLine: some View {
        HStack(spacing: 8) {
            Label(model.modelStatusText, systemImage: "cpu")
                .lineLimit(1)
                .layoutPriority(1)
            Label(model.voiceStatusText, systemImage: "speaker.wave.2")
                .lineLimit(1)
                .truncationMode(.tail)
            if model.isFallingBehind {
                statusBadge("Falling behind", tint: .orange)
            }
            if let ducking = Self.duckingBadge(isDucked: model.isDucked, status: model.duckingStatusText) {
                statusBadge(ducking, tint: .accentColor)
            }
            if let status = model.sessionStatus {
                Text(status)
                    .lineLimit(1)
                    .layoutPriority(2)
            }
            if let broadcastStatus = model.broadcastStatusText {
                Label(broadcastStatus, systemImage: "antenna.radiowaves.left.and.right")
                    .lineLimit(1)
                    .layoutPriority(2)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(LiveStatusAccessibility.label(modelStatus: model.modelStatusText, voiceStatus: model.voiceStatusText,
                                                          isFallingBehind: model.isFallingBehind,
                                                          duckingStatus: Self.duckingBadge(isDucked: model.isDucked, status: model.duckingStatusText),
                                                          sessionStatus: model.sessionStatus, broadcastStatus: model.broadcastStatusText))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func statusBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .layoutPriority(2)
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
            // M9: a periodic timeline so "12 s" counts up while the reader follows the conversation. It ticks only
            // when ages are shown; with the time alone the rows are static and the view is drawn once.
            TimelineView(.periodic(from: .now, by: model.timeDisplay == .time ? 3_600 : 1)) { context in
              ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(model.rows) { row in
                            LiveTranscriptRowView(row: row, now: context.date, timeDisplay: model.timeDisplay,
                                                  showsOriginal: model.isLearning, romanizes: model.romanizes)
                                .id(row.id)
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
    static let noLanguageTitle = "Not set"
    static let preparingText = "Getting the model ready…"
    static let twoWayHintText = "Speaks what you say to the other person in their language"
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

    /// M10: the status line's ducking badge. The strip's pill already says "Duck off", so the line shows the
    /// state only while other audio is actually lowered — the one moment the pill cannot show.
    static func duckingBadge(isDucked: Bool, status: String?) -> String? {
        isDucked ? status : nil
    }

    /// The details panel's Languages line while Two-way is on: both directions in the names of the two people, or
    /// what is still missing. `they` nil or "" is English — what actually runs (`Settings.twoWayLanguage`).
    static func twoWaySummary(you: String?, they: String?) -> String {
        guard let you else { return "Choose the language you speak." }
        let youName = LanguageCatalog.displayName(you, whenNil: noLanguageTitle)
        let theyCode = they.flatMap { $0.isEmpty ? nil : $0 } ?? "en"
        guard theyCode != you else {
            return "You and they both speak \(youName), so there is nothing to translate. Choose the language they speak."
        }
        let theyName = LanguageCatalog.displayName(theyCode, whenNil: noLanguageTitle)
        return "What you say in \(youName) is spoken to them in \(theyName); what they say is spoken to you in English."
    }

    /// The same line while Two-way is off: the one place Settings › Your language shows on Live in that state.
    static func twoWayOffSummary(you: String?) -> String {
        guard let you else { return "Two-way is off: everything ReVox hears is spoken to you in English, including what you say." }
        let youName = LanguageCatalog.displayName(you, whenNil: noLanguageTitle)
        return "Two-way is off: \(youName) is not translated and not spoken back at you; everything else is spoken to you in English."
    }
}
