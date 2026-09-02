# ReVox Mobile — Design Specification

**Date:** 2026-09-02
**Status:** Approved scope, design for milestones 2–7
**Inputs:** owner requirements (binding scope), controller rulings R1–R15 (binding design decisions), the verified API reference for WhisperKit 1.1.0 and FluidAudio 0.15.6, the Windows reference implementation (`mchrisgm/ReVox`) and its design spec, and the milestone 0 repository state.

ReVox Mobile is the iPhone port of ReVox: it listens to audio (the microphone, or other apps through a ReplayKit Broadcast Upload Extension), cuts the stream into phrases with Silero VAD, translates every phrase to English on-device with Whisper through WhisperKit, speaks the English with Kyutai pocket-tts through FluidAudio (with the system voice as default and fallback), ducks other audio while it speaks, and stores a searchable transcript that exports in the Windows `.txt` format. This document is the implementation-ready design for milestones 2–7: the platform-independent `ReVoxCore` package that ports the Windows pipeline one-to-one, the `ReVoxMobile` adapters that bind it to iOS and to the two pinned libraries, the `ReVoxBroadcast` extension that forwards other apps' audio through a shared ring buffer, the SwiftUI screens, the error model, the test strategy, and the list of assumptions that on-device measurement must confirm milestone by milestone. Every library call named here exists in the pinned sources with the signature given in the API reference (`scratchpad/research/api-reference.md`, cited as "API §n"); anything not verified there is marked **ASSUMED** together with the milestone that measures it.

---

## 2. Goals and non-goals

### Goals

1. Run the complete ReVox pipeline on an iPhone 12 or newer under iOS 17 or later, fully on-device and offline after a one-time model download.
2. Port the Windows segmenter, quality gates, backpressure, playback and transcript logic **one-to-one** into a Foundation-only Swift package whose tests run on Linux and in the iOS simulator, mirroring the Windows tests.
3. Two audio sources: the microphone, and other apps through a Broadcast Upload Extension that stays far below the 50 MB extension memory cap.
4. Whisper model picker (tiny, base, small, medium, large-v3) with download progress, on-disk size, delete and a device-based recommendation; default small.
5. pocket-tts voices alba, azelma, cosette and javert downloaded on demand; the system voice as default until then and as automatic fallback; a voice picker listing both engines.
6. Ducking of other audio while the English voice plays, within what iOS permits, plus a voice-volume slider.
7. Local transcript history with search, session detail, `.txt` export in the Windows format and the share sheet.
8. Native SwiftUI UI following the Human Interface Guidelines; TestFlight delivery from CI.
9. No network access after installation, no analytics, no data leaving the phone.

### Non-goals (v1)

- Non-English target languages (Whisper translates only *to* English).
- iPad and macOS (`TARGETED_DEVICE_FAMILY = 1`).
- Streaming text-to-speech (phrase-level synthesis only; `synthesizeStreaming` and `PocketTtsSession` are a later enhancement).
- A content-based self-capture guard (detected-English or near-duplicate heuristics); v1 uses the timing-based `CaptureGate` only (R9).
- iOS 27 ScreenCaptureKit capture; the ReplayKit broadcast path is the only other-apps source in v1, with protocol seams for a later replacement (§12).
- Voice cloning, extra pocket-tts languages, `.aneState` placement, revision-pinned mirrors of the model repositories.
- Hotkeys, output-device selection, start-minimised, configurable transcript folder (Windows-only settings, dropped per the owner brief).

---

## 3. Requirements table

Every bullet of the owner requirements, the milestone that delivers it and the component that owns it.

| # | Requirement (owner brief) | Milestone | Owning component(s) |
|---|---|---|---|
| F1 | Audio source: microphone | M3 | `MicrophoneCapture` (app), `AudioSource` protocol (core) |
| F2 | Audio source: other apps through a Broadcast Upload Extension | M5 | `ReVoxBroadcast/SampleHandler`, `BroadcastCapture` (app), `RingWriter`/`RingReader` (core) |
| F3 | Speech-to-English with WhisperKit, task translate | M3 | `WhisperKitTranslator` (app), `Translator`/`LanguageDetector` protocols (core) |
| F4 | Model picker tiny/base/small/medium/large-v3 with progress, size, delete, device recommendation; default small; no turbo/distil | M3 (picker, progress, delete), M7 (storage accounting, delete-while-idle) | `ModelCatalog`, `DeviceRecommendation` (core), `ModelManager`, Models screen (app) |
| F5 | pocket-tts through FluidAudio with alba, azelma, cosette, javert, downloaded on demand | M4 | `PocketTTSSpeaker`, `ModelManager` (app) |
| F6 | AVSpeechSynthesizer default until pocket-tts is downloaded and automatic fallback on load/synthesis failure; picker lists both engines | M3 (system voice), M4 (fallback, Voices screen) | `SystemSpeaker`, `EffectiveSpeaker`, Voices screen (app) |
| F7 | Segmentation presets Balanced and Fast ported exactly | M2 | `Segmenter` (core) |
| F8 | Source-language pin (blank = auto-detect) with a language-probability gate identical to Windows | M2 (gate), M3 (detection adapter, Settings field) | `SpeechGate`, `TranslationStage` (core), `WhisperKitTranslator` (app) |
| F9 | Hallucination guard and per-segment quality gates identical to Windows | M2 | `SpeechGate` (core) |
| F10 | Backpressure: at most 3 pending segments, oldest dropped, drop marker in the transcript | M2 | `BoundedSegmentQueue`, `TranslationPipeline`, `TranscriptFormatter` (core) |
| F11 | Mute toggle that silences the voice while the transcript keeps running | M3 (toggle), M4 (semantics verified with both engines) | `PlaybackQueue`, `TranslationPipeline` (core), `AudioPlayer` (app) |
| F12 | Ducking of other apps while the English voice plays | M4 | `DuckingCoordinator` (core), `AudioSessionController` (app) |
| F13 | Transcript history stored locally: history screen, search, per-session detail, `.txt` export in the Windows format, share sheet | M3 (store), M6 (screens, export, share) | `TranscriptFormatter` (core), `TranscriptStore`, History/Session screens (app) |
| F14 | Native SwiftUI UI following the HIG; iOS 17; iPhone 12 and newer | M3–M6 (HIG audit in M6) | all screens (app) |
| F15 | TestFlight delivery from CI: internal group first, public link afterwards | M3 (first build), M6/M7 (public link) | `.github/workflows/testflight.yml`, `docs/release.md` |
| P1 | Port `segmenter.py`: 512-sample chunks at 16 kHz, presets, threshold 0.5, 200 ms pre-roll, tail trimming, `flush()` | M2 | `Segmenter` (core) |
| P2 | Port `stt.py` gates: `NO_SPEECH_MAX`, `AVG_LOGPROB_MIN`, `LANGUAGE_PROB_MIN`, hallucination set, normalisation, beam 1, no conditioning, no timestamps | M2 (gates), M3 (decoding options) | `SpeechGate` (core), `WhisperKitTranslator` (app) |
| P3 | Port `pipeline.py`: three-stage queue, `max_pending = 3`, lag event, state machine, speaking callback drives ducking | M2 | `TranslationPipeline` (core) |
| P4 | Port `playback.py`: queued playback, mute discards, speaking edges | M2 (queue semantics), M3 (engine playback) | `PlaybackQueue` (core), `AudioPlayer` (app) |
| P5 | Port `transcript.py` export format including the drop marker and the empty original | M2 | `TranscriptFormatter` (core) |
| P6 | Port `config.py` fields model, language, voice, ducking, latency_mode, capture_mode; drop the rest | M2 | `Settings` (core) |
| P7 | Port `to_mono_16k` semantics | M2 (downmix, re-framing), M3 (resampling on device) | `AudioFormat` (core), `MicrophoneCapture` (app) |
| P8 | Testing approach with injected fakes; no test downloads anything | M2 onward | `ReVoxCoreTests`, `ReVoxMobileTests` |
| A1 | Three targets plus one package from a committed `project.yml`; no `.xcodeproj` committed | M0 (done), maintained | `project.yml` |
| A2 | `ReVoxCore` contents and import restrictions | M2 | `ReVoxCore` |
| A3 | `ReVoxMobile` adapters and screens | M3–M6 | `ReVoxMobile` |
| A4 | `ReVoxBroadcast`: `.audioApp` → mono 16 kHz Float32 → shared ring; no models; no per-buffer allocation | M5 | `SampleHandler` |
| A5 | App Group `group.<prefix>.revox`; mmap'd ring file with cursor header; Darwin notification; `docs/broadcast-bridge.md` | M2 (core types), M5 (adapters, document) | `RingLayout` (core), `BroadcastCapture`, `SampleHandler` |
| A6 | Data flow capture → Segmenter → queue (3) → translator → store + text queue → speaker → player → speaking edge → session controller | M2/M3 | `TranslationPipeline` |
| A7 | Self-capture suppression: gate the segmenter while speaking and for 300 ms after, with a core test | M2 (core), M5 (verified in broadcast mode) | `CaptureGate` (core) |
| C1 | Ducking as toggle + voice-volume slider, `.duckOthers` on speaking start, deactivate with `.notifyOthersOnDeactivation` on stop; README and Settings help text about the Windows ducked-level slider | M4 | `AudioSessionController`, Settings screen, README |
| C2 | Background operation with the `audio` background mode; spike in M5 before the full broadcast flow; record the working configuration | M5 | `AudioSessionController`, `docs/broadcast-bridge.md` |
| C3 | Broadcast start via `RPSystemBroadcastPickerView` with `preferredExtension`; UI explains Control Center | M5 | Live screen (`BroadcastPickerButton`) |
| C4 | Extension memory 50 MB; never load models in the extension | M5 | `SampleHandler` |
| C5 | Licences on the About screen with links (WhisperKit MIT, pocket-tts CC-BY-4.0 with Kyutai attribution, Silero VAD MIT) | M6 | `ModelCatalog.licences` (core), About screen |
| C6 | Device recommendation from `ProcessInfo.processInfo.physicalMemory` | M2 (function), M3 (badge) | `DeviceRecommendation` (core), `DeviceInfo` (app) |
| C7 | Privacy manifest reasons, export-compliance false in both plists, full icon set, `NSMicrophoneUsageDescription` | M0 (present), M3 (verified before upload) | `PrivacyInfo.xcprivacy` ×2, `Info.plist` ×2 |
| E1 | Pinned WhisperKit 1.1.0 and FluidAudio 0.15.6; never code against an unseen API | all | `project.yml`, this document |
| E2 | Xcode 26.6 on macos-26, iOS 17.0 target, Swift 5 mode, XCTest | all | CI workflows |
| E3 | Bundle ids from `REVOX_BUNDLE_PREFIX`; app reads `REVOXAppGroup` and `REVOXBroadcastExtensionBundleID` from Info.plist | M5 | `AppConfiguration` (app) |

---

## 4. Architecture overview

### 4.1 Targets and package

| Unit | Kind | Imports allowed | Role |
|---|---|---|---|
| `ReVoxCore` | Swift package (`swift-tools-version 5.10`, platforms iOS 17 / macOS 14, Linux-testable) | Foundation only. No UIKit, AVFoundation, CoreML, SwiftUI, CoreMedia, ReplayKit. | Pipeline logic ported from Windows, catalog, settings, transcript format, ring bridge types. Contains no required-reason API calls (§11). |
| `ReVoxMobile` | iOS application (SwiftUI) | Everything, plus `ReVoxCore`, `WhisperKit`, `FluidAudio` | Adapters, model management, audio session, storage, screens. |
| `ReVoxBroadcast` | Broadcast Upload Extension (`com.apple.broadcast-services-upload`, `APPLICATION_EXTENSION_API_ONLY`) | ReplayKit, CoreMedia, AVFAudio, Foundation, `ReVoxCore` (ring types only) | Converts `.audioApp` buffers to 16 kHz mono Float32 and writes them into the shared ring file. No ML, no third-party packages. |
| `ReVoxMobileTests` | XCTest bundle hosted by the app | | Adapter tests that run in the simulator without models. |

### 4.2 Data flow

```
                    ┌──────────────────────── ReVoxMobile (app process) ────────────────────────┐
 mic hardware ──► MicrophoneCapture ─┐                                                            │
                                     ├─► [Float] 16 kHz ─► CaptureGate ─► Segmenter ─► BoundedSegmentQueue (3, oldest drop, lag)
 ReVoxBroadcast ─► ring file ─► BroadcastCapture ┘  (frame counter)      (VAD 512)         │
   (extension)     (App Group)                                                              ▼
                                                                          TranslationStage: LanguageDetector (if no pin) ─► SpeechGate.languagePasses
                                                                                            └─► Translator(language) ─► SpeechGate.evaluate ─► Translation?
                                                                                                                                        │
                                                        TranscriptSink.add(entry) ◄─────────── event .entry ◄───────────────────────────┤
                                                                                                                                        ▼
                                                                          text queue ─► Speaker.synthesize ─► AudioClip ─► PlaybackQueue/AudioPlayer
                                                                                                                                        │ speaking edge
                                                                         CaptureGate.speakingChanged ◄────────────┬─────────────────────┤
                                                                         DuckingCoordinator ─► Ducker (AudioSessionController) ◄────────┘
```

Three stages, three tasks, two bounded hand-offs, exactly as `pipeline.py`: the capture task feeds the gate, the segmenter and the segment queue; the translate task drains the segment queue, applies the gates, writes the transcript and pushes English text; the speak task drains the text queue, synthesises and enqueues clips. The player's speaking edge fans out to the ducking coordinator, the capture gate and the UI.

### 4.3 Concurrency model (R12)

- `TranslationPipeline` is a `public final class` whose mutable state lives behind a private actor; its three stages are child `Task`s of one `start()` call and the hand-offs are `AsyncStream`s (segment queue, text queue) with the bounded-drop policy applied on the producer side. All protocol types the pipeline holds are `Sendable`.
- Events leave the pipeline through one `AsyncStream<PipelineEvent>`; the UI observes it on the main actor.
- App-side actors: `WhisperKitTranslator` (owns exactly one `WhisperKit`, which is a non-Sendable class, and serialises `detectLangauge`/`transcribe`), `PocketTTSSpeaker` (owns one `PocketTtsManager`), `SileroVAD` (owns one `MLModel` and the LSTM state), `ModelInstaller` (owns `ModelHub.offlineMode` transitions), `TranscriptStore` (`@ModelActor`).
- translate(N+1) may overlap speak(N): the translate task never waits for playback. ANE contention between Whisper and pocket-tts is measured in M4; if a synthesis stalls twice by more than 160 ms behind real time, the speak task serialises behind translate for the rest of the session (ASSUMED policy, M4).
- Real-time audio callbacks (`AVAudioNode` tap, `AVAudioPlayerNode` completion) never touch actors synchronously: they append to a lock-free buffer or call `continuation.yield`, and the async side re-frames.

