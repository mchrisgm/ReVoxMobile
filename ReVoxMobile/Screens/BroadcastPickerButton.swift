import ReplayKit
import SwiftUI

/// `RPSystemBroadcastPickerView` (C3, §6.2, §8.2): the only way an app can offer to start a system broadcast. The user
/// must tap it; ReVox cannot start or stop a broadcast programmatically. The microphone button is hidden (§11).
struct BroadcastPickerButton: UIViewRepresentable {
    static let size: CGFloat = 50
    static let captionText = "Tap to choose ReVox and start the broadcast. You can also start it from Control Center's Screen Recording control."
    static let footnoteText = "Locking the iPhone with the side button ends the broadcast."
    static let accessibilityLabelText = "Choose ReVox and start the broadcast"
    static let accessibilityHintText = "Opens the system broadcast sheet"

    let preferredExtension: String

    /// The single source of the picker's VoiceOver identity (§8.8). `makeUIView` calls it; the test calls it on a
    /// view it builds itself, because `UIViewRepresentableContext` has no public initializer.
    static func configure(_ view: RPSystemBroadcastPickerView, preferredExtension: String) {
        view.preferredExtension = preferredExtension
        view.showsMicrophoneButton = false
        view.isAccessibilityElement = true
        view.accessibilityLabel = accessibilityLabelText
        view.accessibilityHint = accessibilityHintText
    }

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        Self.configure(view, preferredExtension: preferredExtension)
        return view
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = preferredExtension
    }
}
