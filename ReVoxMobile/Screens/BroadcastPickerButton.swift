import ReplayKit
import SwiftUI

/// `RPSystemBroadcastPickerView` (C3, §6.2, §8.2): the only way an app can offer to start a system broadcast. The user
/// must tap it; ReVox cannot start or stop a broadcast programmatically. The microphone button is hidden (§11).
struct BroadcastPickerButton: UIViewRepresentable {
    static let size: CGFloat = 50
    static let captionText = "Tap to choose ReVox and start the broadcast. You can also start it from Control Center's Screen Recording control."
    static let footnoteText = "Locking the iPhone with the side button ends the broadcast."

    let preferredExtension: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.preferredExtension = preferredExtension
        view.showsMicrophoneButton = false
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Start broadcast"
        view.accessibilityHint = "Opens the system sheet to start sending other apps' audio to ReVox"
        return view
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        uiView.preferredExtension = preferredExtension
    }
}