### 4.4 What runs where (R1, C4)

- **App:** VAD (CoreML wrapper), Whisper (WhisperKit), pocket-tts (FluidAudio), AVSpeechSynthesizer, the audio engine, the audio session, SwiftData, downloads.
- **Extension:** format detection, one `AVAudioConverter`, `memcpy` into the ring, Darwin notifications, a `UserDefaults(suiteName:)` state record. Nothing else, ever.
- **Core:** everything that has a Windows counterpart plus the ring bridge types; no I/O beyond the byte-level ring accessors it is handed.

---

## 5. ReVoxCore design

Conventions: signatures only, Swift 5 language mode, `Sendable` everywhere a value crosses a task boundary, no `Synchronization` (iOS 18), no `os` framework. Constants ported from Windows carry the Windows name in a comment and are `public static let` so tests can assert them directly. Every subsection ends with the behaviours the mirrored tests assert (§10 lists the test names).

### 5.1 Segmenter

Port of `revox/pipeline/segmenter.py`. Turns a continuous 16 kHz stream into phrases using a per-chunk speech probability.

```swift
public enum SegmenterPreset: String, CaseIterable, Codable, Sendable {
    case balanced, fast
    public var silenceMs: Int { get }            // balanced 500, fast 300
    public var maxSegmentSeconds: Double { get } // balanced 10.0, fast 4.0
}

public final class Segmenter {
    public static let chunkSamples = 512          // CHUNK_SAMPLES
    public static let sampleRate = 16_000         // SAMPLE_RATE
    public static let defaultSpeechThreshold: Float = 0.5
    public static let defaultPaddingMs = 200

    public let preset: SegmenterPreset
    public let speechThreshold: Float
    public let silenceChunks: Int                 // max(1, Int(silenceMs/1000 * 16000 / 512))
    public let maxChunks: Int                     // max(1, Int(maxSegmentSeconds * 16000 / 512))
    public let paddingChunks: Int                 // max(1, Int(paddingMs/1000 * 16000 / 512))

    public init(vad: any SpeechProbabilityModel,
                preset: SegmenterPreset = .balanced,
                speechThreshold: Float = Segmenter.defaultSpeechThreshold,
                paddingMs: Int = Segmenter.defaultPaddingMs)

    /// Appends samples of any length; returns every phrase completed by this call.
    public func feed(_ samples: [Float]) async throws -> [[Float]]
    /// Emits the in-progress phrase, if any; returns nil when not in speech.
    public func flush() -> [Float]?
    /// Forgets pending samples, pre-roll and the in-progress phrase; also resets the VAD state.
    public func reset() async
}
```

Integer chunk counts (Python `int()` truncates):

| Quantity | Formula | balanced | fast |
|---|---|---|---|
| `silenceChunks` | `Int(silenceMs / 1000 × 16000 / 512)` | `Int(15.625)` = **15** (480 ms) | `Int(9.375)` = **9** (288 ms) |
| `maxChunks` | `Int(maxSegmentSeconds × 16000 / 512)` | `Int(312.5)` = **312** (9.98 s) | `Int(125.0)` = **125** (4.0 s) |
| `paddingChunks` | `Int(200 / 1000 × 16000 / 512)` | `Int(6.25)` = **6** (192 ms) | 6 |

The Swift computation must reproduce the truncation exactly: compute in `Double` and truncate with `Int(...)`, never round.

Algorithm (identical to `_process`):

1. `feed` concatenates into a pending buffer and consumes exactly 512 samples per step; a remainder shorter than 512 stays pending.
2. Per chunk: `isSpeech = try await vad.probability(of: chunk) >= speechThreshold` (VAD is called for every chunk, in speech or not, so the LSTM state matches Windows).
3. Not in speech: speech chunk starts a phrase with `preRoll + [chunk]` and `silenceRun = 0`; silence chunk goes into the pre-roll deque (`maxlen = paddingChunks`, oldest dropped).
4. In speech: append the chunk; speech resets `silenceRun`, silence increments it.
5. `silenceRun >= silenceChunks` → tail trimming: `keepTail = silenceRun − paddingChunks`; emit `segment.dropLast(max(0, keepTail))` (the phrase keeps `paddingChunks` of trailing silence).
6. Else `segment.count >= maxChunks` → emit the whole segment (no trimming).
7. `_finish`: clear segment, `silenceRun = 0`, `inSpeech = false`, **clear the pre-roll**.
8. `flush()` returns `nil` unless in speech with a non-empty segment; then emits the whole segment through `_finish`.

`SpeechProbabilityModel.reset()` is called only from `Segmenter.reset()` (session start); Windows never calls `reset_states()` during a run and neither does the port.

Mirrored test behaviours: preset values; one segment for 300 ms silence + 1 s speech + 700 ms silence with `0.8 s < length < 1.6 s`; nothing for 2 s of silence and `flush() == nil`; a 200 ms pause inside balanced does not split; a 500 ms pause inside fast splits into 2; 9 s of speech in fast emits ≥ 2 segments each ≤ 4.2 s; `flush()` after 800 ms of speech returns ≥ 0.7 s and a second `flush()` returns nil. Additionally: the chunk-count constants above, feeding in 1 600-sample slices (Windows test cadence) and in 480-sample slices gives identical segments, and the pre-roll is cleared after each emit.

### 5.2 SpeechProbabilityModel and CaptureGate (R1, R9)

```swift
/// One probability per 512-sample chunk at 16 kHz, semantics of the Silero JIT model `model(chunk, 16000)`.
public protocol SpeechProbabilityModel: Sendable {
    func probability(of chunk: [Float]) async throws -> Float   // chunk.count == 512
    func reset() async
}
```

The app implements it with the 512-sample CoreML export (§6.3). Tests implement it with an energy threshold (`mean(|x|) > 0.1 → 1.0 else 0.0`), exactly the Windows `fake_vad`.

`CaptureGate` is the self-capture suppression of R9. It sits **before** the segmenter, keyed on capture frame counts so that no host-time API is needed anywhere:

```swift
public struct CaptureGate: Sendable, Equatable {
    public static let defaultHoldFrames = 4_800          // 300 ms at 16 kHz
    public init(holdFrames: Int = CaptureGate.defaultHoldFrames)
    /// Player speaking edge, stamped with the capture frame counter at the moment of the edge.
    public mutating func speakingChanged(_ speaking: Bool, atFrame frame: Int64)
    /// True when a chunk ending at `frame` may reach the segmenter.
    public func allows(chunkEndingAt frame: Int64) -> Bool
    public var isClosed: Bool { get }
}
```

