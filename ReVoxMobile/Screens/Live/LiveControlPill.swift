import SwiftUI

/// One pill of the Live control strip (M10): a symbol, a short title and, where the control carries one, its
/// current value — at least 44 pt tall so the whole capsule is a real tap target. The pill is a label only; the
/// `Menu`, `Toggle` or `Button` around it owns the behaviour and the accessibility label, value and hint. A
/// locked control dims through the environment (`.disabled` on the control), so no caller has to remember to.
///
/// State is never colour alone (§8.8): an "on" pill also says so in its title and swaps to a filled symbol.
struct LiveControlPill: View {
    static let minimumHeight: CGFloat = 44
    static let lockedOpacity = 0.45

    let systemImage: String
    let title: String
    var value: String? = nil
    var isOn = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(minHeight: Self.minimumHeight)
        .background(isOn ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : Self.lockedOpacity)
    }
}

/// Press feedback that changes opacity only, so the row never shifts under a finger (stable interaction states).
struct LivePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A `Toggle` drawn as a pill: the toggle keeps its binding, the label is a `LiveControlPill` the caller builds
/// with the current state, and tapping anywhere on the capsule flips it. The spoken value is set here so a
/// custom style never loses it.
struct LivePillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(LivePillButtonStyle())
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
