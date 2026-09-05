import SwiftUI

/// VOICE: ducking (read at Start, so it locks) and the voice volume (live: the players read it per clip, M9).
struct LiveVoiceGroup: View {
    let model: any LiveControlsModel
    @Binding var showsVolumeSlider: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        LiveControlGroup(caption: LiveControlStrip.voiceCaption) {
            duckingPill
            volumePill
        }
    }

    private var duckingPill: some View {
        Toggle(isOn: Binding(get: { model.ducking }, set: { model.ducking = $0 })) {
            LiveControlPill(systemImage: "waveform.badge.minus",
                            title: LiveControlStrip.togglePillTitle(LiveControlStrip.duckingPillName, isOn: model.ducking), isOn: model.ducking)
        }
        .toggleStyle(LivePillToggleStyle())
        .disabled(isLocked)
        .accessibilityLabel("Ducking")
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveControlStrip.duckingHelpText)
    }

    /// Live during a run: the pill shows the level and opens the slider under the strip rather than a sheet.
    private var volumePill: some View {
        Button {
            if reduceMotion { showsVolumeSlider.toggle() } else { withAnimation(.default) { showsVolumeSlider.toggle() } }
        } label: {
            LiveControlPill(systemImage: LiveControlStrip.volumeSymbol(for: model.voiceVolume),
                            title: LiveControlStrip.volumePillText(model.voiceVolume), isOn: showsVolumeSlider)
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel(LiveControlStrip.volumePillName)
        .accessibilityValue(LiveControlStrip.volumePercentText(model.voiceVolume))
        .accessibilityHint(showsVolumeSlider ? LiveControlStrip.hideVolumeHintText : LiveControlStrip.showVolumeHintText)
    }
}

/// The slider the volume pill unfolds under the whole strip.
struct LiveVolumeRow: View {
    let model: any LiveControlsModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(value: Binding(get: { model.voiceVolume }, set: { model.voiceVolume = $0 }), in: 0...1, step: 0.05) {
                Text(LiveControlStrip.volumePillName)
            }
            .accessibilityValue(LiveControlStrip.volumePercentText(model.voiceVolume))
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: LiveControlPill.minimumHeight)
        .padding(.horizontal)
    }
}