Semantics: closed from the `speaking == true` edge until `holdFrames` capture frames after the `speaking == false` edge. Chunks that arrive while closed are **dropped before the segmenter and before the VAD** (the VAD/LSTM state is untouched, the segmenter's pending buffer, pre-roll and in-progress phrase are frozen). If a phrase was in progress when the gate closed it resumes when the gate opens; the silence counter is not advanced by dropped chunks. The frame counter is the cumulative number of 16 kHz samples the `AudioSource` has delivered in this session (mic: tap frames after resampling; broadcast: ring cursor delta), so the gate applies identically in both modes (harmless in mic mode).

Mirrored/new test behaviours: chunks during speaking are dropped; chunks within 4 800 frames after the speaking-false edge are dropped; the first chunk ending after that boundary passes; a re-trigger during the hold extends it; the fake VAD is not called for dropped chunks; a segmenter phrase in progress survives a gate closure and completes afterwards.

### 5.3 SpeechGate and TranslationStage (R2, R3)

Port of the gating in `revox/pipeline/stt.py:Translator.translate`. Constants and the hallucination set are verbatim.

```swift
public struct TranslationSegment: Sendable, Equatable {
    public var text: String
    public var noSpeechProbability: Float        // seg.no_speech_prob (WhisperKit: always 0, documented)
    public var averageLogProbability: Float      // seg.avg_logprob recomputed over word tokens (R3)
    public init(text: String, noSpeechProbability: Float, averageLogProbability: Float)
}

public struct TranslationCandidate: Sendable, Equatable {
    public var language: String                  // info.language
    public var languageProbability: Float?       // info.language_probability; nil when pinned (gate skipped)
    public var segments: [TranslationSegment]
}

public struct Translation: Sendable, Equatable, Codable {
    public var english: String
    public var language: String
}

public enum SpeechGate {
    public static let noSpeechMax: Float = 0.85          // NO_SPEECH_MAX
    public static let averageLogProbMin: Float = -1.2    // AVG_LOGPROB_MIN
    public static let languageProbMin: Float = 0.4       // LANGUAGE_PROB_MIN
    public static let hallucinationPhrases: Set<String> = [
        "", "you", "thanks for watching", "thank you for watching",
        "subtitles by the amara.org community", "subscribe",
    ]
    /// Python `string.punctuation` + `string.whitespace` + "!¡¿?"
    public static let strippedCharacters: Set<Character>

    /// `text.lower().strip(strippedCharacters)`
    public static func normalize(_ text: String) -> String
    /// Windows: `settings.language is None and info.language_probability < LANGUAGE_PROB_MIN` → drop.
    public static func languagePasses(probability: Float?) -> Bool
    /// The full Windows sequence: language gate, per-segment gates, join, normalise, hallucination set.
    public static func evaluate(_ candidate: TranslationCandidate) -> Translation?
}
```

`evaluate` order, identical to Windows:

1. `languageProbability != nil && languageProbability < 0.4` → `nil`.
2. Keep segments with `noSpeechProbability <= 0.85 && averageLogProbability >= -1.2` (Windows drops on `>` / `<`), `text.strip()` each.
3. `english = parts.filter { !$0.isEmpty }.joined(separator: " ").strip()`.
4. `normalized = normalize(english)`; if `hallucinationPhrases.contains(normalized)` → `nil` (the empty string is in the set, so empty output is dropped here).
5. `Translation(english: english, language: candidate.language)`.

`strippedCharacters` = `!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~` plus space, `\t`, `\n`, `\r`, `\u{0B}`, `\u{0C}`, plus `!`, `¡`, `¿`, `?`; stripping removes characters from both ends while they are in the set (Python `str.strip(chars)`); lowercasing uses `lowercased()`. No `compressionRatio` gate (R3).

`TranslationStage` binds the two protocols the way Windows' single `transcribe()` call did, so the Windows STT tests mirror one-to-one:

```swift
public struct LanguageDetection: Sendable, Equatable { public var language: String; public var probability: Float }

public protocol LanguageDetector: Sendable {
    func detectLanguage(in audio: [Float]) async throws -> LanguageDetection
}
public protocol Translator: Sendable {
    /// `language` is the pinned or detected code; never nil at this level.
    func translate(_ audio: [Float], language: String) async throws -> TranslationCandidate
}

public struct TranslationStage: Sendable {
    public init(detector: any LanguageDetector, translator: any Translator, pinnedLanguage: String?)
    /// nil = dropped by a gate (no transcript entry, nothing spoken).
    public func translate(_ audio: [Float]) async throws -> Translation?
}
```

`translate`: if `pinnedLanguage == nil` run the detector; if `!SpeechGate.languagePasses(probability:)` return nil **without** calling the translator (saves the encoder pass; Windows got both from one call); otherwise call `translator.translate(audio, language:)` with the pinned or detected code and return `SpeechGate.evaluate(candidate with languageProbability = detection?.probability)`. The candidate's `language` is what the translator reports (WhisperKit echoes the language it was given).

Mirrored test behaviours: two segments " Hola." and " Buenos días." join to "Hola. Buenos días." with language "es" and the translator received the detected language; a pin "fr" is passed through and the detector is not called; `noSpeechProbability 0.99` rejected; `averageLogProbability −2.5` rejected; " Thanks for watching! " rejected; detection probability 0.2 while auto-detecting rejected and the translator not called; probability 0.2 with a pin accepted. Normalisation cases: "¿Subscribe?", "SUBSCRIBE...", "you.", "" all rejected; "you know" accepted.

### 5.4 BoundedSegmentQueue, PlaybackQueue, DuckingCoordinator and TranslationPipeline

#### Protocols

```swift
public enum CaptureMode: String, Codable, Sendable, CaseIterable { case microphone, broadcast }

public struct AudioClip: Sendable, Equatable {
    public var samples: [Float]     // mono Float32
    public var sampleRate: Int
    public var isEmpty: Bool { get }
}

public protocol AudioSource: Sendable {
    /// 16 kHz mono Float32 chunks of any length, in capture order. Ends when the source stops.
    var frames: AsyncStream<[Float]> { get }
    func start(_ mode: CaptureMode) async throws
    func stop() async
}

public protocol Speaker: Sendable {
    var sampleRate: Int { get }
    /// Whitespace-only text must return an empty clip without touching the engine.
    func synthesize(_ text: String) async throws -> AudioClip
}

public protocol AudioPlayer: Sendable {
    func start() async throws
    func enqueue(_ clip: AudioClip) async
    func setMuted(_ muted: Bool) async
    func clear() async
    func stop() async
    var isSpeaking: Bool { get async }
}
public typealias SpeakingCallback = @Sendable (Bool) -> Void
public typealias AudioPlayerFactory = @Sendable (_ sampleRate: Int, _ onSpeaking: @escaping SpeakingCallback) -> any AudioPlayer

public protocol Ducker: Sendable {
    func duck() async
    func restore() async
}

public protocol TranscriptSink: Sendable {
    func add(_ entry: TranscriptEntry) async
    func addDropMarker(at time: Date) async
    func close() async
}
public typealias TranscriptSinkFactory = @Sendable () -> any TranscriptSink
```

`Ducker` has no target pid (iOS ducks "everything else" in both modes, §6.8).

#### BoundedSegmentQueue

```swift
public struct BoundedSegmentQueue<Element: Sendable>: Sendable {
    public static var defaultCapacity: Int { 3 }              // max_pending
    public init(capacity: Int = 3)
    /// Drops the oldest elements until count < capacity, then appends. Returns the number dropped.
    public mutating func push(_ element: Element) -> Int
    public mutating func pop() -> Element?
    public var count: Int { get }
    public var isEmpty: Bool { get }
    public mutating func removeAll()
}
```

`push` mirrors `_enqueue_segment`: `while count >= capacity { dropOldest(); dropped += 1 }`. The pipeline emits one `.lag` event and one `addDropMarker` per dropped element.

#### PlaybackQueue (core half of `AudioPlayer`, port of `playback.py:Player`)

```swift
public protocol PlaybackSink: Sendable {
    /// Schedules the clip; calls `completion` once the audio has been played back or the sink was stopped.
    func schedule(_ clip: AudioClip, completion: @escaping @Sendable () -> Void)
    /// Stops the current clip immediately (used when muted mid-clip and on stop).
    func stopCurrent()
}

public actor PlaybackQueue {
    public init(sink: any PlaybackSink, onSpeakingChanged: @escaping SpeakingCallback)
    public var isSpeaking: Bool { get }
    public var isMuted: Bool { get }
    public func enqueue(_ clip: AudioClip)      // empty clips ignored
    public func setMuted(_ muted: Bool)         // true: discard queue and stop current; speaking → false
    public func clear()
    public func stop()                          // idempotent; speaking → false
}
```

Semantics from Windows: muted audio is **discarded, never paused** (`if self._muted: continue`); muting during a clip breaks out of the write loop (`stopCurrent()`); speaking becomes true when the first clip is scheduled with nothing outstanding and false when the last outstanding clip completes with an empty queue; `on_speaking` fires only on edges. The app's `AudioPlayer` (§6.7) is `PlaybackQueue` over an `AVAudioPlayerNode` sink; the Windows 0.25 s slicing is not needed because the sink can stop a scheduled buffer at any time.

Mirrored test behaviours: enqueuing 24 000 samples schedules them and toggles speaking true then false; empty clips are ignored and `isSpeaking` stays false; muted clips are never scheduled and speaking never becomes true; `stop()` twice is safe and stops the sink.

#### DuckingCoordinator

Port of the ducking policy in `pipeline.py:_on_speaking` plus the idempotence of `ducking.py`, with the iOS hold:

```swift
public actor DuckingCoordinator {
    public static let defaultHoldNanoseconds: UInt64 = 250_000_000     // ~250 ms (R8)
    public init(ducker: any Ducker, enabled: Bool, hold: UInt64 = DuckingCoordinator.defaultHoldNanoseconds,
                sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) })
    public func setEnabled(_ enabled: Bool)     // disabling while ducked restores immediately
    public func speakingChanged(_ speaking: Bool)
    public func restoreNow()                    // mute, stop, error
    public var isDucked: Bool { get }
}
```

`speakingChanged(true)` ducks once (a second call while ducked is a no-op); `speakingChanged(false)` starts the hold; a new `true` inside the hold cancels it; when the hold elapses `restore()` is called once. `restoreNow()` cancels any hold and restores if ducked. Disabled → no `Ducker` calls at all.

Mirrored test behaviours (from `test_ducking.py`): duck twice is a no-op and restore is idempotent; disabled leaves the ducker alone; a speaking edge inside the hold does not restore; restore happens exactly once after the hold.

#### TranslationPipeline

```swift
public enum PipelineState: String, Sendable, Equatable { case idle, running, error }

public enum PipelineEvent: Sendable, Equatable {
    case state(PipelineState)
    case entry(TranscriptEntry)
    case lag
    case speaking(Bool)
    case error(String)
}

public struct PipelineConfiguration: Sendable, Equatable {
    public var captureMode: CaptureMode
    public var preset: SegmenterPreset
    public var pinnedLanguage: String?
    public var maxPending: Int = 3
    public var captureGateHoldFrames: Int = CaptureGate.defaultHoldFrames
    public var duckingEnabled: Bool = true
}

public struct PipelineDependencies: Sendable {
    public var source: any AudioSource
    public var vad: any SpeechProbabilityModel
    public var detector: any LanguageDetector
    public var translator: any Translator
    public var speaker: any Speaker
    public var playerFactory: AudioPlayerFactory
    public var ducker: any Ducker
    public var transcriptFactory: TranscriptSinkFactory
    public var clock: @Sendable () -> Date = Date.init
}

public final class TranslationPipeline: Sendable {
    public init(dependencies: PipelineDependencies)
    public var events: AsyncStream<PipelineEvent> { get }
    public var state: PipelineState { get async }
    public func start(_ configuration: PipelineConfiguration) async   // no-op while running
    public func stop() async                                          // idempotent
    public func setMuted(_ muted: Bool) async
    public var isMuted: Bool { get async }
    /// Broadcast reader detected a ring overrun: emits `.lag` and a drop marker without dropping a segment.
    public func noteCaptureGap() async
}
```

Behaviour, stage by stage, mirroring `pipeline.py`:

- **start:** ignore if running; build fresh queues, a `Segmenter(vad:preset:)`, a `CaptureGate`, a `DuckingCoordinator(ducker:enabled:)`, the transcript sink and the player (`playerFactory(speaker.sampleRate, onSpeaking)`); `player.setMuted(isMuted)`; `player.start()`; `source.start(mode)`; spawn the three stage tasks; `state = .running`, emit `.state(.running)`. A throw from `player.start()` or `source.start()` goes to `fail`.
- **capture stage:** for each `[Float]` from `source.frames`: advance the frame counter; re-frame into 512-sample chunks (`AudioFormat.ChunkReframer`); for each chunk, if `captureGate.allows(chunkEndingAt:)` then `segmenter.feed(chunk)`; every completed phrase → `segmentQueue.push`; each dropped element → `.lag` + `transcript.addDropMarker(at: clock())`. When the stream ends (source stopped) call `segmenter.flush()` and push the remainder.
- **translate stage:** pop → `translationStage.translate(segment)`; if nil or no longer running, continue; else `entry = TranscriptEntry(timestamp: clock(), language:, original: "", english:)`, `transcript.add(entry)`, emit `.entry(entry)`, push text. Backpressure between translate and speak is unbounded, as in Windows (the text queue is never dropped).
- **speak stage:** pop text → `speaker.synthesize(text)` → `player.enqueue(clip)` (player ignores empty clips).
- **speaking edge** (`onSpeaking`): stamp the current frame counter into `captureGate.speakingChanged(speaking, atFrame:)`, forward to `ducking.speakingChanged(speaking)`, emit `.speaking(speaking)`. Windows ducks with the target pid in app mode and `None` in system mode; iOS ducks the same way in both modes.
- **setMuted:** store; `player.setMuted(muted)`; if muted, `ducking.restoreNow()` (Windows: `self._ducker.restore()`).
- **fail(error):** `running = false`, `state = .error`, emit `.error(String(describing: error))`; the other stages exit on their next loop check; the player and source are left to `stop()`, exactly like Windows.
- **stop:** `wasRunning = running || state == .error`; `running = false`; `source.stop()`; cancel and await the stage tasks (bounded wait); `player.stop()`; `ducking.restoreNow()`; `transcript.close()`; if `wasRunning || state != .idle` → `state = .idle`, emit `.state(.idle)`. Calling `stop()` twice is safe; `stop()` from an error state transitions to idle.

Mirrored test behaviours: happy path translates and speaks, transcript entry `text-1`/`es`, an `.entry` event, state running then idle; with a blocked translator and `maxPending = 2`, six segments produce a `.lag`, at least one drop marker and at most four translations after unblocking; speaking true → `duck()`, false → `restore()` after the hold (in both modes); mute forwards to the player and restores ducking; a throwing translator emits `.error` and `state == .error`; stop cleans up (source stopped, player stopped, transcript closed, ducker restored, last state event idle) and is idempotent. New: a speaking edge closes the capture gate and chunks are dropped until 300 ms of capture frames after the edge (R9 test); `flush()` on stop pushes the partial phrase.

### 5.5 TranscriptFormatter

Port of `revox/transcript.py`. Core formats; the app stores and writes files.

```swift
public struct TranscriptEntry: Sendable, Equatable, Codable {
    public var timestamp: Date
    public var language: String
    public var original: String          // always "" on both platforms
    public var english: String
}

public enum TranscriptItem: Sendable, Equatable {
    case entry(TranscriptEntry)
    case dropMarker(Date)
}

public struct TranscriptFormatter: Sendable {
    public static let headerPrefix = "# ReVox session "
    public static let dropMarkerText = "… (skipped: falling behind)"
    public init(timeZone: TimeZone = .current)
    public func fileName(startedAt: Date) -> String                 // "yyyy-MM-dd_HH-mm-ss.txt"
    public func header(startedAt: Date) -> String                   // "# ReVox session yyyy-MM-dd'T'HH:mm:ss\n"
    public func line(for entry: TranscriptEntry) -> String          // "[HH:mm:ss] [<lang>] <original>\n  → <english>\n"
    public func dropMarkerLine(at time: Date) -> String             // "[HH:mm:ss] … (skipped: falling behind)\n"
    /// Header plus items in order, with consecutive drop markers collapsed to one (Windows `_last_was_drop`).
    public func export(startedAt: Date, items: [TranscriptItem]) -> String
}

/// In-memory `TranscriptSink` with the Windows dedupe rule; the app's SwiftData sink reuses it for the flag.
public actor TranscriptRecorder: TranscriptSink {
    public init(startedAt: Date, formatter: TranscriptFormatter = TranscriptFormatter())
    public var items: [TranscriptItem] { get }
    public var isClosed: Bool { get }
    public func add(_ entry: TranscriptEntry)
    public func addDropMarker(at time: Date)   // ignored while closed or when the last item is a drop marker
    public func close()                        // idempotent
    public func exportText() -> String
}
```

Formatting rules: `DateFormatter` with `locale = Locale(identifier: "en_US_POSIX")`, `calendar = Calendar(identifier: .gregorian)`, the given time zone; patterns `yyyy-MM-dd'T'HH:mm:ss` (Python `isoformat(timespec="seconds")` on a naive local datetime: no offset suffix), `HH:mm:ss`, `yyyy-MM-dd_HH-mm-ss`. The arrow line is two spaces, U+2192, one space. The ellipsis is U+2026. UTF-8, `\n` line endings, no BOM. The drop marker carries the time the drop happened (Windows uses `clock()` at the moment of the drop), the entry carries the translation time.

Mirrored test behaviours: export starts with `# ReVox session `; an entry produces `[es] hola` and `  → hello` lines (the port writes an empty original, so the test asserts `[es] ` followed by the newline and the arrow line); two drop markers, an entry, then a drop marker yield exactly two `skipped: falling behind` lines; `close()` twice is safe and `add` after close is ignored. New: exact byte-for-byte golden file for a fixed session; file name for a fixed date; timestamps honour the injected time zone.

### 5.6 ModelCatalog and DeviceRecommendation (R4, R13)

```swift
public enum WhisperModelID: String, CaseIterable, Codable, Sendable, Identifiable {
    case tiny, base, small, medium, largeV3 = "large-v3"
    public var id: String { rawValue }
    public var displayName: String { get }        // "tiny" … "large-v3"
}

public struct WhisperModelDescriptor: Sendable, Equatable, Identifiable {
    public let id: WhisperModelID
    public let folderName: String                 // Hub folder in argmaxinc/whisperkit-coreml
    public let approximateBytes: Int64            // decimal, Hub listing 2026-09-02
    public let modelRepo: String                  // "argmaxinc/whisperkit-coreml"
    public let tokenizerRepo: String              // "openai/whisper-<size>"; large-v3 → "openai/whisper-large-v3"
    public let note: String?                      // large-v3: compressed weights Argmax ships for iPhone
    public var requiredRelativePaths: [String] { get }   // §6.9 installed check
}

public struct VADModelDescriptor: Sendable, Equatable {
    public let repo: String                       // "FluidInference/silero-vad-coreml"
    public let subdirectory: String               // "silero-vad-unified-v6.0.0.mlmodelc"
    public let approximateBytes: Int64            // ≈ 950_000 (weight.bin 882 304 + model.mil 25 126 + metadata)
    public var requiredRelativePaths: [String] { get }
}

public struct PocketTTSDescriptor: Sendable, Equatable {
    public let repo: String                       // "FluidInference/pocket-tts-coreml"
    public let languageFolder: String             // "v2.1/english"
    public let approximateBytes: Int64            // ≈ 527_300_000 (ANE placement, fp16, all 26 voices)
    public let offeredVoices: [String]            // ["alba", "azelma", "cosette", "javert"]
}

public struct LicenceNotice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let licence: String
    public let url: URL
    public let attribution: String?
}

public enum DownloadKind: Sendable, Equatable { case whisper(WhisperModelID), vad, pocketTTS }

public struct DownloadDescriptor: Sendable, Equatable {
    public let kind: DownloadKind
    public let expectedBytes: Int64
    public let displayName: String
}

public enum ModelCatalog {
    public static let whisperModels: [WhisperModelDescriptor]      // order: tiny, base, small, medium, largeV3
    public static let defaultWhisperModel: WhisperModelID = .small
    public static func whisper(_ id: WhisperModelID) -> WhisperModelDescriptor
    public static let vad: VADModelDescriptor
    public static let pocketTTS: PocketTTSDescriptor
    public static let licences: [LicenceNotice]
    public static func download(for kind: DownloadKind) -> DownloadDescriptor
    /// `available >= expected * 1.25 + 200 MB` (ASSUMED rule, §6.9)
    public static func hasRoomToInstall(expectedBytes: Int64, availableBytes: Int64) -> Bool
}
```

Whisper catalog values (R4; sizes decimal, recorded from the Hub listing of 2026-09-02, shown to the user as "≈ N MB"):

| `id` | `folderName` | `approximateBytes` | `tokenizerRepo` | note |
|---|---|---|---|---|
| tiny | `openai_whisper-tiny` | 76 600 000 | `openai/whisper-tiny` | |
| base | `openai_whisper-base` | 146 700 000 | `openai/whisper-base` | |
| small (default) | `openai_whisper-small` | 486 500 000 | `openai/whisper-small` | |
| medium | `openai_whisper-medium` | 1 528 000 000 | `openai/whisper-medium` | long load time and heat (on eligible devices) |
| large-v3 | `openai_whisper-large-v3_947MB` | 948 000 000 | `openai/whisper-large-v3` | "Compressed weights Argmax ships for iPhone" |

Turbo and distil variants are never offered and never appear in the catalog. Tokenizer files (`tokenizer.json`, `tokenizer_config.json`, `config.json`) are part of the Whisper install (§6.9).

Licences: WhisperKit — MIT — https://github.com/argmaxinc/WhisperKit; pocket-tts Core ML weights — CC-BY-4.0 — https://huggingface.co/FluidInference/pocket-tts-coreml — attribution "pocket-tts by Kyutai (https://kyutai.org)"; Silero VAD — MIT — https://github.com/snakers4/silero-vad; FluidAudio — Apache-2.0 — https://github.com/FluidInference/FluidAudio; ReVox Mobile — MIT.

`DeviceRecommendation` (R13), a pure function of physical memory:

```swift
public struct DeviceRecommendation: Sendable, Equatable {
    public let recommended: WhisperModelID
    public let suitable: Set<WhisperModelID>
    public let warnings: [WhisperModelID: String]
    public static let heatWarning = "Long load time and heat"
    public static func forPhysicalMemory(bytes: UInt64) -> DeviceRecommendation
    /// Nearest whole GiB: Int((Double(bytes) / 1_073_741_824).rounded())
    public static func memoryTierGB(bytes: UInt64) -> Int
}
```

| `memoryTierGB` | `recommended` | `suitable` | `warnings` |
|---|---|---|---|
| < 4 | base | {tiny, base, small} | — |
| 4, 5 | small | {tiny, base, small} | — |
| 6, 7 | small | {tiny, base, small, medium} | — |
| ≥ 8 | small | all five | medium, large-v3 → `heatWarning` |

Rounding to the nearest GiB absorbs the few hundred MB that `physicalMemory` reports below the nominal size (ASSUMED; the reported values on the test devices are logged in M3). Models outside `suitable` remain downloadable; the Models screen shows them as "Not recommended for this iPhone" (§8).

Test behaviours: five catalog entries in order, folder names and byte sizes as tabled, no folder containing "turbo" or "distil", default small; licences contain the four notices with the Kyutai attribution; recommendation table above at 3.9, 4.0, 5.9, 6.0, 7.9, 8.0 GiB inputs; `hasRoomToInstall` boundaries.

### 5.7 Settings (R11)

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var model: String = "small"                       // WhisperModelID.rawValue
    public var language: String? = nil                       // nil = auto-detect
    public var voice: String = "alba"                        // pocket-tts voice name or "system"
    public var systemVoiceIdentifier: String? = nil          // AVSpeechSynthesisVoice.identifier
    public var ducking: Bool = true
    public var voiceVolume: Double = 1.0                     // 0.0 … 1.0
    public var latencyMode: String = "balanced"              // SegmenterPreset.rawValue
    public var captureMode: String = "microphone"            // CaptureMode.rawValue
    public init()

    public var whisperModel: WhisperModelID { get }          // invalid → .small
    public var preset: SegmenterPreset { get }               // invalid → .balanced
    public var capture: CaptureMode { get }                  // invalid → .microphone
    public var usesPocketTTSVoice: Bool { get }              // voice ∈ ModelCatalog.pocketTTS.offeredVoices
}

