import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class UserFacingErrorTextTests: XCTestCase {
    private enum Plain: Error { case broke }
    private struct Spoken: LocalizedError { var errorDescription: String? { "The disk is full." } }
    private enum Silent: LocalizedError, CustomStringConvertible {
        case one
        var errorDescription: String? { nil }
        var description: String { "described" }
    }

    func testReVoxErrorsKeepTheirSentence() {
        let missing = ModelInstallError.filesMissingAfterDownload("pocket-tts")
        XCTAssertEqual(UserFacingErrorText.describe(missing), String(describing: missing))
        XCTAssertEqual(UserFacingErrorText.describe(SpeakerError.noVoice), SpeakerError.noVoice.description)
        XCTAssertEqual(UserFacingErrorText.describe(PipelineBuildError.vadLoadFailed("x")), "Voice detector failed to load. Re-download it in Models.")
        XCTAssertEqual(UserFacingErrorText.describe(CaptureError.microphoneDenied), "Microphone access is off for ReVox")
    }

    /// The case that reached a user: a Whisper download after airplane mode showed `URLError(_nsError: …)`.
    func testFoundationBridgedErrorsUseTheirLocalizedSentence() {
        let offline = URLError(.notConnectedToInternet)
        let text = UserFacingErrorText.describe(offline)
        XCTAssertEqual(text, offline.localizedDescription)
        XCTAssertFalse(text.contains("_nsError"))
        XCTAssertFalse(text.hasPrefix("URLError("))

        let cocoa = CocoaError(.fileNoSuchFile)
        XCTAssertEqual(UserFacingErrorText.describe(cocoa), cocoa.localizedDescription)

        let refused = NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Refused."])
        XCTAssertEqual(UserFacingErrorText.describe(refused), "Refused.")
    }

    func testLocalizedErrorWinsAndAPlainSwiftErrorNeverReadsAsAnOperationThatCouldNotBeCompleted() {
        XCTAssertEqual(UserFacingErrorText.describe(Spoken()), "The disk is full.")
        XCTAssertEqual(UserFacingErrorText.describe(Silent.one), "described", "a nil errorDescription falls through to the description")
        XCTAssertEqual(UserFacingErrorText.describe(Plain.broke), "broke")
        XCTAssertEqual(UserFacingErrorText.describe(CancellationError()), String(describing: CancellationError()))
    }
}
