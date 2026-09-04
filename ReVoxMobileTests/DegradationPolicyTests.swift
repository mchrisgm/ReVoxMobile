import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class DegradationPolicyTests: XCTestCase {
    private let allSmall: [WhisperModelID] = [.tiny, .base, .small]

    @discardableResult
    private func react(_ signal: DeviceSignal, state: inout DegradationState, selected: WhisperModelID = .small,
                       installed: [WhisperModelID]? = nil, usesPocketTTS: Bool = false) -> [DegradationEffect] {
        DegradationPolicy.react(to: signal, state: &state, selectedModel: selected,
                                installedModels: installed ?? allSmall, usesPocketTTS: usesPocketTTS)
    }

    func testFirstMemoryWarningDropsPocketTTSThenPressureShrinksTheModel() {
        var state = DegradationState()
        XCTAssertEqual(react(.memoryWarning, state: &state, usesPocketTTS: true),
                       [.unloadPocketTTS, .banner("Memory low: switched to the system voice")])
        XCTAssertTrue(state.pocketTTSDropped)
        XCTAssertNil(state.reducedModel)
        XCTAssertEqual(state.memoryWarnings, 1)

        XCTAssertEqual(react(.memoryWarning, state: &state, usesPocketTTS: true),
                       [.useModel(.base, restartRunning: true), .banner("Memory low: switched to base")],
                       "pocket-tts is given up once; further pressure shrinks the model, and memory switches at once")
        XCTAssertEqual(state.reducedModel, .base)

        XCTAssertEqual(react(.memoryWarning, state: &state),
                       [.useModel(.tiny, restartRunning: true), .banner("Memory low: switched to tiny")],
                       "the next step starts from the model already in use")
        XCTAssertEqual(react(.memoryWarning, state: &state), [], "tiny is the smallest installed model")
        XCTAssertEqual(state.memoryWarnings, 4)
    }

    func testMemoryWarningWithTheSystemVoiceGoesStraightToASmallerModel() {
        var state = DegradationState()
        XCTAssertEqual(react(.memoryWarning, state: &state, usesPocketTTS: false),
                       [.useModel(.base, restartRunning: true), .banner("Memory low: switched to base")])
        XCTAssertFalse(state.pocketTTSDropped)
    }

    func testAWhisperFailureAfterAMemoryWarningIsTheEvictionSignal() {
        var state = DegradationState()
        XCTAssertEqual(DegradationPolicy.reactToWhisperFailure(state: &state, selectedModel: .small, installedModels: allSmall),
                       [], "§9 asks for the step-down only once memory pressure is on the record")
        XCTAssertNil(state.reducedModel)

        react(.memoryWarning, state: &state, usesPocketTTS: true)   // the first warning only drops pocket-tts
        XCTAssertNil(state.reducedModel)
        XCTAssertEqual(DegradationPolicy.reactToWhisperFailure(state: &state, selectedModel: .small, installedModels: allSmall),
                       [.useModel(.base, restartRunning: true), .banner("Memory low: switched to base")],
                       "§9: Whisper failing after a memory warning is the eviction the row names")
        XCTAssertEqual(state.reducedModel, .base)
        XCTAssertEqual(state.memoryWarnings, 1, "a Whisper failure is not itself a memory warning")

        XCTAssertEqual(DegradationPolicy.reactToWhisperFailure(state: &state, selectedModel: .small, installedModels: [.small]),
                       [], "nothing smaller than the reduced model is installed")
        XCTAssertEqual(state.reducedModel, .base)
    }

    func testSeriousReducesOnceForTheNextSessionAndTheRecoveryRestoresTheUsersModel() {
        var state = DegradationState()
        XCTAssertEqual(react(.thermalState(.serious), state: &state),
                       [.useModel(.base, restartRunning: false), .banner("iPhone is hot: translation reduced")],
                       "§9: the smaller model is preferred for new sessions, so a running one is not rebuilt")
        XCTAssertEqual(state.reducedModel, .base)
        XCTAssertEqual(react(.thermalState(.serious), state: &state), [], "a repeated .serious does not step down again")
        XCTAssertEqual(react(.thermalState(.fair), state: &state),
                       [.useModel(.small, restartRunning: false), .banner("iPhone cooled down: translation resumed")])
        XCTAssertNil(state.reducedModel)
        XCTAssertEqual(state.thermalState, .fair)
    }

    func testCriticalPausesAndTheRecoveryResumes() {
        var state = DegradationState()
        XCTAssertEqual(react(.thermalState(.critical), state: &state),
                       [.pauseTranslation, .banner("iPhone is hot: translation paused")])
        XCTAssertTrue(state.isPausedForHeat)
        XCTAssertEqual(react(.thermalState(.critical), state: &state), [], "already paused")
        XCTAssertEqual(react(.thermalState(.serious), state: &state),
                       [.resumeTranslation, .useModel(.base, restartRunning: false), .banner("iPhone is hot: translation reduced")])
        XCTAssertFalse(state.isPausedForHeat)
        XCTAssertEqual(react(.thermalState(.nominal), state: &state),
                       [.useModel(.small, restartRunning: false), .banner("iPhone cooled down: translation resumed")])
    }

    func testNothingSmallerInstalledMeansNothingToGiveUp() {
        var state = DegradationState()
        XCTAssertEqual(react(.thermalState(.serious), state: &state, selected: .tiny, installed: [.tiny]), [])
        XCTAssertEqual(react(.memoryWarning, state: &state, selected: .tiny, installed: [.tiny]), [])
        XCTAssertNil(state.reducedModel)
        XCTAssertEqual(state.thermalState, .serious)
    }

    func testLowPowerModeChangesNothing() {
        var state = DegradationState()
        XCTAssertEqual(react(.lowPowerMode(true), state: &state), [])
        XCTAssertEqual(state, DegradationState())
    }

    func testBannerTextsAreTheSpecTexts() {
        XCTAssertEqual(DegradationPolicy.systemVoiceText, "Memory low: switched to the system voice")
        XCTAssertEqual(DegradationPolicy.memoryModelText(.base), "Memory low: switched to base")
        XCTAssertEqual(DegradationPolicy.memoryModelText(.largeV3), "Memory low: switched to large-v3")
        XCTAssertEqual(DegradationPolicy.heatPausedText, "iPhone is hot: translation paused")
        XCTAssertEqual(DegradationPolicy.heatReducedText, "iPhone is hot: translation reduced")
        XCTAssertEqual(DegradationPolicy.heatRecoveredText, "iPhone cooled down: translation resumed")
    }
}