public enum SettingsCodec {
    public static let fileName = "settings.json"
    public static func decode(_ data: Data) -> Settings      // never throws: corrupt/wrong types → Settings()
    public static func encode(_ settings: Settings) throws -> Data
    public static func load(from url: URL) -> Settings       // missing file → Settings()
    public static func save(_ settings: Settings, to url: URL) throws
}
```

JSON keys use the Windows snake_case names (`model`, `language`, `voice`, `system_voice_identifier`, `ducking`, `voice_volume`, `latency_mode`, `capture_mode`) through explicit `CodingKeys`, so a Windows `settings.json` decodes with its extra keys ignored. Decoding is a custom `init(from:)` using `decodeIfPresent` for every field (missing keys defaulted); any type mismatch, non-object root or invalid JSON yields `Settings()` (Windows: `TypeError`/`ValueError` → defaults). Encoding writes all keys, pretty-printed with sorted keys. File location on iOS: `<Application Support>/ReVox/settings.json` (the app passes the URL). Dropped fields: `device`, `output_device`, `ducking_level`, `hotkey_*`, `transcript_dir`, `start_minimized`.

Mirrored test behaviours: defaults as tabled; round trip through encode/decode is equal; missing file → defaults; corrupt JSON → defaults; `{"model":"medium","bogus_key":1}` → model medium, voice alba; wrong type (`"ducking": "yes"`) → defaults; a Windows-format file with `ducking_level` decodes; invalid `latency_mode` maps to `.balanced`.

### 5.8 AudioFormat helpers

Port of the `to_mono_16k` semantics split along the platform line: core does channel averaging and re-framing; resampling lives in the app on `AVAudioConverter` (§6.1) because Foundation has no resampler and the Windows `soxr` cannot be reproduced bit-exactly anyway.

```swift
public enum AudioFormat {
    public static let pipelineSampleRate = 16_000            // PIPELINE_SAMPLE_RATE
    /// Average of the channels per frame, Float32; channels == 1 returns the input unchanged.
    public static func downmixInterleaved(_ samples: [Float], channels: Int) -> [Float]
    public static func downmixPlanar(_ channels: [[Float]]) -> [Float]
    /// Int16 → Float32 in [-1, 1) (`/ 32768`), used by tests that model the broadcast source.
    public static func float32(fromInt16 samples: [Int16]) -> [Float]
}

public struct ChunkReframer: Sendable {
    public init(chunkSamples: Int = Segmenter.chunkSamples)
    public mutating func push(_ samples: [Float]) -> [[Float]]  // full chunks only
    public var pendingCount: Int { get }
    public mutating func drain() -> [Float]                     // remainder (< chunkSamples)
}
```

Test behaviours: stereo interleaved 4 800 frames average to 4 800 mono samples; a mono 16 kHz array passes through unchanged (`array_equal`); planar and interleaved downmix agree; the reframer emits exactly `n / 512` chunks for any slice cadence and keeps the remainder. The resample assertion of the Windows test (`4800 @ 48 kHz → 1600 ± 16`) moves to `ReVoxMobileTests` against the app's converter.

### 5.9 Ring bridge types (R10)

Foundation-only types over injected storage. The app and the extension map the ring file and implement `RingStorage` with real atomics (§6.2, §7); tests use `HeapRingStorage`. This subsection, with the header table, is the source for `docs/broadcast-bridge.md` (written in M5).

```swift
public struct RingLayout: Sendable, Equatable {
    public static let v1 = RingLayout(magic: "RVXRING1", headerBytes: 4_096, capacityFrames: 960_000, sampleRate: 16_000)
    public let magic: String
    public let headerBytes: Int
    public let capacityFrames: Int
    public let sampleRate: Int
    public var dataBytes: Int { get }           // capacityFrames × 4 = 3 840 000
    public var totalBytes: Int { get }          // 3 844 096
    public static let fileName = "audio-ring-v1.bin"
}

public protocol RingStorage: AnyObject, Sendable {
    var base: UnsafeMutableRawPointer { get }
    var count: Int { get }
    func loadCursor(at offset: Int) -> UInt64          // acquire semantics in adapters
    func storeCursor(_ value: UInt64, at offset: Int)  // release semantics in adapters
}

public final class HeapRingStorage: RingStorage {
    public init(layout: RingLayout)
    public init(bytes: Int)                             // for "too small" tests
}

public struct RingHeader: Sendable, Equatable {
    public enum State: UInt32, Sendable { case idle = 0, running, paused, finished, failed }
    public struct ASBD: Sendable, Equatable {           // AudioStreamBasicDescription snapshot, 40 bytes
        public var sampleRate: Double; public var formatID: UInt32; public var formatFlags: UInt32
        public var bytesPerPacket: UInt32; public var framesPerPacket: UInt32; public var bytesPerFrame: UInt32
        public var channelsPerFrame: UInt32; public var bitsPerChannel: UInt32; public var reserved: UInt32
    }
    public struct PTS: Sendable, Equatable { public var value: Int64; public var timescale: Int32; public var flags: UInt32 }
    public var magic: String; public var headerBytes: UInt32; public var capacityFrames: UInt32
    public var sampleRate: UInt32; public var channels: UInt16; public var sampleFormat: UInt16
    public var generation: UInt64; public var writeCursor: UInt64; public var readCursor: UInt64
    public var state: State; public var asbdChangeCount: UInt32
    public var lastWriteAt: Double; public var startedAt: Double; public var lastPTS: PTS; public var lastAsbdChangeAt: Double
    public var sourceASBD: ASBD; public var droppedInputFrames: UInt64; public var micBuffersSeen: UInt64
    public var overrunCount: UInt64; public var peakLevel1s: Float; public var rmsLevel1s: Float; public var writerPID: UInt32
    public static func read(from storage: any RingStorage) -> RingHeader?   // nil on bad magic / short
}

public enum RingError: Error, Equatable { case badMagic, tooSmall, unsupportedLayout }

public final class RingWriter: Sendable {
    public init(storage: any RingStorage, layout: RingLayout = .v1) throws
    /// Writes the full header (magic first, cursors zero), bumps generation, state = running.
    public func begin(generation: UInt64, startedAt: Double, asbd: RingHeader.ASBD, pid: UInt32)
    /// Copies frames at writeCursor % capacity (split at wrap), then stores the cursor, then lastWriteAt/levels. Returns the new cursor.
    public func write(_ frames: UnsafeBufferPointer<Float>, at time: Double, pts: RingHeader.PTS) -> UInt64
    public func setState(_ state: RingHeader.State, at time: Double)
    public func noteFormatChange(_ asbd: RingHeader.ASBD, at time: Double)
    public func noteDroppedInput(frames: Int)
    public func noteMicBuffer()
    public var writeCursor: UInt64 { get }
}

public enum AttachState: Sendable, Equatable {
    case noRing
    case idle
    case attachedLive(generation: UInt64)
    case stale(lastWriteAt: Double)
}
public enum ReadResult: Sendable, Equatable {
    case frames(Int)
    case gap(dropped: Int)
    case idle
}

