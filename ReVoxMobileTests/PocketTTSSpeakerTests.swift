import XCTest
import ReVoxCore
@testable import ReVoxMobile

final class PocketTTSSpeakerTests: XCTestCase {
    /// The Windows `FakeTTSModel`: records voice-state requests and generate calls, returns 2 400 ones.
    private final class FakeEngine: @unchecked Sendable {
        private let lock = NSLock()
        private var initializeCalls = 0
        private var voiceRequests: [String] = []
        private var generateCalls: [(text: String, voice: String)] = []
        var failInitialize = false
        var failSynthesis = false

        var initializes: Int { lock.lock(); defer { lock.unlock() }; return initializeCalls }
        var voices: [String] { lock.lock(); defer { lock.unlock() }; return voiceRequests }
        var texts: [String] { lock.lock(); defer { lock.unlock() }; return generateCalls.map(\.text) }
        var synthesizedVoices: [String] { lock.lock(); defer { lock.unlock() }; return generateCalls.map(\.voice) }

        var engine: PocketTTSSpeaker.Engine {
            PocketTTSSpeaker.Engine(
                initialize: { [self] in
                    lock.lock(); initializeCalls += 1; let fail = failInitialize; lock.unlock()
                    if fail { throw SpeakerError.synthesisFailed("initialize refused") }
                },
                setVoice: { [self] voice in
                    lock.lock(); voiceRequests.append(voice); lock.unlock()
                },
                synthesize: { [self] text, voice in
                    lock.lock(); generateCalls.append((text, voice)); let fail = failSynthesis; lock.unlock()
                    if fail { throw SpeakerError.synthesisFailed("synthesis refused") }
                    return [Float](repeating: 1, count: 2_400)
                }
            )
        }
    }

    func testLoadIsIdempotent() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "javert", engine: fake.engine)
        try await speaker.load()
        try await speaker.load()
        XCTAssertEqual(fake.initializes, 1)
        let count = await speaker.initializeCount
        XCTAssertEqual(count, 1)
        let loaded = await speaker.isLoaded
        XCTAssertTrue(loaded)
        XCTAssertEqual(speaker.sampleRate, 24_000, "fixed once loaded and never re-queried from the engine")
        XCTAssertEqual(PocketTTSSpeaker.sampleRateHz, 24_000)
    }

    func testSynthesizeUsesLoadedManager() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "alba", engine: fake.engine)
        try await speaker.load()
        let first = try await speaker.synthesize("Hello world")
        let second = try await speaker.synthesize("Again")
        XCTAssertEqual(first.samples.count, 2_400)
        XCTAssertEqual(first.sampleRate, 24_000)
        XCTAssertEqual(second.samples.count, 2_400)
        XCTAssertEqual(fake.texts, ["Hello world", "Again"])
        XCTAssertEqual(fake.synthesizedVoices, ["alba", "alba"])
        XCTAssertEqual(fake.initializes, 1, "no reload between phrases")
    }

    func testWhitespaceReturnsEmptyClipWithoutEngine() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "alba", engine: fake.engine)
        let clip = try await speaker.synthesize("   \n\t")
        XCTAssertTrue(clip.isEmpty)
        XCTAssertEqual(clip.sampleRate, 24_000)
        XCTAssertEqual(fake.initializes, 0)
        XCTAssertEqual(fake.texts, [])
    }

    func testSetVoiceForwardsToManager() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "alba", engine: fake.engine)
        _ = try await speaker.synthesize("hi")
        await speaker.setVoice("cosette")
        _ = try await speaker.synthesize("again")
        XCTAssertEqual(fake.voices, ["cosette"], "setDefaultVoice forwarded once")
        XCTAssertEqual(fake.synthesizedVoices, ["alba", "cosette"], "the next synthesis carries the new voice")
        let voice = await speaker.voice
        XCTAssertEqual(voice, "cosette")
    }

    func testOnlyOfferedVoicesAreEverSynthesised() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "michael", engine: fake.engine)
        _ = try await speaker.synthesize("hi")
        XCTAssertEqual(fake.synthesizedVoices, ["alba"], "an unknown voice maps to alba, whose file the installed check guarantees")
        await speaker.setVoice("bogus")
        XCTAssertEqual(fake.voices, ["alba"])
        XCTAssertEqual(PocketTTSSpeaker.offeredVoice("azelma"), "azelma")
        XCTAssertEqual(PocketTTSSpeaker.offeredVoice("system"), "alba")
    }

    func testSynthesizeLoadsOnDemand() async throws {
        let fake = FakeEngine()
        let speaker = PocketTTSSpeaker(voice: "alba", engine: fake.engine)
        _ = try await speaker.synthesize("hi")
        XCTAssertEqual(fake.initializes, 1)
        let loaded = await speaker.isLoaded
        XCTAssertTrue(loaded)
    }

    func testInitializeFailurePropagatesAndTheNextLoadRetries() async {
        let fake = FakeEngine()
        fake.failInitialize = true
        let speaker = PocketTTSSpeaker(voice: "alba", engine: fake.engine)
        do {
            try await speaker.load()
            XCTFail("expected the initialize error")
        } catch {
            XCTAssertEqual(error as? SpeakerError, .synthesisFailed("initialize refused"))
        }
        var loaded = await speaker.isLoaded
        XCTAssertFalse(loaded)
        fake.failInitialize = false
        try? await speaker.load()
        loaded = await speaker.isLoaded
        XCTAssertTrue(loaded)
        XCTAssertEqual(fake.initializes, 2)
    }
}
