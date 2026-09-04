import XCTest
import ReplayKit
@testable import ReVoxMobile

final class LiveStatusAccessibilityTests: XCTestCase {
    func testSystemVoiceSentence() {
        let label = LiveStatusAccessibility.label(modelStatus: "small · ready", voiceStatus: "System voice — pocket-tts not downloaded",
                                                  isFallingBehind: false, duckingStatus: nil, sessionStatus: nil, broadcastStatus: nil)
        XCTAssertEqual(label, "Model small ready. Using system voice: pocket-tts not downloaded.")
    }

    func testPocketTTSSentenceWithEveryPill() {
        let label = LiveStatusAccessibility.label(modelStatus: "small · ready", voiceStatus: "alba (pocket-tts)",
                                                  isFallingBehind: true, duckingStatus: "Ducking", sessionStatus: "Translation paused by iOS",
                                                  broadcastStatus: "Broadcast attached")
        XCTAssertEqual(label, "Model small ready. Using alba (pocket-tts). Falling behind. Ducking. Translation paused by iOS. Broadcast attached.")
    }

    /// §8.2 lists the broadcast attach state as the last item of the status line, and the line is one combined
    /// element, so the sentence builder must carry it; M5's label ended with `broadcastStatusText`.
    func testBroadcastAttachStateIsTheLastSentence() {
        let label = LiveStatusAccessibility.label(modelStatus: "small · ready", voiceStatus: "System voice",
                                                  isFallingBehind: false, duckingStatus: nil, sessionStatus: nil,
                                                  broadcastStatus: "Broadcast attached")
        XCTAssertEqual(label, "Model small ready. Using system voice. Broadcast attached.")
    }

    func testPreparingKeepsItsEllipsisAndPlainSystemVoice() {
        let label = LiveStatusAccessibility.label(modelStatus: "Preparing…", voiceStatus: "System voice",
                                                  isFallingBehind: false, duckingStatus: "Ducking off", sessionStatus: nil, broadcastStatus: nil)
        XCTAssertEqual(label, "Model Preparing… Using system voice. Ducking off.")
    }

    func testNoModel() {
        let label = LiveStatusAccessibility.label(modelStatus: "No model", voiceStatus: "System voice",
                                                  isFallingBehind: false, duckingStatus: nil, sessionStatus: nil, broadcastStatus: nil)
        XCTAssertEqual(label, "Model No model. Using system voice.")
    }

    func testPercentText() {
        XCTAssertEqual(LiveStatusAccessibility.percentText(0.421), "42 percent")
        XCTAssertEqual(LiveStatusAccessibility.percentText(1), "100 percent")
        XCTAssertEqual(LiveStatusAccessibility.percentText(nil), "0 percent")
        XCTAssertEqual(LiveStatusAccessibility.percentText(-0.5), "0 percent")
        XCTAssertEqual(LiveStatusAccessibility.percentText(1.7), "100 percent")
    }

    /// `makeUIView` is the single source of the picker's VoiceOver label and hint; it delegates to `configure`, so
    /// this asserts the label on a real configured view and fails if the shipped M5 wording is left in place.
    /// (`UIViewRepresentableContext` has no public initializer, so `makeUIView` cannot be called directly.)
    @MainActor
    func testPickerConfigurationSetsTheLabelOnTheUIKitView() {
        let view = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: BroadcastPickerButton.size, height: BroadcastPickerButton.size))
        BroadcastPickerButton.configure(view, preferredExtension: "com.example.revox.Broadcast")
        XCTAssertEqual(BroadcastPickerButton.accessibilityLabelText, "Choose ReVox and start the broadcast")
        XCTAssertEqual(BroadcastPickerButton.accessibilityHintText, "Opens the system broadcast sheet")
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertEqual(view.accessibilityLabel, BroadcastPickerButton.accessibilityLabelText)
        XCTAssertEqual(view.accessibilityHint, BroadcastPickerButton.accessibilityHintText)
        XCTAssertEqual(view.preferredExtension, "com.example.revox.Broadcast")
        XCTAssertFalse(view.showsMicrophoneButton)
    }
}
