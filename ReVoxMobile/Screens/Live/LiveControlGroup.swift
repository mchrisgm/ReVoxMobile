import SwiftUI

/// The caption at the head of a group's row: drawn uppercase, read by VoiceOver in its own case as a heading.
struct LiveGroupCaption: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: LiveControlStrip.captionColumnWidth, minHeight: LiveControlPill.minimumHeight, alignment: .leading)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One captioned row of the strip (M11 §1): the caption is the first subview of the group's own `PillFlowLayout`,
/// so the pills align across rows and wrapping stays inside the group; at accessibility type sizes the caption
/// moves above its pills (the `LiveTranscriptRowView.entryRow` precedent). The group is one VoiceOver container
/// named by its caption.
struct LiveControlGroup<Pills: View>: View {
    let caption: String
    @ViewBuilder let pills: () -> Pills
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    LiveGroupCaption(title: caption)
                    PillFlowLayout(spacing: LiveControlStrip.pillSpacing) { pills() }
                }
            } else {
                PillFlowLayout(spacing: LiveControlStrip.pillSpacing) {
                    LiveGroupCaption(title: caption)
                    pills()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(caption)
    }
}