public final class RingReader: Sendable {
    public static let defaultGuardFrames = 16_000          // 1 s
    public static let defaultCatchUpFrames = 32_000        // 2 s
    public static let staleAfterSeconds: Double = 3
    public init(storage: any RingStorage, layout: RingLayout = .v1) throws   // .badMagic / .tooSmall
    public var header: RingHeader { get }
    /// Decides live/stale/idle from state, generation and heartbeat; positions readCursor = max(stored, writeCursor − catchUp).
    public func attach(now: Double, storedReadCursor: UInt64?, storedGeneration: UInt64?, catchUp: Int = RingReader.defaultCatchUpFrames) -> AttachState
    /// Copies [start, writeCursor) in ≤ 512-multiples; re-checks writeCursor after the copy; on overrun discards, bumps overrunCount, jumps to writeCursor − catchUp.
    public func read(into buffer: UnsafeMutableBufferPointer<Float>, guard guardFrames: Int = RingReader.defaultGuardFrames) -> ReadResult
    public var readCursor: UInt64 { get }
    public var overrunCount: UInt64 { get }
}
```

Header layout (all fields little-endian; 8-byte fields 8-byte aligned; header is one 4 096-byte page; writer column: ext = extension, app = app):

| Offset | Size | Type | Field | Writer | Meaning |
|---|---|---|---|---|---|
| 0 | 8 | `[8]UInt8` | `magic` | ext | ASCII `RVXRING1`; the app refuses anything else |
| 8 | 4 | UInt32 | `headerBytes` | ext | 4096 |
| 12 | 4 | UInt32 | `capacityFrames` | ext | 960 000 (60 s at 16 kHz) |
| 16 | 4 | UInt32 | `sampleRate` | ext | 16000 |
| 20 | 2 | UInt16 | `channels` | ext | 1 |
| 22 | 2 | UInt16 | `sampleFormat` | ext | 1 = Float32 little-endian |
| 24 | 8 | UInt64 | `generation` | ext | +1 on every `broadcastStarted`; mirrored in the UserDefaults record |
| 32 | 8 | UInt64 | `writeCursor` | ext | absolute frames since generation start, never wraps; physical index = `cursor % capacityFrames` |
| 40 | 8 | UInt64 | `readCursor` | app | advisory: last frame consumed; the extension never reads it |
| 48 | 4 | UInt32 | `state` | ext | 0 idle, 1 running, 2 paused, 3 finished, 4 failed |
| 52 | 4 | UInt32 | `asbdChangeCount` | ext | source-format changes seen; the first format counts as 1 |
| 56 | 8 | Float64 | `lastWriteAt` | ext | `Date().timeIntervalSince1970` at the last data write (heartbeat) |
| 64 | 8 | Float64 | `startedAt` | ext | generation start |
| 72 | 8 | Int64 | `lastPTS.value` | ext | `CMSampleBufferGetPresentationTimeStamp` of the last input buffer |
| 80 | 4 | Int32 | `lastPTS.timescale` | ext | |
| 84 | 4 | UInt32 | `lastPTS.flags` | ext | |
| 88 | 8 | Float64 | `lastAsbdChangeAt` | ext | |
| 96 | 40 | ASBD | `sourceASBD` | ext | verbatim `AudioStreamBasicDescription` of the current `.audioApp` stream: `mSampleRate` (Float64), then `mFormatID`, `mFormatFlags`, `mBytesPerPacket`, `mFramesPerPacket`, `mBytesPerFrame`, `mChannelsPerFrame`, `mBitsPerChannel`, `mReserved` (UInt32 each) |
| 136 | 8 | UInt64 | `droppedInputFrames` | ext | non-PCM, > 2 channels or converter failure |
| 144 | 8 | UInt64 | `micBuffersSeen` | ext | `.audioMic` buffers received and ignored (Control Center mic toggle diagnostic) |
| 152 | 8 | UInt64 | `overrunCount` | app | reader detected an overwrite and jumped |
| 160 | 4 | Float32 | `peakLevel1s` | ext | level meter over the last ~1 s of converted audio |
| 164 | 4 | Float32 | `rmsLevel1s` | ext | |
| 168 | 4 | UInt32 | `writerPID` | ext | |
| 172 | 3924 | | reserved | | zero |
| 4096 | 3 840 000 | Float32 × 960 000 | data region | ext | 60 s ring of mono 16 kHz samples |

Ordering rules: the writer copies data, then stores `writeCursor` (release), then the heartbeat and levels. The reader loads `writeCursor` (acquire), copies, then re-loads it; if `writeCursor − start > capacityFrames − guardFrames` the copy is discarded as torn. This is correct even if a torn 64-bit cursor is observed on a plain (test) storage, because only data at least `guardFrames` behind the writer is ever trusted. The file is created and only ever **grown** by the extension (§7); a layout change gets a new file name (`audio-ring-v2.bin`), never a resize.

`attach` decision table (`now` and stored values come from the adapter):

| Condition | Result |
|---|---|
| storage nil / bad magic / `count < totalBytes` | `.noRing` (thrown at init or reported by the adapter) |
| `state == running` and `now − lastWriteAt ≤ 3 s` and generation matches the stored record (or no record) | `.attachedLive(generation)`; `readCursor = max(storedReadCursor for this generation, writeCursor − catchUp)` |
| `state == running` and heartbeat older than 3 s | `.stale(lastWriteAt)`; nothing is read |
| `state ∈ {idle, paused, finished, failed}` | `.idle` |
| header generation ≠ stored generation | trust the header, reset the stored cursor, then re-evaluate |

Test behaviours: header round trip at every offset above (golden bytes); write across the wrap boundary reads back in order; a reader that lags more than `capacity − guard` gets `.gap` and jumps to `writeCursor − catchUp`; a torn cursor injected by a test storage (high word updated first) never yields corrupted frames; generation change resets the reader; `attach` table above; `read` returns frames in 512-multiples only; `.tooSmall` and `.badMagic` at init; `HeapRingStorage` sized `totalBytes` exactly.

---

## 6. ReVoxMobile adapters

Each adapter names the exact library or Apple APIs it uses (API §n = section of `api-reference.md` where the signature was verified), the formats it produces, its error handling and its fallback. Nothing in this section imports into `ReVoxCore`.

### 6.1 MicrophoneCapture (`AudioSource`, mic mode) — API §1

- **Permission:** `AVAudioApplication.requestRecordPermission()` (iOS 17) before the first start; `AVAudioApplication.shared.recordPermission == .denied` → `CaptureError.microphoneDenied` surfaced by the Live screen with a Settings deep link (`UIApplication.openSettingsURLString`).
- **Engine:** the mode's shared `AVAudioEngine` owned by `AudioSessionController` (§6.8). Guard `inputNode.inputFormat(forBus: 0).sampleRate > 0` before installing the tap (the input node throws otherwise). Tap: `inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNode.outputFormat(forBus: 0))` — the tap format must equal the hardware format because the input node does no conversion. `engine.isAutoShutdownEnabled = false`.
- **Conversion:** one long-lived `AVAudioConverter(from: hardwareFormat, to: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))` per tap format. Per tap buffer: `convert(to:error:withInputFrom:)` with an input block that hands the tap buffer over once with `.haveData` and then answers `.noDataNow`; loop until `.inputRanDry`; output capacity `ceil(frameLength × 16000 / inputRate) + 64` (ASSUMED feeding pattern, M3 checks for clicks at chunk edges on 48 kHz and HFP routes). Channel averaging happens inside the converter (it downmixes); the core `AudioFormat.downmixInterleaved` is used only when the hardware format is interleaved multi-channel and the converter refuses the format (never observed; defensive).
- **Output:** `AsyncStream<[Float]>` fed from the tap thread with `continuation.yield(samples)` (buffering policy `.unbounded`; the core re-frames to 512). The frame counter for the capture gate is the sum of yielded samples.
- **Configuration changes:** observe `AVAudioEngineConfigurationChangeNotification`; off the notification queue, remove the tap, rebuild the converter from the new `inputNode.outputFormat(forBus: 0)`, re-install, `engine.start()`. Never deallocate the engine in the handler.
- **Never** call WhisperKit's `startRecordingLive`/`resumeRecordingLive` (they configure a non-mixable session) or FluidAudio's `AudioConverter` for the continuous tap (stateless per call, resets filter history).
- Errors: `engine.start()` throwing → `.error("Microphone unavailable")`; route loss during a session (`routeChangeNotification` reason `.oldDeviceUnavailable`) → rebuild as above; if the input becomes unavailable the pipeline continues with silence and the status line shows "No microphone input".

### 6.2 BroadcastCapture (`AudioSource`, broadcast mode) — API §2

- **Mapping:** `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)` → `Library/Application Support/ReVox/audio-ring-v1.bin`; open with `open(2)` read/write (the app writes only `readCursor` and `overrunCount`), `mmap(nil, totalBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)`; `munmap` on stop. The app never creates, truncates or grows the file: absent or short → `AttachState.noRing` and the Live screen shows "Start a broadcast to listen to other apps".
- **`RingStorage`:** `MappedRingStorage` implements the two cursor accessors with a 10-line C shim (`stdatomic` `atomic_load_explicit(memory_order_acquire)` / `atomic_store_explicit(memory_order_release)` on the mapped `uint64_t`) compiled into both the app and the extension targets (ASSUMED primitive choice; M5 confirms the shim builds under `APPLICATION_EXTENSION_API_ONLY` and that `MAP_SHARED` pages are not charged to the extension's jetsam footprint).
- **Wake-ups:** `CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, callback, name, nil, .deliverImmediately)` for `<appGroup>.broadcast.{started,paused,resumed,stopped,formatChanged,audio}`, delivered on the main run loop and hopped to the capture task. A 100 ms timer fallback polls `writeCursor` while attached, so missed notifications only add latency.
- **Reading:** on every wake or tick, `reader.read(into:)` into a 16 000-frame scratch buffer; `.frames(n)` → yield `[Float]` (the reader returns 512-multiples); `.gap(dropped)` → yield nothing, emit a transcript drop marker through the pipeline's lag path (the pipeline exposes `noteCaptureGap()` for this), store the new `readCursor` in the `"capture.reader"` defaults record.
- **State record:** `UserDefaults(suiteName: appGroup)` key `"broadcast.state"` read on launch, `didBecomeActive` and every Darwin wake (cross-process change notifications are not relied on). Attach state machine per §5.9: `.attachedLive` starts the pipeline from the foreground and marks the transcript "joined in progress"; `.stale` shows "The broadcast stopped unexpectedly"; a `finishReason` equal to `RPRecordingErrorCode.systemDormancy` shows the lock-screen hint.
- **Broadcast start/stop:** the picker (`RPSystemBroadcastPickerView`, `preferredExtension = Info.plist REVOXBroadcastExtensionBundleID`, `showsMicrophoneButton = false`, wrapped in a `UIViewRepresentable` sized 50×50 pt) or Control Center. Stop is user-driven (Control Center or the status bar indicator); the app's Stop only stops the pipeline and detaches; it cannot end the broadcast.
- Silence from AVPlayer/Safari/Music sources is a ReplayKit limitation; the status line shows "No audio from the app (some players are not captured)" when `rmsLevel1s` stays below −60 dBFS for 10 s while attached.

### 6.3 SileroVAD (`SpeechProbabilityModel`) — API §3.2, R1

FluidAudio's `VadManager` scores 4 096-sample chunks with noisy-OR aggregation and pads shorter input, so it is **not** used for per-chunk scoring. The app downloads FluidAudio's 512-sample export and drives it directly:

- **Download:** `ModelHub.download(.vad, subdirectory: "silero-vad-unified-v6.0.0.mlmodelc", to: root/Models/silero-vad, config: .default, progressHandler:)` (`ModelHub.swift:563-576`; files land at `repoDirectory/<remote path>`, so the bundle is `root/Models/silero-vad/silero-vad-unified-v6.0.0.mlmodelc`). Progress spans 0–1, byte-weighted.
- **Load:** `MLModel(contentsOf: bundleURL, configuration: MLModelConfiguration())` with `computeUnits = .cpuOnly` initially (fp16 LSTM state numerics on the ANE over hours are unmeasured; M3 A/Bs `.cpuAndNeuralEngine` on the same audio).
- **Inference per 512-sample chunk:** inputs `audio_input` `[1,576]` Float32 = 64 context samples (the last 64 of the previous chunk, zeros at start) followed by the 512 new samples; `hidden_state` `[1,128]`; `cell_state` `[1,128]`. Outputs `vad_output` `[1,1,1]` (plain sigmoid for one window), `new_hidden_state`, `new_cell_state`, carried to the next call. `reset()` zeroes context and states. `MLMultiArray` buffers are preallocated once; `prediction(from:)` runs on the actor. Feature names and shapes are verified from the bundle's `model.mil`; the port of the Windows 0.5 threshold to this export is ASSUMED and A/B-tested against the Windows app on identical audio in M3.
- **Never** pass this bundle to `VadManager(config:vadModel:)` (it would build 4 160-sample inputs and fail) and never call `processStreamingChunk` with 512 samples.
- Errors: load failure → `ModelError.vadLoadFailed` → the pipeline cannot start; the Live screen shows "Voice detector failed to load. Re-download it in Models." (§9). README documents why `VadManager` is not used.

### 6.4 WhisperKitTranslator (`Translator` + `LanguageDetector`) — API §4, R2, R3, R4

An actor owning one `WhisperKit`.

- **Construction:** `WhisperKit(WhisperKitConfig(modelFolder: root/models/argmaxinc/whisperkit-coreml/<folderName>, tokenizerFolder: root, computeOptions: ModelComputeOptions(), verbose: false, logLevel: .error, prewarm: true, load: true, download: false))`. With `modelFolder` set, `setupModels` never touches the Hub; `prewarm: true` bounds peak memory at the cost of load time (progress shown as "Preparing model…" with `modelStateCallback` states `.prewarming`/`.loading`). The tokenizer resolves from `tokenizerFolder/models/openai/whisper-<size>/tokenizer.json`, which the install step placed there (§6.9).
- **Language detection (R2):** when no language is pinned, `detectLangauge(audioArray:)` (sic) returns `(language, langProbs)` where `langProbs[language]` is the **log**-probability of the argmax language token (`TextDecoder.swift:515-521`); the adapter returns `LanguageDetection(language:, probability: exp(logProb))`, clamped to `[0, 1]` and logged if outside it after `exp` (R2: measured in M3; the core gate is unchanged either way).
- **Decoding options (R3, verbatim):**

  ```swift
  DecodingOptions(task: .translate,
                  language: language,               // pinned or detected; never nil here
                  temperature: 0.0,                 // greedy = beam size 1 equivalent
                  temperatureFallbackCount: 0,
                  usePrefillPrompt: true,
                  detectLanguage: false,
                  skipSpecialTokens: true,
                  withoutTimestamps: true,
                  wordTimestamps: false,
                  windowClipTime: 0,
                  chunkingStrategy: ChunkingStrategy.none)
  ```

  `windowClipTime: 0` is required so phrases shorter than 1 s produce a decode window (default 1.0 yields an empty result silently). `usePrefillPrompt: true` with an explicit `language` prefills `<|sot|><|LANG|><|translate|><|notimestamps|>`. No conditioning on previous text: each phrase is a fresh `transcribe` call with no `promptTokens`. Only multilingual variants are in the catalog, so `.translate` always takes effect.
- **Transcribe:** `transcribe(audioArray: segment, decodeOptions: options)` → `[TranscriptionResult]`; the candidate's segments come from `result.segments` with `text`, `noSpeechProb` (always 0 in 1.1.0, documented in the code) and `averageLogProbability` **recomputed** as the mean of the log-probs in `segment.tokenLogProbs` whose token id is `< whisperKit.tokenizer!.specialTokens.specialTokenBegin` (`Models.swift:1116`), because WhisperKit's `avgLogprob` averages in five zero-valued special tokens. A segment with no word tokens gets `averageLogProbability = -.infinity` (dropped by the gate). `candidate.language = language`.
- **Serialisation:** one `transcribe` at a time (actor). `Task.checkCancellation` inside `TranscribeTask` propagates `CancellationError` when the pipeline stops mid-phrase; the adapter swallows it.
- **Errors:** `WhisperError` and any other error from `transcribe` → rethrown; the pipeline enters `.error` (Windows semantics). Load errors (`WhisperError.modelsUnavailable`, `.tokenizerUnavailable`, CoreML compile failures) are thrown from a separate `load()` step run before `pipeline.start`, so a broken model never puts the pipeline in error: the Live screen shows the M7 recovery banner (§9).
- Unload for memory pressure: `unloadModels()` only when idle (never mid-transcribe), then re-create.

### 6.5 PocketTTSSpeaker (`Speaker`) — API §5, R6

- **Manager:** `PocketTtsManager(defaultVoice: settings.voice, language: .english, directory: root, precision: .fp16, placement: .ane)`; `initialize()` on `load()` (no progress; the download happened first). `setDefaultVoice(_:)` when the user changes voice.
- **Download:** `PocketTtsResourceDownloader.ensureModels(language: .english, directory: root, precision: .fp16, placement: .ane, progressHandler:)` → files under `root/Models/pocket-tts/v2.1/english/` (≈ 527 MB; all 26 voices land on disk; the picker shows only alba, azelma, cosette, javert). The same `directory/precision/placement` triple must be used for the download and the manager so `initialize()` hits the cache.
- **Synthesis:** whitespace-only text → empty clip without calling the manager. Otherwise `synthesizeDetailed(text:voice:temperature:deEss:maxTokensPerChunk:)` with defaults (0.7, `true`, 50) and `AudioClip(samples: result.samples, sampleRate: 24_000)`. `samples` are de-essed but un-normalised; the player applies a fixed gain (§6.7).
- **Errors:** `PocketTTSError` or any error from `initialize()`/`synthesizeDetailed` → the `EffectiveSpeaker` wrapper switches to `SystemSpeaker` for the rest of the session, posts `SpeakerStatus.fallback(reason:)` to the status line ("Using system voice: pocket-tts failed to load") and does **not** fail the pipeline (F6). The failed manager is dropped (ARC releases the models; ASSUMED, M4 checks resident memory after a fallback).
- Memory: no unload API; `EffectiveSpeaker.unloadPocketTTS()` drops the manager under memory pressure (§9).

### 6.6 SystemSpeaker (`Speaker`) — API §6, R7

- **Voice:** `AVSpeechSynthesisVoice(identifier: settings.systemVoiceIdentifier)` when set and still present in `AVSpeechSynthesisVoice.speechVoices()`, else `AVSpeechSynthesisVoice(language: "en-US")`. The Voices screen lists `speechVoices().filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) }` sorted premium > enhanced > default (ASSUMED policy).
- **Synthesis (primary path):** `AVSpeechSynthesizer.write(_ utterance, toBufferCallback:)` collecting `AVAudioPCMBuffer`s until a buffer with `frameLength == 0` arrives (the terminating buffer is not documented; ASSUMED, M3 verifies) or a timeout of `max(3 s, 4 × estimated duration)` where the estimate is `characters / 15` seconds; buffers are converted to Float32 mono at the voice's native rate (`buffer.format.sampleRate`) and concatenated into one `AudioClip`. The synthesizer instance is retained by the actor for its lifetime. `utterance.volume = 1` (attenuation-only; loudness is matched in the player).
- **Fallback path (if `write` proves unreliable on device in M3):** `speak(_:)` with `usesApplicationAudioSession = true` and `AVSpeechSynthesizerDelegate` `didStart`/`didFinish`/`didCancel` driving the same speaking edges through a `PlaybackSink` that does not go through the engine. The core protocols do not change.
- Errors: no English voice available → `SpeakerError.noVoice` (status line "No English system voice; install one in Settings > Accessibility").

### 6.7 AudioPlayer (`AudioPlayer` + `PlaybackSink`) — API §7, R7

- **Graph:** one `AVAudioPlayerNode` attached to the mode's engine and connected to `engine.mainMixerNode` with `AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)`; the mixer→output format is never set (the mixer resamples to the hardware rate). Started with `play()` after `engine.start()`.
- **Enqueue:** `PlaybackQueue` (core) decides; the sink converts a clip whose `sampleRate != 24_000` with an `AVAudioConverter` created per distinct source rate (cached), applies the gain, wraps into `AVAudioPCMBuffer(pcmFormat: format, frameCapacity:)` (spelling ASSUMED per API §7; confirmed by compiling in M3) and calls `scheduleBuffer(_:completionCallbackType: .dataPlayedBack, completionHandler:)`; the completion calls `PlaybackQueue`'s completion off the callback thread.
- **Gain:** `voiceVolume × engineGain`, `engineGain = 0.7` for pocket-tts samples (un-normalised, ASSUMED starting value calibrated in M4 against the system voice at the same `voiceVolume`), `1.0` for system-voice clips; applied in the float domain, clamped to ±1.
- **Mute:** `stopCurrent()` = `playerNode.stop()` then `playerNode.play()` (stop clears every scheduled buffer and fires their completions, which the queue treats as drained); queued clips are discarded by `PlaybackQueue`.
- **Speaking edges:** from `PlaybackQueue` (first schedule → true; last `.dataPlayedBack` → false). The 250 ms hold lives in `DuckingCoordinator`; the 300 ms hold lives in `CaptureGate`.
- Errors: `scheduleBuffer` on a stopped engine (after an interruption) is a no-op; the session controller restarts the engine and the next clip plays.

### 6.8 AudioSessionController (`Ducker`, session and engine owner) — API §8, R8

- **Configuration per mode, applied in the foreground before `pipeline.start`:**

  | Mode | Category | Mode | Resident options |
  |---|---|---|---|
  | microphone | `.playAndRecord` | `.default` | `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]` |
  | broadcast | `.playback` | `.default` | `[.mixWithOthers]` |

  `setCategory(_:mode:options:)` then `setActive(true)`. Both masks are mixable, so the session can be re-activated from the background. One `AVAudioEngine` per mode, started in the foreground and never stopped while a session runs; `isAutoShutdownEnabled = false`.
- **Ducking (R8, owner brief):** when `settings.ducking` is on, `duck()` re-calls `setCategory` with the resident mask plus `.duckOthers` (same category, mode and route options, `.mixWithOthers` explicit) right before the first clip of a phrase plays; `restore()` after the `DuckingCoordinator` hold does `engine.pause()` → `setActive(false, options: .notifyOthersOnDeactivation)` → `setCategory(resident mask)` → `setActive(true)` → `engine.start()` (deactivating with a running engine returns `.isBusy`, hence the pause; `pause()` keeps prepared resources, the mic tap stays installed). "Duck on" is documented behaviour; whether an options-only `setCategory` without `.duckOthers` also un-ducks on a live session is undocumented — **M4 measurement plan:** play Music at a known level, log `engine.isRunning`, tap callback rate, `categoryOptions`, every `routeChangeNotification` reason and any `AVAudioEngineConfigurationChangeNotification`; apply the "on" mask, play a phrase, then (A) the options-only "off" mask and (B) the deactivation cycle; record the other app's level from the extension meter or a second device, the ramp time at both edges, and the mic gap; repeat on speaker, wired, A2DP, HFP and with ReVox in the background, on iOS 17, 18 and 26. If (A) restores the level without a config-change notification it becomes the primary path and (B) the fallback; the result is recorded in `docs/broadcast-bridge.md` and the README. Never keep `.duckOthers` resident, never use `setMode`, never add `.interruptSpokenAudioAndMixWithOthers` to the resident session.
- **Ducking off / mute:** `Ducker` is not called (coordinator disabled); mute calls `restoreNow()`.
- **Background keep-alive (C2):** `UIBackgroundModes = [audio]` (present), an active mixable session and a running engine with a live output. Apple documents no "must be non-silent" rule, so **M5 spike** (before the full broadcast flow): a throwaway extension writing into the ring plus a debug screen showing samples arriving; 30-minute locked-screen test in both modes with a foreign-language probe every 5 minutes; pass iff no `interruptionNotification` carrying `AVAudioSessionInterruptionWasSuspendedKey == true` (or reason `.appWasSuspended`), every probe is transcribed and `engine.isRunning` is still true; repeat in Low Power Mode and on A2DP. Escalation if it fails: schedule a looping silent buffer on the player node; then, in broadcast mode, keep a mic tap installed under `.playAndRecord` as a last resort. The working configuration is recorded verbatim in `docs/broadcast-bridge.md`.
- **Interruptions and routes:** `interruptionNotification` `.began` → pipeline keeps state, player stops; `.ended` with `.shouldResume` → `setActive(true)`, `engine.start()`, resume; `.began` with the suspended key → log, transcript drop marker, status "Translation paused by iOS". `routeChangeNotification`: `.oldDeviceUnavailable`/`.newDeviceAvailable` → mic tap rebuild (§6.1); `.categoryChange` → no-op. `mediaServicesWereResetNotification` → rebuild engine, converters, player; re-apply the category; restart the pipeline stages.
- One observer adapter wraps the interruption API so the iOS 27 replacement notifications can be swapped in (§12).

### 6.9 ModelManager (downloads, storage, readiness) — API §9, R4, R5

- **Root:** `root = <Application Support>/ReVox/Models`, created at launch with `isExcludedFromBackup = true`. WhisperKit writes `root/models/argmaxinc/whisperkit-coreml/<folder>/` and `root/models/openai/whisper-<size>/`; FluidAudio writes `root/Models/silero-vad/` and `root/Models/pocket-tts/v2.1/english/` (case-sensitive APFS on iOS keeps `models` and `Models` distinct siblings). The exclusion flag is re-applied to `root` and to every top-level model folder after every download and every verified load (file operations reset it).
- **Offline mode:** `ModelHub.offlineMode = true` at launch; the `ModelInstaller` actor flips it to `false` only for the duration of a user-initiated install and back in a `defer`. WhisperKit runtime always uses `modelFolder` + `download: false`. After install, nothing touches the network (§11).
- **Install steps:**
  - Whisper: `WhisperKit.download(variant: folderName, downloadBase: root, progressCallback:)` (returns the variant folder; progress units are files, not bytes) followed by `HubApiWrapper(downloadBase: root).snapshot(from: HubApiWrapper.Repo(id: tokenizerRepo), matching: ["tokenizer.json", "tokenizer_config.json", "config.json"], progressHandler:)`, which stores under `root/models/<tokenizerRepo>/` (`HubApi.localRepoLocation`, `downloadBase/models/<id>`), the first path WhisperKit's tokenizer loader searches (ASSUMED path equality; M3 verifies with an airplane-mode load).
  - VAD: `ModelHub.download(.vad, subdirectory:to:config:progressHandler:)` (§6.3).
  - pocket-tts: `PocketTtsResourceDownloader.ensureModels(...)` (§6.5).
  - Then a verified load (WhisperKit reaching `.loaded`/`.prewarmed`; `MLModel(contentsOf:)`; `PocketTtsManager.initialize()`), recorded in `UserDefaults.standard` under `verifiedLoads[<kind>:<library version>]`.
- **`ModelDownloadState`** (one type for the UI):

  ```swift
  enum ModelDownloadPhase: Equatable { case idle, listing, downloading(completedFiles: Int?, totalFiles: Int?), compiling(String?), verifying, installed, failed(String) }
  struct ModelDownloadState: Equatable { var phase: ModelDownloadPhase; var fraction: Double?; var bytesExpected: Int64; var cancel: (() -> Void)? }
  ```

  Bridging: WhisperKit `Progress.fractionCompleted` (file-count weighted) → `fraction`, phase `.downloading(nil, nil)`; the tokenizer snapshot contributes the last 2 % of the bar. FluidAudio `DownloadProgress.fractionCompleted` → `fraction`, `phase` `.listing` → `.listing`, `.downloading(completedFiles:totalFiles:)` → same, `.compiling(modelName:)` → `.compiling(name)`. `fraction` is determinate from the first callback; the bar never turns into a spinner (HIG). Cancel = cancel the awaiting `Task`; WhisperKit may rethrow `URLError(.cancelled)` or return a partial folder, so the URL is never trusted after cancellation and the installed check decides.
- **Installed check** (required files present): Whisper — `MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc`, `TextDecoder.mlmodelc` each containing `coremldata.bin`, plus `config.json`, plus the three tokenizer files; VAD — bundle dir with `coremldata.bin` and no `*.partial` beneath; pocket-tts — every member of `ModelNames.PocketTTS.requiredModels(precision: .fp16, placement: .ane)` present with `coremldata.bin`, `constants_bin/text_embed_table.bin`, `constants_bin/bos_before_voice.bin`, the four offered voice files, no `*.partial`. **Ready** = installed and a recorded verified load for the current library version.
- **Delete:** only while the pipeline is idle (button disabled otherwise, M7); Whisper — `removeItem` on the variant folder and its `.cache/huggingface/download/<variant>` sidecars; VAD — `ModelHub.clearCache(for: .vad, directory: root/Models)`; pocket-tts — `ModelHub.clearCache(for: .pocketTts, directory: root/Models)`. Never `clearAllCaches()`. Deleting the active Whisper model switches `settings.model` to the smallest installed model, or to none with a Live-screen prompt.
- **Free space:** before an install, `root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage`; refuse when `ModelCatalog.hasRoomToInstall` is false with "Not enough space: needs about N GB, M GB free"; warn (not refuse) when less than 1 GB would remain (ASSUMED thresholds).
- **Storage accounting (M7):** per-model on-disk size by enumerating the folder with `.totalFileAllocatedSizeKey`, cached and refreshed after install/delete; a "Free: N GB" line (DiskSpace reason `85F4.1`).
- Errors: `DownloadError`, `URLError`, `PocketTTSError.downloadFailed`, disk-full write failures → `.failed(message)` with Retry; partial downloads resume (both libraries support `Range` resume).

### 6.10 TranscriptStore (SwiftData, `TranscriptSink`) — API §10, R14

```swift
@Model final class Session {
    @Attribute(.unique) var id: UUID
    var startedAt: Date; var endedAt: Date?
    var captureMode: String; var pinnedLanguage: String?; var modelID: String; var voice: String
    var joinedInProgress: Bool
    @Relationship(deleteRule: .cascade, inverse: \Entry.session) var entries: [Entry]
}
@Model final class Entry {
    var timestamp: Date; var language: String; var original: String; var english: String
    var isDropMarker: Bool
    var session: Session?
}
```

- Container: `ModelConfiguration("ReVoxTranscripts", groupContainer: .none)` (explicit so the App Group entitlement never relocates the store), `isStoredInMemoryOnly: true` in tests.
- Writes happen on a `@ModelActor actor TranscriptStore` that implements `TranscriptSink` for one session (`add`, `addDropMarker` with the core dedupe rule via `TranscriptRecorder`'s flag, `close` sets `endedAt`). The pipeline's transcript factory returns a new store-backed sink per run.
- Search: `#Predicate<Entry> { $0.english.localizedStandardContains(query) }` sessions grouped by `session`; if `@Query.fetchError` reports the predicate unsupported, fall back to `contains` (ASSUMED store translation, M6).
- Export: entries → `[TranscriptItem]` → `TranscriptFormatter.export(startedAt:items:)` → written to `FileManager.default.temporaryDirectory/ReVox/<fileName>` → `ShareLink(item: url, preview: SharePreview(fileName, image: Image(systemName: "doc.text")))`. Temp files older than a day are pruned on launch (FileTimestamp reason `C617.1`).
- Housekeeping: swipe-to-delete a session; "Clear All" behind a `confirmationDialog` with the session count.

