import XCTest
import SwiftUI
import AVFAudio
import ReVoxCore
@testable import ReVoxMobile

/// M11 §2: what the popover says for every source combination, the model that resolves a tapped word, the
/// services it reaches through the environment, and the row's selection hand-off.
@MainActor
final class WordPopoverTests: XCTestCase {
    private let sentence = "¿Dónde está la estación?"
    private let english = "Where is the station?"

    private func lookup(hasVoice: Bool = false, hasDefinition: Bool = false,
                        translator: WordTranslatorAvailability = .unavailableOnThisiOS, speaker: WordSpeaker? = nil) -> WordLookup {
        WordLookup(speaker: speaker, hasVoice: { _ in hasVoice }, hasDefinition: { _ in hasDefinition },
                   translatorAvailability: { _ in translator })
    }

    // MARK: The environment value

    /// Every hosted test row gets this: no speaker, no voice, no dictionary, iOS 17 copy — and no framework touched.
    func testTheDefaultLookupIsHonestAndInert() async {
        let lookup = WordLookup.unavailable
        XCTAssertNil(lookup.speaker)
        XCTAssertFalse(lookup.hasVoice("es"))
        XCTAssertFalse(lookup.hasDefinition("estación"))
        let availability = await lookup.translatorAvailability("es")
        XCTAssertEqual(availability, .unavailableOnThisiOS)
    }

    /// The production services: the speaker's cached voice list and the translator probe. The probe never
    /// downloads; the CI simulator runs iOS 18 or later, so the answer is one of the three iOS 18 cases.
    func testTheProductionLookupReadsTheSpeakersVoicesAndTheProbe() async {
        let speaker = WordSpeaker(voices: { AVSpeechSynthesisVoice.speechVoices() }, speak: { _ in }, stop: {})
        let lookup = WordLookup.production(speaker: speaker)
        XCTAssertTrue(lookup.speaker === speaker)
        XCTAssertFalse(lookup.hasVoice("zz"))
        XCTAssertTrue(lookup.hasVoice("en"), "every iPhone speaks English")
        let availability = await lookup.translatorAvailability("es")
        XCTAssertNotEqual(availability, .unavailableOnThisiOS, "the iOS 18 branch answered; which case depends on the simulator's packs")
        let probed = await WordTranslatorProbe.availability(language: "es")
        XCTAssertEqual(probed, availability)
    }
}
