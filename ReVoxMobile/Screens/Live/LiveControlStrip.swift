import SwiftUI
import ReVoxCore

/// M10: the Live screen's controls as one row of pills, so the transcript gets the height the three cards used to
/// take. Source and latency are menus; ducking, Learning and two-way are toggle pills; the voice volume opens an
/// inline slider under the row; More unfolds the explanations (`LiveDetailsPanel`). Everything the pipeline reads
/// once at Start — source, latency, ducking, Learning, two-way and its languages — is locked while a run is going:
/// dimmed, with one shared "Stop to change" pill at the head of the row instead of a caption per control. The
/// volume stays live because the players read it per clip (M9).
///
/// Smarter: the two-way language row exists only while two-way is on, the reply pill's symbol turns into a
/// crossed speaker when this iPhone has no voice for the reply language, and the value each pill shows is the
/// one thing a glance needs ("Mic", "Fast", "Duck on", "80%").
struct LiveControlStrip: View {
    @Bindable var model: LiveViewModel
    @Binding var showsVolumeSlider: Bool
    @Binding var isMoreExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { Self.locksControls(in: model.state) }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isLocked {
                        lockedPill
                    }
                    sourcePill
                    latencyPill
                    duckingPill
                    learningPill
                    twoWayPill
                    volumePill
                    morePill
                }
                .padding(.horizontal)
            }
            if model.isTwoWay {
                twoWayRow
            }
            if showsVolumeSlider {
                volumeRow
            }
        }
        .animation(reduceMotion ? nil : .default, value: model.isTwoWay)
        .animation(reduceMotion ? nil : .default, value: showsVolumeSlider)
    }

    // MARK: The pills

    /// The one hint for every locked pill: it sits where the row starts, so the dimming next to it needs no caption.
    private var lockedPill: some View {
        Label(Self.lockedText, systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(minHeight: LiveControlPill.minimumHeight)
            .accessibilityLabel(LiveView.lockedWhileRunningText)
    }

    private var sourcePill: some View {
        Menu {
            Picker(Self.sourceAccessibilityLabel, selection: $model.captureMode) {
                ForEach(LiveView.availableSources, id: \.self) { mode in
                    Label(LiveView.title(for: mode), systemImage: LiveView.symbol(for: mode)).tag(mode)
                }
            }
        } label: {
            LiveControlPill(systemImage: LiveView.symbol(for: model.captureMode), title: Self.sourcePillTitle(for: model.captureMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(Self.sourceAccessibilityLabel)
        .accessibilityValue(LiveView.title(for: model.captureMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.description(for: model.captureMode))
    }

    private var latencyPill: some View {
        Menu {
            Picker(Self.latencyAccessibilityLabel, selection: $model.latencyMode) {
                ForEach(SegmenterPreset.allCases, id: \.self) { preset in
                    Label(SettingsView.title(for: preset), systemImage: Self.latencySymbol(for: preset)).tag(preset)
                }
            }
        } label: {
            LiveControlPill(systemImage: Self.latencySymbol(for: model.latencyMode), title: SettingsView.title(for: model.latencyMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(Self.latencyAccessibilityLabel)
        .accessibilityValue(SettingsView.title(for: model.latencyMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : SettingsViewModel.presetDescription(model.latencyMode))
    }

    private var duckingPill: some View {
        Toggle(isOn: $model.ducking) {
            LiveControlPill(systemImage: "waveform.badge.minus",
                            title: Self.togglePillTitle(Self.duckingPillName, isOn: model.ducking), isOn: model.ducking)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Ducking")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : Self.duckingHelpText)
    }

    private var learningPill: some View {
        Toggle(isOn: $model.isLearning) {
            LiveControlPill(systemImage: model.isLearning ? "text.book.closed.fill" : "text.book.closed",
                            title: Self.togglePillTitle(Self.learningPillName, isOn: model.isLearning), isOn: model.isLearning)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Learning mode")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : Self.learningHelpText)
    }

    private var twoWayPill: some View {
        Toggle(isOn: $model.isTwoWay) {
            LiveControlPill(systemImage: "arrow.left.arrow.right",
                            title: Self.togglePillTitle(Self.twoWayPillName, isOn: model.isTwoWay), isOn: model.isTwoWay)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Two-way conversation")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.twoWayHintText)
    }

    /// Live during a run: the pill shows the level and opens the slider in place rather than a sheet over the
    /// transcript.
    private var volumePill: some View {
        Button {
            toggleWithMotion { showsVolumeSlider.toggle() }
        } label: {
            LiveControlPill(systemImage: Self.volumeSymbol(for: model.voiceVolume), title: Self.volumePillName,
                            value: Self.volumePillText(model.voiceVolume), isOn: showsVolumeSlider)
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel("Voice volume")
        .accessibilityValue(Self.volumePercentText(model.voiceVolume))
        .accessibilityHint(showsVolumeSlider ? Self.hideVolumeHintText : Self.showVolumeHintText)
    }

    private var morePill: some View {
        Button {
            toggleWithMotion { isMoreExpanded.toggle() }
        } label: {
            LiveControlPill(systemImage: isMoreExpanded ? "chevron.up.circle" : "info.circle",
                            title: Self.moreTitle(expanded: isMoreExpanded), isOn: isMoreExpanded)
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel(Self.moreAccessibilityLabel)
        .accessibilityValue(isMoreExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isMoreExpanded ? Self.lessHintText : Self.moreHintText)
    }

    // MARK: The rows that exist only when they matter

    /// The two-way languages, as two menu pills on a second row: they matter only while two-way is on, and the
    /// pipeline reads them at Start like everything else on the first row.
    private var twoWayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                languagePill(title: Self.leaveAloneTitle, systemImage: "hand.raised", selection: $model.ignoredLanguage,
                             hint: Self.leaveAloneHintText)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                languagePill(title: Self.replyInTitle, systemImage: model.twoWayVoiceNote == nil ? "bubble.left" : "speaker.slash",
                             selection: $model.twoWayLanguage, hint: model.twoWayVoiceNote ?? Self.replyInHintText)
            }
            .padding(.horizontal)
        }
        .disabled(isLocked)
    }

    private func languagePill(title: String, systemImage: String, selection: Binding<String?>, hint: String) -> some View {
        let name = LanguageCatalog.displayName(selection.wrappedValue, whenNil: LiveView.noLanguageTitle)
        return Menu {
            Picker(title, selection: selection) {
                Text(LiveView.noLanguageTitle).tag(String?.none)
                ForEach(LanguageCatalog.concrete) { option in
                    Text(option.displayName).tag(option.code)
                }
            }
        } label: {
            LiveControlPill(systemImage: systemImage, title: title, value: name)
        }
        .accessibilityLabel(title)
        .accessibilityValue(name)
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : hint)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: $model.voiceVolume, in: 0...1, step: 0.05) { Text("Voice volume") }
                .accessibilityValue(Self.volumePercentText(model.voiceVolume))
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: LiveControlPill.minimumHeight)
        .padding(.horizontal)
    }

    private func toggleWithMotion(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.default, change)
        }
    }

    // MARK: Copy and layout decisions (pure, read by the tests)

    static let lockedText = "Stop to change"
    static let sourceAccessibilityLabel = "Audio source"
    static let latencyAccessibilityLabel = "Latency mode"
    static let duckingPillName = "Duck"
    static let learningPillName = "Learn"
    static let twoWayPillName = "Two-way"
    static let volumePillName = "Volume"
    static let moreAccessibilityLabel = "Details"
    static let leaveAloneTitle = "Leave alone"
    static let replyInTitle = "Reply in"
    static let duckingHelpText = "Lowers other apps' audio while ReVox speaks; applies at the next Start"
    static let learningHelpText = "Shows the words as spoken above the translation; applies at the next Start"
    static let leaveAloneHintText = "The language ReVox does not translate"
    static let replyInHintText = "The language that language is spoken back in"
    static let showVolumeHintText = "Shows the volume slider"
    static let hideVolumeHintText = "Hides the volume slider"
    static let moreHintText = "Explains what each control does"
    static let lessHintText = "Hides the explanations"

    /// Source, latency, ducking, Learning and two-way are read once, when the pipeline starts (§8.2, M9).
    static func locksControls(in state: LiveState) -> Bool {
        switch state {
        case .running, .preparing: return true
        case .idle, .error: return false
        }
    }

    /// The pill is narrow; the menu and VoiceOver keep the full `LiveView.title(for:)`.
    static func sourcePillTitle(for mode: CaptureMode) -> String {
        switch mode {
        case .microphone: return "Mic"
        case .broadcast: return "Other apps"
        }
    }

    static func latencySymbol(for preset: SegmenterPreset) -> String {
        switch preset {
        case .balanced: return "gauge.with.dots.needle.33percent"
        case .fast: return "gauge.with.dots.needle.67percent"
        case .veryFast: return "gauge.with.dots.needle.100percent"
        }
    }

    /// "Duck on" / "Duck off": the state is in the words, not only in the tint.
    static func togglePillTitle(_ name: String, isOn: Bool) -> String {
        "\(name) \(isOn ? "on" : "off")"
    }

    static func volumePillText(_ volume: Double) -> String {
        "\(volumePercent(volume))%"
    }

    static func volumePercentText(_ volume: Double) -> String {
        "\(volumePercent(volume)) percent"
    }

    static func volumePercent(_ volume: Double) -> Int {
        Int((min(max(volume, 0), 1) * 100).rounded())
    }

    static func volumeSymbol(for volume: Double) -> String {
        switch volumePercent(volume) {
        case 0: return "speaker.slash"
        case 1...33: return "speaker.wave.1"
        case 34...66: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    static func moreTitle(expanded: Bool) -> String {
        expanded ? "Less" : "More"
    }

    /// "Fast — Silence 300 ms, max 4 s": the preset's name with the numbers Settings shows for it.
    static func latencyDetailText(for preset: SegmenterPreset) -> String {
        "\(SettingsView.title(for: preset)) — \(SettingsViewModel.presetDescription(preset))"
    }
}

/// The rarely needed words behind the pills, folded away by default: what the chosen source listens to, what the
/// latency preset waits for, what ducking and Learning do, and — with two-way on — what it will do in the chosen
/// languages plus the missing-voice note. Expanded and collapsed per launch only (`@State` in `LiveView`).
struct LiveDetailsPanel: View {
    let model: LiveViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            detail(LiveView.description(for: model.captureMode), systemImage: LiveView.symbol(for: model.captureMode))
            detail(LiveControlStrip.latencyDetailText(for: model.latencyMode), systemImage: LiveControlStrip.latencySymbol(for: model.latencyMode))
            detail(LiveControlStrip.duckingHelpText, systemImage: "waveform.badge.minus")
            detail(LiveControlStrip.learningHelpText, systemImage: "text.book.closed")
            if model.isTwoWay {
                detail(LiveView.twoWaySummary(ignored: model.ignoredLanguage, target: model.twoWayLanguage), systemImage: "arrow.left.arrow.right")
                if let note = model.twoWayVoiceNote {
                    detail(note, systemImage: "speaker.slash")
                }
            } else {
                detail(LiveView.twoWayHintText, systemImage: "arrow.left.arrow.right")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LiveControlStrip.moreAccessibilityLabel)
    }

    private func detail(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .accessibilityElement(children: .combine)
    }
}