### 6.11 DeviceInfo

- `ProcessInfo.processInfo.physicalMemory` → `DeviceRecommendation.forPhysicalMemory(bytes:)` (the only input, C6/R13); logged once per launch with the `memoryTierGB` result.
- `ProcessInfo.processInfo.thermalState` observed through `ProcessInfo.thermalStateDidChangeNotification`; `isLowPowerModeEnabled`; `UIApplication.didReceiveMemoryWarningNotification`. Consumed by the M7 degradation policy (§9).
- `AppConfiguration` reads `REVOXAppGroup` and `REVOXBroadcastExtensionBundleID` from `Bundle.main.infoDictionary` and fails loudly at launch if either is missing.

---

## 7. ReVoxBroadcast extension design

`SampleHandler: RPBroadcastSampleHandler` (replaces the M0 stub). Budget: stay far below the 50 MB cap (community figure; target ≤ 15 MB resident measured in M5), ~150 wake-ups/s, and return from `processSampleBuffer` in well under the 23 ms buffer period.

### 7.1 Flow

1. `broadcastStarted(withSetupInfo:)`: read `REVOXAppGroup` from the extension's Info.plist; `containerURL(forSecurityApplicationGroupIdentifier:)`; create `Library/Application Support/ReVox/` if needed; `FileManager.createFile(atPath:contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])` if the ring file is absent; `FileHandle(forUpdating:)` + `truncate(atOffset: totalBytes)` only if the current size is smaller (never shrink); `mmap(MAP_SHARED)`; `RingWriter(storage:)`; `begin(generation: previous + 1, startedAt:, asbd: zero, pid:)`; write the `"broadcast.state"` record (`running`); post `<appGroup>.broadcast.started`. Preallocate the scratch buffers (§7.3).
2. `broadcastAnnotated(withApplicationInfo:)`: store `RPApplicationInfoBundleIdentifierKey` into the record's `annotatedBundleID` (diagnostic only).
3. `processSampleBuffer(_:with:)`: `.video` → return immediately; `.audioMic` → `writer.noteMicBuffer()`, return; `.audioApp` → §7.2 inside `autoreleasepool`.
4. `broadcastPaused()` / `broadcastResumed()`: `setState(.paused/.running)`, record, Darwin `paused`/`resumed`; cursors untouched; `converter.reset()` on resume (resampler history).
5. `broadcastFinished()`: `setState(.finished)`, record with `finishedAt`, post `stopped`, `munmap`, close the fd. Never truncate.
6. `finishBroadcastWithError(_:)` only for real failures (cannot map the ring, container missing) — replayd leaks memory per error-finish (community observation); the record gets `state = failed` and `finishReason`.

### 7.2 Format detection and conversion of `.audioApp`

- `CMSampleBufferGetFormatDescription` → `CMAudioFormatDescriptionGetStreamBasicDescription` → read the ASBD **at runtime** (the format is undocumented; community measurements say 44.1 kHz, SInt16, interleaved, 1–2 channels, **big-endian**, 1 024 frames per buffer). `mFormatID != kAudioFormatLinearPCM` → `noteDroppedInput`, log once, return.
- Change detection on `(mSampleRate, mChannelsPerFrame, mFormatFlags, mBitsPerChannel, mBytesPerFrame, mFramesPerPacket)`; on change (including the first buffer): `inputFormat = AVAudioFormat(streamDescription:)` (nil for > 2 channels → drop); `converter = AVAudioConverter(from: inputFormat, to: target)` with `target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)`; rebuild the preallocated input buffer for the new format; `writer.noteFormatChange(asbd, at:)`; update the record; post `formatChanged`; `os_log` the full ASBD (first at `.info`, later ones at `.error`) — this log is the M5 measurement of the real format.
- **Big-endian handling:** if `AVAudioConverter.init` returns nil and `mFormatFlags & kAudioFormatFlagIsBigEndian != 0`, describe the input as little-endian (clear the flag in a copy of the ASBD) and byte-swap the Int16 samples in place in the input buffer before conversion (the Twilio approach); if still nil → drop and count.
- Per buffer: `CMSampleBufferGetNumSamples`; `CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, 0, frames, inputBuffer.mutableAudioBufferList)` into the preallocated input `AVAudioPCMBuffer` (capacity 45 192 frames, the largest community-observed slice), set `frameLength`; `converter.convert(to: outputBuffer, error:, withInputFrom:)` with the once-`.haveData`-then-`.noDataNow` block until `.inputRanDry`; `writer.write(outputBuffer.floatChannelData![0] for frameLength, at: Date().timeIntervalSince1970, pts: CMSampleBufferGetPresentationTimeStamp)`; update the 1 s peak/RMS meter; post `<appGroup>.broadcast.audio` at most every 100 ms (1 600 frames) — one wake-up per ~4 input buffers.

