import XCTest
import ReVoxCore
@testable import ReVoxMobile

/// §8.2 (M8): the seam Apple's translator reaches the pipeline through. Nothing here talks to the framework —
/// what matters is that the pipeline gets an answer only from a session serving exactly the pair it asked for,
/// gets nil rather than a throw for everything else (a throw would stop the run), and is never left waiting.
final class TranslationBridgeTests: XCTestCase {
    /// Answers every request the way a session would, until the stream ends.
    private func serve(_ bridge: TranslationBridge, from source: String, to target: String,
                       answer: @escaping @Sendable (String) -> String?) async -> Task<[String], Never> {
        let serving = await bridge.serve(from: source, to: target)
        return Task {
            var seen: [String] = []
            for await request in serving.requests {
                seen.append(request.text)
                await bridge.complete(request.id, with: answer(request.text))
            }
            await bridge.withdraw(serving.token)
            return seen
        }
    }

    func testNothingIsTranslatedUntilASessionIsServing() async throws {
        let bridge = TranslationBridge()
        let result = try await bridge.translate("Good morning.", from: "en", to: "es")
        XCTAssertNil(result)
        let pair = await bridge.servedPair
        XCTAssertNil(pair?.source)
    }

    func testAServingSessionAnswersItsOwnPair() async throws {
        let bridge = TranslationBridge()
        let task = await serve(bridge, from: "en", to: "es") { "[es] \($0)" }
        let result = try await bridge.translate("Good morning.", from: "en", to: "es")
        XCTAssertEqual(result, "[es] Good morning.")
        let pair = await bridge.servedPair
        XCTAssertEqual(pair?.source, "en")
        XCTAssertEqual(pair?.target, "es")
        await bridge.withdraw(1)
        let seen = await task.value
        XCTAssertEqual(seen, ["Good morning."])
    }

    func testAnotherPairIsNotAnsweredByThisSession() async throws {
        let bridge = TranslationBridge()
        _ = await serve(bridge, from: "en", to: "es") { "[es] \($0)" }
        let wrongTarget = try await bridge.translate("Good morning.", from: "en", to: "fr")
        XCTAssertNil(wrongTarget, "a session for en→es must not answer for en→fr")
        let wrongSource = try await bridge.translate("Buenos días.", from: "es", to: "es")
        XCTAssertNil(wrongSource)
        await bridge.withdraw(1)
    }

    func testWithdrawingStopsTheSecondDirection() async throws {
        let bridge = TranslationBridge()
        let task = await serve(bridge, from: "en", to: "es") { "[es] \($0)" }
        await bridge.withdraw(1)
        _ = await task.value
        let result = try await bridge.translate("Good morning.", from: "en", to: "es")
        XCTAssertNil(result)
    }

    /// A session that cannot produce this phrase is transcript-only, not a stopped pipeline (§8.2).
    func testASessionThatCannotAnswerGivesNil() async throws {
        let bridge = TranslationBridge()
        _ = await serve(bridge, from: "en", to: "es") { _ in nil }
        let result = try await bridge.translate("Good morning.", from: "en", to: "es")
        XCTAssertNil(result)
        await bridge.withdraw(1)
    }

    func testAnEmptyAnswerIsNotSpoken() async throws {
        let bridge = TranslationBridge()
        _ = await serve(bridge, from: "en", to: "es") { _ in "   \n " }
        let result = try await bridge.translate("Good morning.", from: "en", to: "es")
        XCTAssertNil(result)
        await bridge.withdraw(1)
    }

    /// The failure that would hang the pipeline: a session going away with a phrase still in flight.
    func testAPhraseInFlightIsReleasedWhenTheSessionGoesAway() async throws {
        let bridge = TranslationBridge()
        let serving = await bridge.serve(from: "en", to: "es")
        let asked = expectation(description: "the phrase reached the session")
        Task {
            for await _ in serving.requests {
                asked.fulfill()          // received, and deliberately never answered
            }
        }
        async let pending = bridge.translate("Good morning.", from: "en", to: "es")
        await fulfillment(of: [asked], timeout: 2)
        await bridge.withdraw(serving.token)
        let result = try await pending
        XCTAssertNil(result, "the phrase is released as transcript-only rather than left waiting")
    }

    /// A changed pair replaces the serving; the old task's later withdraw must not take the new one down.
    func testAReplacedServingCannotWithdrawItsSuccessor() async throws {
        let bridge = TranslationBridge()
        let first = await bridge.serve(from: "en", to: "es")
        let second = await bridge.serve(from: "en", to: "fr")
        await bridge.withdraw(first.token)
        let pair = await bridge.servedPair
        XCTAssertEqual(pair?.target, "fr", "the older serving withdrew nothing")
        await bridge.withdraw(second.token)
        let after = await bridge.servedPair
        XCTAssertNil(after?.target)
    }
}
