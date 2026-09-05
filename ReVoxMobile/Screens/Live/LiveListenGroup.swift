import SwiftUI
import ReVoxCore

/// LISTEN: the source, the latency preset and the ⓘ — the last member of the row and of its VoiceOver container.
/// Source and latency are read once at Start, so they lock; the ⓘ never does.
struct LiveListenGroup: View {
    let model: any LiveControlsModel
    @Binding var isMoreExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLocked: Bool { LiveControlStrip.locksControls(in: model.state) }

    var body: some View {
        LiveControlGroup(caption: LiveControlStrip.listenCaption) {
            sourcePill
            latencyPill
            morePill
        }
    }

    private var sourcePill: some View {
        Menu {
            Picker(LiveControlStrip.sourceAccessibilityLabel, selection: Binding(get: { model.captureMode }, set: { model.captureMode = $0 })) {
                ForEach(LiveView.availableSources, id: \.self) { mode in
                    Label(LiveView.title(for: mode), systemImage: LiveView.symbol(for: mode)).tag(mode)
                }
            }
        } label: {
            LiveControlPill(systemImage: LiveView.symbol(for: model.captureMode), title: LiveControlStrip.sourcePillTitle(for: model.captureMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.sourceAccessibilityLabel)
        .accessibilityValue(LiveView.title(for: model.captureMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : LiveView.description(for: model.captureMode))
    }

    private var latencyPill: some View {
        Menu {
            Picker(LiveControlStrip.latencyAccessibilityLabel, selection: Binding(get: { model.latencyMode }, set: { model.latencyMode = $0 })) {
                ForEach(SegmenterPreset.allCases, id: \.self) { preset in
                    Label(SettingsView.title(for: preset), systemImage: LiveControlStrip.latencySymbol(for: preset)).tag(preset)
                }
            }
        } label: {
            LiveControlPill(systemImage: LiveControlStrip.latencySymbol(for: model.latencyMode), title: SettingsView.title(for: model.latencyMode))
        }
        .disabled(isLocked)
        .accessibilityLabel(LiveControlStrip.latencyAccessibilityLabel)
        .accessibilityValue(SettingsView.title(for: model.latencyMode))
        .accessibilityHint(isLocked ? LiveView.lockedWhileRunningText : SettingsViewModel.presetDescription(model.latencyMode))
    }

    /// Symbol only, 44 pt round: the one control whose glyph says it all (ⓘ, the system's own "details").
    private var morePill: some View {
        Button {
            if reduceMotion { isMoreExpanded.toggle() } else { withAnimation(.default) { isMoreExpanded.toggle() } }
        } label: {
            Label(LiveControlStrip.moreTitle(expanded: isMoreExpanded), systemImage: isMoreExpanded ? "chevron.up.circle" : "info.circle")
                .labelStyle(.iconOnly)
                .font(.subheadline)
                .foregroundStyle(isMoreExpanded ? Color.accentColor : Color.secondary)
                .frame(width: LiveControlPill.minimumHeight, height: LiveControlPill.minimumHeight)
                .background(isMoreExpanded ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground), in: Circle())
                .overlay(Circle().strokeBorder(isMoreExpanded ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityLabel(LiveControlStrip.moreAccessibilityLabel)
        .accessibilityValue(LiveControlStrip.moreTitle(expanded: isMoreExpanded))
        .accessibilityHint(isMoreExpanded ? LiveControlStrip.lessHintText : LiveControlStrip.moreHintText)
    }
}