### 7.3 Zero per-buffer allocation strategy

Allocated once per format (not per buffer): the input `AVAudioPCMBuffer` (45 192 frames × up to 2 ch × 2 B ≈ 181 KB), the output `AVAudioPCMBuffer` (capacity `ceil(45 192 × 16000 / 8000) + 64` frames = 90 448 frames × 4 B ≈ 362 KB, covering the lowest plausible input rate), the `AVAudioConverter`, the input block closure (stored, captures the input buffer), the Darwin `CFNotificationName`s, the level-meter accumulator. Per buffer: no `Data`, no arrays, no `String`s, no `os_log` (after the first), no `Task`, no dictionary writes (the record is written only at transitions), no file system calls. Swift concurrency is not used anywhere in the extension; everything runs on the single ReplayKit callback thread. The mapping (3.7 MB) plus buffers (< 1 MB) plus runtime is the whole footprint.

### 7.4 Ring writing, notifications, state record

- Writes follow `RingWriter` (§5.9): data, then cursor (release), then heartbeat. The extension never reads `readCursor` for flow control; if the app is absent the ring simply wraps (Control Center start while ReVox is closed is bounded by design).
- Darwin names derived from the App Group id: `<appGroup>.broadcast.started`, `.paused`, `.resumed`, `.stopped`, `.formatChanged`, `.audio` (extension → app, ≤ 10/s for `.audio`); `<appGroup>.app.attached` (app → extension, diagnostics). Posted with `CFNotificationCenterPostNotification(center, name, nil, nil, true)`.
- `UserDefaults(suiteName: appGroup)` key `"broadcast.state"`: `contractVersion 1`, `ringFile "audio-ring-v1.bin"`, `generation`, `state` (`running|paused|finished|failed|lost`), `startedAt`, `finishedAt`, `finishReason`, `writerPID`, `sourceASBD` (dictionary), `asbdChangeCount`, `annotatedBundleID`, `micToggleSeen`. Written only at transitions. The app writes `"capture.reader"` (`lastAttachedAt`, `lastReadCursor`, `generation`).
- Privacy manifest (present): UserDefaults `1C8F.1`, FileTimestamp `C617.1`; the DiskSpace entry is removed in M5 unless the extension actually checks free space.

### 7.5 What it must never do

No CoreML, no WhisperKit, no FluidAudio, no `AVAudioEngine`, no `AVAudioSession` changes, no network, no models, no VAD, no per-buffer allocation or logging, no `finishBroadcastWithError` for non-failures, no shrinking of the ring file, no reliance on the app being alive, no host-time APIs (`mach_absolute_time`, `AVAudioTime.hostTime`) — timestamps are `CMTime` PTS and `Date`, keeping the SystemBootTime reason out of the manifest.

---

## 8. UI design (SwiftUI, iOS 17, HIG)

### 8.1 Structure (R14)

`TabView` with `.tabItem { Label(...) }` (the `Tab` type is iOS 18+): **Live** (`waveform`), **History** (`clock`), **Settings** (`gearshape`). Each tab wraps its own `NavigationStack`. Models, Voices and About are pushed from Settings. iOS 17 APIs only: `ContentUnavailableView`, `ShareLink`, `confirmationDialog`, `@Observable` view models, SwiftData `@Query`. Dynamic Type, VoiceOver labels and 44 pt minimum targets throughout; colour is never the only status carrier; `.sensoryFeedback` on start/stop.

### 8.2 Live screen

- **Source picker:** segmented control Microphone / Other apps, disabled while running.
- **Start/Stop:** one large primary button (`mic.fill` / `stop.fill`), `.keyboardShortcut(.space)` on hardware keyboards; in broadcast mode it starts the pipeline and, if no broadcast is attached, shows the **broadcast picker** (`RPSystemBroadcastPickerView` embedded via `UIViewRepresentable`, 50×50 pt, `preferredExtension` set, mic button hidden) with the caption "Tap to choose ReVox and start the broadcast. You can also start it from Control Center's Screen Recording control." and a footnote "Locking the iPhone with the side button ends the broadcast."
- **Status line** (one `Label` row, wraps): model ("small · ready" / "Preparing…" / "No model"), voice ("alba (pocket-tts)" / "System voice — pocket-tts not downloaded" / "System voice — pocket-tts failed to load"), lag ("Falling behind" badge while `.lag` events arrive, cleared 5 s after the last), ducking ("Ducking" pill while ducked, or "Ducking off"), broadcast attach state.
- **Live transcript:** reverse-chronological list; each row shows `HH:mm:ss`, a language badge (detected or pinned code), the English text; drop markers render as a muted "… skipped: falling behind" row; "joined in progress" as a muted header. Auto-scrolls while at the bottom.
- **Mute** toggle in the toolbar (`speaker.slash`), reflecting `pipeline.isMuted`.
- **Empty state:** `ContentUnavailableView("Ready to translate", systemImage: "waveform.and.mic", description: "Choose a source and tap Start.")`. No model installed: `ContentUnavailableView` with a "Download small (≈ 487 MB)" button leading to Models.
- **Error surfaces:** permission denied → inline banner with "Open Settings"; pipeline `.error` → banner with the message and "Try again"; model load failure → banner per §9.

### 8.3 Models screen

Per-model row: name, "Recommended" badge (`DeviceRecommendation.recommended`), "Not recommended for this iPhone" caption when outside `suitable`, the heat warning caption for medium/large-v3 when present, the note for large-v3, "≈ N MB" (catalog) or the measured on-disk size when installed, state (Not downloaded / Downloading with a determinate `ProgressView` and phase text and Cancel / Installed / Selected / Failed with Retry), a Delete swipe action (disabled while running with the explanation "Stop translation to delete models"). Selecting an installed model updates `settings.model`. Footer: "Free: N GB" and the total used by ReVox models (M7). Low-storage refusal shows an alert with the exact numbers. The VAD row appears once ("Voice detector, ≈ 1 MB") and is installed automatically with the first Whisper model.

### 8.4 Voices screen

Two sections. **pocket-tts** (Kyutai): download row with progress (≈ 527 MB) when absent; otherwise alba, azelma, cosette, javert with a checkmark; a "Play sample" button synthesises "This is ReVox." (idle only). **System voices:** English voices from `speechVoices()` with quality labels; selecting one sets `voice = "system"` and `systemVoiceIdentifier`. A footer explains "ReVox uses the system voice until pocket-tts is downloaded, and falls back to it automatically if pocket-tts fails." Delete pocket-tts via swipe (idle only).

### 8.5 Settings screen

- Latency mode: Balanced (default) / Fast picker with the Windows descriptions (silence 500 ms, max 10 s / 300 ms, max 4 s).
- Source language: picker "Auto-detect" plus Whisper language codes; blank = auto.
- Mute voice toggle (mirrors the Live toolbar).
- Ducking toggle and **Voice volume** slider with help text: "While ReVox speaks, iOS lowers other audio by an amount iOS decides. The Windows ducked-level slider has no iOS equivalent; use Voice volume to balance ReVox's own voice."
- Links: Models, Voices, About.
- Storage of settings: `SettingsCodec` file; every change saved immediately.

### 8.6 History and Session detail

- History: `@Query` of sessions newest first; each row shows date/time, source, duration, entry count, first English line. `.searchable` filters entries by English text and shows matching sessions with the matching line. Empty: `ContentUnavailableView("No Transcripts", systemImage: "text.bubble", description: "Sessions you translate appear here.")`; search empty: `ContentUnavailableView.search`. Swipe to delete; "Clear All" via `confirmationDialog`.
- Session detail: header (start time, source, model, voice, language pin), the entries in the Live row style, `ShareLink` toolbar item exporting the `.txt`, and a Delete item.

### 8.7 About

App name and version, a paragraph on on-device processing and privacy, the licences list from `ModelCatalog.licences` with `Link`s, and the Kyutai attribution line for the pocket-tts weights (CC-BY-4.0), plus a link to the ReVox Windows project and the README's platform-limitations section.

### 8.8 Error surfaces and accessibility notes

Download failure (row state Failed + Retry, alert only on user-initiated actions), low storage (alert with numbers before starting), permission denied (inline banner + Settings link, never a modal loop). All banners are `accessibilityAddTraits(.updatesFrequently)` free; the status line uses `accessibilityLabel` sentences ("Model small ready. Using system voice."); the picker button has an explicit label; progress views announce percentages.

---

## 9. Error handling and recovery matrix

| Condition | Detected by | Behaviour | User-visible |
|---|---|---|---|
| Whisper load failure (missing files, CoreML compile error, `WhisperError`) | `WhisperKitTranslator.load()` before start | Pipeline never starts in error; mark the model not ready; M7: if a smaller installed model exists, load it instead | Banner "Couldn't load small. Using base instead." or "Re-download small in Models." |
| Whisper failure mid-run (`transcribe` throws) | translate stage | Pipeline `.error`, stop cleans up (Windows semantics); M7 retries once after unload/reload before surfacing | Banner with Try again |
| pocket-tts load or synthesis failure | `EffectiveSpeaker` | Switch to `SystemSpeaker` for the session; pipeline continues | Status line "System voice — pocket-tts failed"; Voices screen shows Retry |
| VAD load failure | `SileroVAD.load()` | Pipeline cannot start; offer re-download | Banner "Voice detector failed to load" |
| Download failure / cancel | `ModelManager` | State `.failed(message)`; partial files kept for resume; `offlineMode` restored | Row Failed + Retry |
| Disk full during download | write error surfaced by the library | Same as failure; free-space check prevents most cases | Alert "Not enough space" |
| Microphone permission denied | `AVAudioApplication` | Start refused | Inline banner + Open Settings |
| Audio interruption began | `interruptionNotification` | Player stops, state retained; suspended-key case adds a drop marker | Status "Paused by iOS" |
| Interruption ended (`.shouldResume`) | same | `setActive(true)`, `engine.start()`, resume | Status clears |
| Route change | `routeChangeNotification` | Rebuild tap/converter for device changes; ignore `.categoryChange` | none |
| Media services reset | `mediaServicesWereResetNotification` | Rebuild engine graph, re-apply category, restart stages | Status "Audio restarted" |
| Broadcast ended by system (power button, phone call, user) | Darwin `stopped` + record `finishReason` | Pipeline stops cleanly, session closed | "Broadcast ended" (+ lock-screen hint for `systemDormancy`) |
| Broadcast heartbeat stale (extension killed) | `RingReader.attach` → `.stale` | Stop reading; record `lost` | "The broadcast stopped unexpectedly" |
| Ring overrun (app was slow) | `ReadResult.gap` | Drop marker; reader jumps forward | "Falling behind" badge |
| Memory warning | `didReceiveMemoryWarningNotification` | Drop pocket-tts (fall back to system voice); M7: if Whisper was evicted or fails next call, drop to a smaller installed model | Banner "Memory low: switched to base / system voice" |
| Thermal state `.serious` | `thermalStateDidChangeNotification` | M7: prefer the next smaller installed model for new sessions; `.critical` pauses translation until it recovers | Banner "iPhone is hot: translation paused/reduced" |
| Backpressure | `BoundedSegmentQueue` | Oldest segment dropped, `.lag`, drop marker | Badge + transcript marker |
| Settings file corrupt | `SettingsCodec` | Defaults, file rewritten on next save | none |

Every path restores ducking (`DuckingCoordinator.restoreNow()`), closes the transcript and leaves the session in `.idle` or `.error` with a message; there is never a silent hang.

---

## 10. Testing strategy

### 10.1 ReVoxCore tests (Linux and simulator), one-to-one with the Windows tests

