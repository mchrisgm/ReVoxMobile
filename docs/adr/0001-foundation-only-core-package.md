# ADR-0001: The pipeline lives in a Foundation-only package that tests on Linux

## Status

Accepted

## Date

Decided in the design spec of 2026-09-02; recorded 2026-09-04.

## Context

ReVox Mobile is a one-to-one port of the Windows ReVox pipeline: the segmenter, the speech gates, the backpressure queue, the playback queue, the transcript format, the model catalog and the settings all have a Windows counterpart with its own tests. The port has to prove that it reproduces those semantics, and it has to do so in an authoring environment that has no Xcode (see [ADR-0002](0002-ci-is-the-compiler.md)). Apple Foundation and swift-corelibs-foundation also differ in small ways — `Calendar`/`DateComponents` formatting, `JSONEncoder.sortedKeys`, `lowercased()` — that a port can trip over silently.

## Decision

Everything with a Windows counterpart, plus the ring-bridge types, goes into `ReVoxCore`, a local Swift package (`swift-tools-version 5.10`, platforms iOS 17 / macOS 14) that imports **Foundation only** — no UIKit, AVFoundation, CoreML, SwiftUI, CoreMedia or ReplayKit — and does no I/O beyond the byte-level ring accessors it is handed. Its test target `ReVoxCoreTests` runs in both CI jobs: `swift test` in a Linux container (`core-linux`) and inside the `ReVoxMobile` scheme on the iPhone simulator (`ios-simulator`), so both Foundations are verified on every push. The app (`ReVoxMobile`) holds the adapters that bind the core to iOS and to the two pinned libraries; the extension (`ReVoxBroadcast`) imports the core's ring types only.

A CI gate (`scripts/ci/check-constant-coverage.sh`) requires every constant ported from the Windows sources to be asserted by name and value in `ReVoxCoreTests`, so a renamed or dropped assertion cannot pass unnoticed.

## Consequences

- The core's 193 tests run on Linux in seconds, without a Mac, and again on the simulator in the same run.
- Time-based waits inside the core go through an injected `sleep` closure and audio is handed in as `[Float]`, so no core test touches the wall clock, a microphone or a model.
- Foundation has no resampler, so the core ships a linear-interpolation `AudioFormat.resample` as the reference path and the app resamples with `AVAudioConverter` in production (spec deviation W1, both within the Windows ±16-sample tolerance).
- Anything platform-specific — VAD inference, Whisper, pocket-tts, the audio session, SwiftData — must live behind a protocol the core defines (`AudioSource`, `SpeechProbabilityModel`, `Translator`, `Speaker`, `Ducker`, `TranscriptSink`) and be tested with fakes in `ReVoxMobileTests`.

## Sources

- Design spec [§2 Goals](../superpowers/specs/2026-09-02-revox-mobile-design.md#2-goals-and-non-goals) (goal 2), [§4.1 Targets and package](../superpowers/specs/2026-09-02-revox-mobile-design.md#41-targets-and-package), [§4.4 What runs where](../superpowers/specs/2026-09-02-revox-mobile-design.md#44-what-runs-where-r1-c4), §10.1.
- [`ReVoxCore/Package.swift`](../../ReVoxCore/Package.swift), [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) (jobs `core-linux`, `ios-simulator`, step "Core tests ran on the simulator").
