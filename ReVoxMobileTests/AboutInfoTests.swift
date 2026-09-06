import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class AboutInfoTests: XCTestCase {
    func testVersionTextAndDefaults() {
        XCTAssertEqual(AboutInfo(infoDictionary: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "42"]).versionText, "1.0.0 (42)")
        XCTAssertEqual(AboutInfo(infoDictionary: [:]).versionText, "0 (0)")
        XCTAssertEqual(AboutInfo(marketingVersion: "1.2.3", buildNumber: "7").versionText, "1.2.3 (7)")
    }

    func testCurrentReadsTheHostBundle() {
        let info = AboutInfo.current(bundle: Bundle(for: AboutInfoTests.self))
        XCTAssertFalse(info.marketingVersion.isEmpty)
        XCTAssertFalse(info.buildNumber.isEmpty)
    }

    func testLicencesAreTheFiveCatalogNoticesInOrder() {
        let info = AboutInfo(marketingVersion: "1.0.0", buildNumber: "1")
        XCTAssertEqual(info.licences.map(\.name), ["WhisperKit", "FluidAudio", "pocket-tts Core ML weights", "Silero VAD", "Whisper weights (OpenAI)"])
        XCTAssertEqual(info.licences.map(\.licence), ["MIT", "Apache-2.0", "CC-BY-4.0", "MIT", "MIT"])
        XCTAssertEqual(info.licences.map(\.url.absoluteString), [
            "https://github.com/argmaxinc/WhisperKit",
            "https://github.com/FluidInference/FluidAudio",
            "https://huggingface.co/FluidInference/pocket-tts-coreml",
            "https://github.com/snakers4/silero-vad",
            "https://github.com/openai/whisper",
        ])
    }

    func testKyutaiAttributionComesFromTheCatalog() {
        let info = AboutInfo(marketingVersion: "1.0.0", buildNumber: "1")
        XCTAssertEqual(info.pocketTTSAttributionText, "pocket-tts voices: pocket-tts by Kyutai (https://kyutai.org), Core ML weights under CC-BY-4.0.")
        XCTAssertEqual(ModelCatalog.licences.first { $0.id == AboutInfo.pocketTTSLicenceID }?.attribution, "pocket-tts by Kyutai (https://kyutai.org)")
    }

    func testStaticTexts() {
        XCTAssertEqual(AboutInfo.appName, "ReVox")
        XCTAssertEqual(AboutInfo.appLicenceText, "ReVox Mobile is open source under the MIT licence.")
        XCTAssertTrue(AboutInfo.privacyText.contains("never uses the network"))
        XCTAssertEqual(AboutInfo.windowsProjectURL.absoluteString, "https://github.com/mchrisgm/ReVox")
        XCTAssertEqual(AboutInfo.platformLimitationsURL.absoluteString, "https://github.com/mchrisgm/ReVoxMobile#platform-limitations")
    }
}