| Windows test | Swift counterpart (`ReVoxCoreTests`) |
|---|---|
| `test_segmenter.py::test_presets` | `SegmenterTests.testPresets` (+ `testChunkCounts` for 15/9, 312/125, 6) |
| `test_emits_segment_after_silence_gap` | `SegmenterTests.testEmitsSegmentAfterSilenceGap` |
| `test_no_segment_for_pure_silence` | `SegmenterTests.testNoSegmentForPureSilence` |
| `test_short_pause_does_not_split` | `SegmenterTests.testShortPauseDoesNotSplit` |
| `test_long_pause_splits` | `SegmenterTests.testLongPauseSplits` |
| `test_max_segment_forces_emit` | `SegmenterTests.testMaxSegmentForcesEmit` |
| `test_flush_returns_partial` | `SegmenterTests.testFlushReturnsPartial` |
| `test_silero_vad_loads_and_scores_silence` (integration) | on-device manual check in M3 (`SileroVAD` scores zeros < 0.5); not a unit test |
| `test_stt.py::test_translate_joins_segments_and_reports_language` | `TranslationStageTests.testJoinsSegmentsAndReportsLanguage` |
| `test_language_pin_passed_through` | `TranslationStageTests.testLanguagePinPassedThrough` |
| `test_rejects_high_no_speech_prob` | `SpeechGateTests.testRejectsHighNoSpeechProbability` |
| `test_rejects_low_avg_logprob` | `SpeechGateTests.testRejectsLowAverageLogProbability` |
| `test_rejects_hallucination_phrases` | `SpeechGateTests.testRejectsHallucinationPhrases` (+ `testNormalization`) |
| `test_rejects_unsure_language_when_autodetecting` | `TranslationStageTests.testRejectsUnsureLanguageWhenAutoDetecting` |
| `test_resolve_device_explicit`, `test_default_models`, `test_cuda_failure_falls_back_to_cpu` | not applicable (no CUDA); replaced by `DeviceRecommendationTests` |
| `test_pipeline.py::test_happy_path_translates_and_speaks` | `TranslationPipelineTests.testHappyPathTranslatesAndSpeaks` |
| `test_backpressure_drops_oldest_and_reports_lag` | `TranslationPipelineTests.testBackpressureDropsOldestAndReportsLag` (+ `BoundedSegmentQueueTests`) |
| `test_speaking_transitions_drive_ducking` | `TranslationPipelineTests.testSpeakingTransitionsDriveDucking` |
| `test_system_mode_ducks_all` | `TranslationPipelineTests.testBothModesDuck` |
| `test_mute_forwards_to_player` | `TranslationPipelineTests.testMuteForwardsToPlayerAndRestoresDucking` |
| `test_translator_error_emits_error_state` | `TranslationPipelineTests.testTranslatorErrorEmitsErrorState` |
| `test_stop_cleans_up` | `TranslationPipelineTests.testStopCleansUpAndIsIdempotent` |
| (new, A7/R9) | `CaptureGateTests.*`, `TranslationPipelineTests.testSpeakingClosesCaptureGateFor300ms` |
| `test_playback.py::test_enqueue_plays_and_toggles_speaking` | `PlaybackQueueTests.testEnqueuePlaysAndTogglesSpeaking` |
| `test_empty_arrays_ignored` | `PlaybackQueueTests.testEmptyClipsIgnored` |
| `test_mute_discards_audio` | `PlaybackQueueTests.testMuteDiscardsAudio` |
| `test_stop_idempotent_and_closes_stream` | `PlaybackQueueTests.testStopIdempotent` |
| `test_ducking.py::test_duck_twice_is_noop_and_restore_idempotent` | `DuckingCoordinatorTests.testDuckTwiceIsNoOpAndRestoreIdempotent` |
| `test_quiet_sessions_left_alone`, `test_duck_specific_app_only`, `test_duck_system_mode_excludes_self`, `test_restore_skips_vanished_sessions` | not applicable (iOS has no per-session volume); replaced by `DuckingCoordinatorTests.testDisabledNeverCallsDucker`, `testHoldDelaysRestore`, `testRetriggerInsideHoldKeepsDucked` |
| `test_transcript.py::test_creates_file_with_header` | `TranscriptFormatterTests.testHeaderAndFileName` |
| `test_add_appends_and_flushes_without_close` | `TranscriptRecorderTests.testAddAppendsEntryLines` |
| `test_drop_marker_deduplicated` | `TranscriptRecorderTests.testDropMarkerDeduplicated` |
| `test_close_idempotent` | `TranscriptRecorderTests.testCloseIdempotent` (+ `TranscriptFormatterTests.testGoldenExport`) |
| `test_config.py::test_defaults` | `SettingsTests.testDefaults` |
| `test_round_trip` | `SettingsTests.testRoundTrip` |
| `test_load_missing_file_returns_defaults` | `SettingsTests.testMissingFileReturnsDefaults` |
| `test_load_corrupt_json_returns_defaults` | `SettingsTests.testCorruptJSONReturnsDefaults` |
| `test_load_ignores_unknown_and_fills_missing` | `SettingsTests.testIgnoresUnknownAndFillsMissing` (+ `testWrongTypesReturnDefaults`, `testWindowsFileDecodes`) |
| `test_transcript_dir_default_and_override` | not applicable (setting dropped) |
| `test_base.py::test_to_mono_16k_downmixes_and_resamples` | `AudioFormatTests.testDownmixAveragesChannels` (core) + `ResamplerTests.testStereo48kTo16k` (app) |
| `test_to_mono_16k_passthrough_at_16k_mono` | `AudioFormatTests.testPassthroughAt16kMono` |
| `test_fake_backend_reads_fed_chunks` | `FakeAudioSourceTests.testReadsFedChunks` |
| `test_app_mode_requires_pid`, `test_invalid_mode_rejected` | `SettingsTests.testInvalidCaptureModeDefaults` |
| (new, R10) | `RingBridgeTests.*` (header golden bytes, wrap, overrun, torn cursor, generation change, attach table) |
| (new, R4/R13) | `ModelCatalogTests.*`, `DeviceRecommendationTests.*` |

Fakes in `ReVoxCoreTests/Fakes/`: `FakeAudioSource` (feed chunks, records start/stop), `EnergyVAD` (`SpeechProbabilityModel`), `FakeLanguageDetector`, `FakeTranslator` (gate via a continuation, `fail` flag, records language), `FakeSpeaker` (100 ones at 24 kHz), `FakePlayer`/`FakePlaybackSink` (records clips, mute, stop; completes on demand), `FakeDucker` (counts), `FakeTranscriptSink`, `FakeClock`, `TornCursorStorage`. Every protocol has exactly one fake and no test touches the file system except through `FileManager.temporaryDirectory`.

### 10.2 App tests (`ReVoxMobileTests`, simulator, no models, no network)

`ResamplerTests` (AVAudioConverter 48 kHz stereo → 16 kHz mono, count within ±16), `MappedRingStorageTests` (ring over a temp file: writer and reader on two threads, atomics shim), `SettingsStoreTests` (Application Support path round trip), `TranscriptStoreTests` (in-memory SwiftData: add/drop/close, search predicate, export text equals `TranscriptFormatter` output), `ModelManagerTests` (installed checks over fabricated folder layouts, free-space rule, delete refused while running, `ModelDownloadState` bridging from synthetic `Progress` and `DownloadProgress` values), `BroadcastConversionTests` (big-endian Int16 `CMSampleBuffer` fabricated in-process → 16 kHz Float32; format-change rebuild; no allocation growth across 1 000 buffers measured with `mach_task_basic_info`), `AudioSessionMaskTests` (duck-on/off masks differ only by `.duckOthers`), view-model tests for Live/Models/Voices state transitions. Anything requiring a device (permissions, engine I/O, CoreML, the extension process) is excluded by `#if targetEnvironment(simulator)` guards where necessary.

### 10.3 CI proof per milestone

| Milestone | CI evidence (both jobs green) |
|---|---|
| M2 | `core-linux` runs every mirrored test; a coverage script asserts each ported constant (`0.5`, `200`, `500/10`, `300/4`, `0.85`, `−1.2`, `0.4`, `3`, `4 800`, hallucination set) appears in an assertion |
| M3 | simulator tests for resampler, settings, store, catalog bridging; TestFlight upload job succeeds |
| M4 | `PlaybackQueue`/ducking tests; mask tests; TestFlight build notes carry the ducking measurement |
| M5 | ring bridge tests on both platforms; `BroadcastConversionTests`; extension builds under `APPLICATION_EXTENSION_API_ONLY`; `docs/broadcast-bridge.md` present |
| M6 | store/search/export tests; golden export file |
| M7 | degradation policy tests (fake thermal/memory signals); privacy grep gate (§11) in the TestFlight workflow |

### 10.4 On-device measurements that gate ASSUMED items

| ASSUMED item | Measured in |
|---|---|
| `physicalMemory` values on 4/6/8 GB iPhones and the GiB rounding | M3 |
| `langProbs` value is a log-probability; `exp` lands in [0, 1] | M3 |
| Windows 0.5 threshold transfers to the CoreML 512-sample export; `.cpuOnly` vs `.cpuAndNeuralEngine` numerics | M3 |
| Converter feeding pattern (`.haveData` then `.noDataNow`) has no chunk-edge clicks | M3 |
| Tokenizer snapshot path equals WhisperKit's search path; airplane-mode load succeeds | M3 |
| `AVSpeechSynthesizer.write` terminating buffer and reliability; else `speak()` fallback | M3 |
| `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` / `bufferListNoCopy` spellings compile | M3 / M5 |
| Hallucination rate on 0.4–1 s phrases with `windowClipTime: 0` | M3 |
| Options-only un-duck vs deactivation cycle; ramp time; engine survival | M4 |
| pocket-tts `.ane` RTF, resident memory, cold compile; ANE contention with Whisper; gain calibration 0.7 | M4 |
| ARC releases pocket-tts models when the manager is dropped | M4 |
| 30-minute background keep-alive in both modes | M5 spike |
| `.audioApp` ASBD; big-endian acceptance by `AVAudioConverter`; own-TTS re-capture and ducked level | M5 |
| Extension footprint with the mapping; auto-lock survival; atomics shim; `MAP_SHARED` accounting | M5 |
| Cross-process `UserDefaults(suiteName:)` freshness after a Darwin wake | M5 |
| SwiftData `localizedStandardContains` translation | M6 |
| Free-space rule thresholds; App Store scan of SDK `attributesOfItem` calls | M3 / M7 |

---

## 11. Security and privacy

- **App Group data flow:** the only data crossing the process boundary is 16 kHz mono audio in the ring file, the header, the `broadcast.state`/`capture.reader` records and Darwin notification names (no payload). The ring lives in the App Group container under `Library/Application Support/ReVox/`, is created with `FileProtectionType.completeUntilFirstUserAuthentication` (Apple's documented default; the only class a process can open after a later lock), and is excluded from backup. It is overwritten continuously and zeroed on `broadcastStarted`. No audio is ever written to disk by the app; models and transcripts live in the app's own container.
- **Transcripts** are stored in the app container by SwiftData (default `.completeUntilFirstUserAuthentication`), excluded from nothing (the user's transcripts may be backed up like other app data); exported temp files are pruned after a day.
- **Privacy manifests:** app — UserDefaults `CA92.1` (`UserDefaults.standard` for verified-load records and UI state), `1C8F.1` (App Group suite), FileTimestamp `C617.1` (temp-file pruning and absorbing the SDKs' `attributesOfItem` calls), DiskSpace `E174.1` (refusing downloads without space), `85F4.1` (the Free line on Models); extension — UserDefaults `1C8F.1`, FileTimestamp `C617.1`. **No SystemBootTime**: all timing uses frame counts, `Date`, `ContinuousClock` and `CMTime`; a grep gate in the TestFlight workflow fails on `hostTime`, `mach_absolute_time`, `systemUptime` or any covered API inside `ReVoxCore`.
- **No network after install:** `ModelHub.offlineMode = true` except inside `ModelInstaller`; WhisperKit runtime with `modelFolder` and `download: false`; no analytics, crash reporters or telemetry SDKs; the only hosts contacted, and only during a user-initiated install, are `huggingface.co` and its CDN. `ITSAppUsesNonExemptEncryption = false` in both plists.
- **Microphone:** requested only when the user starts mic mode; `NSMicrophoneUsageDescription` states that audio never leaves the device. Broadcast mode uses no microphone (`.playback` session, `showsMicrophoneButton = false`, `.audioMic` buffers ignored and counted).
- **Extension surface:** no network entitlement use, no keychain, no third-party code; App Group only.
- **Model integrity:** installed check plus verified load; file sizes recorded at install so an upstream change on `main` (FluidAudio cannot pin revisions) is flagged as "upstream changed" in M7 rather than silently used.

---

## 12. Platform limitations to document, and the iOS 27 seams

Documented in the README and the About screen:

1. **Ducking:** iOS cannot set another app's volume. ReVox uses `.duckOthers`; iOS chooses the amount and ramp. The Windows ducked-level slider has no iOS equivalent; the Voice volume slider adjusts ReVox's own voice only. Whether un-ducking can be done without a brief session deactivation is measured in M4 and the outcome recorded.
2. **Broadcast start:** other apps' audio requires a user-started system broadcast (picker in ReVox or Control Center's Screen Recording control); ReVox cannot start or stop it programmatically; pressing the side button ends it; some players (AVPlayer-based, Safari, Music) deliver silence to broadcasts.
3. **Extension memory:** 50 MB cap; the extension only forwards audio; every model runs in the app; a Control Center broadcast started while ReVox is closed is buffered for at most 60 s.
4. **Background:** translation continues under the `audio` background mode while the session and engine run; the app must be started from the foreground first; iOS may still suspend the app under memory pressure, in which case the transcript shows a gap.
5. **Self-capture:** in broadcast mode the extension also hears ReVox's English voice; the timing gate drops audio while ReVox speaks and for 300 ms after, so speech that overlaps ReVox's voice is not translated.
6. **Heat and battery:** medium and large-v3 are offered only on 8 GB devices with a warning.

iOS 27 seams (no iOS 27 code in v1): ReplayKit's broadcast API, `AVAudioSession.InterruptionType`/`Options` and `.tabItem` are deprecated at 27 and ScreenCaptureKit becomes the capture replacement; background ANE use needs `com.apple.developer.background-tasks.continued-processing.inference`. The design isolates each: `AudioSource` (`BroadcastCapture` today, a `ScreenCaptureKitSource` with `excludesCurrentProcessAudio = true` later, which would also make the `CaptureGate` unnecessary in that mode), one interruption-observer adapter inside `AudioSessionController`, a "no-ANE" compute tier in `SileroVAD`/`WhisperKitTranslator` construction, and the tab container in a single `RootView`.

---

## 13. Open questions carried forward

| # | Question | Answered in |
|---|---|---|
| 1 | Do the Windows 0.5 threshold and segment boundaries reproduce on the CoreML 512-sample export (A/B on identical audio)? | M3 |
| 2 | Is `exp(langProbs[language])` a probability in [0, 1] on device, and how often does the 0.4 gate fire on real speech? | M3 |
| 3 | Does `AVSpeechSynthesizer.write` deliver a zero-length terminating buffer reliably, or does `SystemSpeaker` need the `speak()` path? | M3 |
| 4 | Per-phrase latency of base and small on A14–A18 with `temperatureFallbackCount: 0`; hallucination rate on sub-second phrases | M3 |
| 5 | Can `.duckOthers` be removed on a live session without deactivation; ramp time; behaviour on HFP/A2DP routes and in the background? | M4 |
| 6 | pocket-tts `.ane` real-time factor, resident memory, cold ANE compile, and ANE contention with Whisper when translate(N+1) overlaps speak(N); the 0.7 gain | M4 |
| 7 | Does dropping the `PocketTtsManager` release model memory? | M4 |
| 8 | Does a `.playback`/`.playAndRecord` mixable session with a running engine keep the app alive for 30 minutes locked, in Low Power Mode and on A2DP? | M5 spike |
| 9 | Real `.audioApp` ASBD on iOS 17/18/26; does `AVAudioConverter` accept the big-endian flag; is ReVox's own voice re-captured, ducked or un-ducked? | M5 |
| 10 | Extension resident footprint; does a broadcast survive auto-lock; which atomic primitive the shim uses; `MAP_SHARED` accounting | M5 |
| 11 | Are cross-process `UserDefaults(suiteName:)` reads fresh immediately after a Darwin wake? | M5 |
| 12 | Does the SwiftData store translate `localizedStandardContains`? | M6 |
| 13 | Does App Store Connect flag the SDKs' `attributesOfItem` calls; are the manifests complete? | M3 (first upload) |
| 14 | Free-space thresholds and storage accounting accuracy; upstream-change detection for unpinned FluidAudio downloads | M7 |
| 15 | Thermal/memory degradation thresholds (`.serious`, warning) and whether model eviction is observable before the next call fails | M7 |
| 16 | Tokenizer file redistribution and whether a ReVox-owned mirror is needed | M7 |
