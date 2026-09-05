import SwiftUI
import ReVoxCore

/// M11: the Live screen's controls as three captioned rows of pills — LISTEN (source, latency, ⓘ), VOICE (ducking,
/// volume) and LANGUAGES (Two-way, Learning, and the You speak / They speak pair while Two-way is on) — each row
/// its own `PillFlowLayout` with a 72 pt caption column first, so the pills align and wrapping stays inside a
/// group. Everything the pipeline reads once at Start locks while a run is going: dimmed, with one "Stop to
/// change" line under the groups so tapping Start moves nothing above it. The volume and the ⓘ stay live. The
/// model is `any LiveControlsModel`, so the tutorial hosts the same strip (§6). Height at the default type size:
/// 144 pt idle with Two-way off, 194 pt on, +24 pt while locked.
struct LiveControlStrip: View {
    let model: any LiveControlsModel
    @Binding var showsVolumeSlider: Bool
    @Binding var isMoreExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { Self.locksControls(in: model.state) }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: Self.pillSpacing) {
                LiveListenGroup(model: model, isMoreExpanded: $isMoreExpanded)
                LiveVoiceGroup(model: model, showsVolumeSlider: $showsVolumeSlider)
                LiveLanguagesGroup(model: model)
                if isLocked {
                    LiveLockedLine()
                }
            }
            .padding(.horizontal)
            if showsVolumeSlider {
                LiveVolumeRow(model: model)
            }
        }
        .animation(reduceMotion ? nil : .default, value: showsVolumeSlider)
    }

    // MARK: Copy and layout decisions (pure, read by the tests)

    /// 6 pt between pills and 10 pt inside them: each group is one row on a 393 pt phone at the default type size
    /// (`PillFlowLayoutTests`); a narrower phone or a larger type size wraps inside the group.
    static let pillSpacing: CGFloat = 6
    static let lockedText = "Stop to change"
    static let sourceAccessibilityLabel = "Audio source"
    static let latencyAccessibilityLabel = "Latency mode"
    static let duckingPillName = "Duck"
    static let learningPillName = "Learn"
    static let twoWayPillName = "Two-way"
    static let volumePillName = "Voice volume"
    static let moreAccessibilityLabel = "Details"
    static let duckingHelpText = "Lowers other apps' audio while ReVox speaks; applies at the next Start"
    static let learningHelpText = "Shows the words as spoken above the translation; applies at the next Start"
    static let showVolumeHintText = "Shows the volume slider"
    static let hideVolumeHintText = "Hides the volume slider"
    static let moreHintText = "Explains what each control does"
    static let lessHintText = "Hides the explanations"

    /// The caption column of every group: fixed so the pills align across the three rows (M11 §1).
    static let captionColumnWidth: CGFloat = 72
    static let listenCaption = "Listen"
    static let voiceCaption = "Voice"
    static let languagesCaption = "Languages"
    static let youSpeakTitle = "You speak"
    static let theySpeakTitle = "They speak"
    static let chooseLanguageTitle = "Choose…"
    static let youSpeakHintText = "The language you speak; what you say is spoken to them in their language"
    static let theySpeakHintText = "The other person's language; what you say is spoken to them in it"
    static let noVoiceValueSuffix = ", no voice on this iPhone"
    static let volumeHelpText = "How loud ReVox's own voice is; other apps are not affected"
    static let lockedDetailText = "Stop to change the dimmed controls — ReVox reads them once, at Start."

    /// "Spanish, no voice on this iPhone": the crossed speaker is never the only signal.
    static func theySpeakAccessibilityValue(name: String, hasVoice: Bool) -> String {
        hasVoice ? name : name + noVoiceValueSuffix
    }

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

/// The one visible word about the lock, under the groups: static text, not a control (about 18 pt), so tapping
/// Start dims the pills in place and moves nothing under the finger.
struct LiveLockedLine: View {
    var body: some View {
        Label(LiveControlStrip.lockedText, systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(LiveView.lockedWhileRunningText)
    }
}

/// The rarely needed words behind the pills, folded away by default, under the same three headings as the rows so
/// VoiceOver can jump by heading: a locked line while a run is going, what the source listens to, what the preset
/// waits for, ducking, volume, what Two-way will do in the people's languages (plus the missing-voice and
/// pinned-source notes), and Learning. Expanded and collapsed per launch only (`@State` in `LiveView`).
struct LiveDetailsPanel: View {
    let model: any LiveControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if LiveControlStrip.locksControls(in: model.state) {
                detail(LiveControlStrip.lockedDetailText, systemImage: "lock.fill")
            }
            heading(LiveControlStrip.listenCaption)
            detail(LiveView.description(for: model.captureMode), systemImage: LiveView.symbol(for: model.captureMode))
            detail(LiveControlStrip.latencyDetailText(for: model.latencyMode), systemImage: LiveControlStrip.latencySymbol(for: model.latencyMode))
            heading(LiveControlStrip.voiceCaption)
            detail(LiveControlStrip.duckingHelpText, systemImage: "waveform.badge.minus")
            detail(LiveControlStrip.volumeHelpText, systemImage: "speaker.wave.2")
            heading(LiveControlStrip.languagesCaption)
            detail(model.isTwoWay ? LiveView.twoWaySummary(you: model.ignoredLanguage, they: model.theySpeak)
                                  : LiveView.twoWayOffSummary(you: model.ignoredLanguage),
                   systemImage: "arrow.left.arrow.right")
            if let note = model.twoWayVoiceNote {
                detail(note, systemImage: "speaker.slash")
            }
            if let note = model.pinnedSourceNote {
                detail(note, systemImage: "pin")
            }
            detail(LiveControlStrip.learningHelpText, systemImage: "text.book.closed")
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

    private func heading(_ caption: String) -> some View {
        Text(caption)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .accessibilityLabel(caption)
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .accessibilityElement(children: .combine)
    }
}
