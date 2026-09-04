# ADR-0003: ReVox drives the Silero VAD export itself, not through FluidAudio's `VadManager`

## Status

Accepted

## Date

Ruling R1 in the design spec of 2026-09-02; recorded 2026-09-04.

## Context

The Windows version of ReVox decides speech on every 512-sample chunk at 16 kHz with a threshold of 0.5, 200 ms of pre-roll, and its own silence and maximum-length rules; the phrase boundaries the user sees follow from exactly that. ReVox Mobile uses FluidAudio to download the Silero model and to run pocket-tts, and FluidAudio also offers a `VadManager`. That API scores 4 096-sample chunks, combines them with noisy-OR aggregation and pads shorter input, so feeding it 512-sample chunks would change where phrases begin and end — and passing the 512-sample bundle to `VadManager` would build 4 160-sample inputs and fail.

## Decision

ReVox loads FluidAudio's 512-sample Core ML export (`silero-vad-unified-v6.0.0.mlmodelc`) directly with `MLModel` and feeds it chunk by chunk from an actor (`SileroVAD`), carrying the model's recurrent state (`hidden_state`, `cell_state`) and the 64-sample context between calls exactly as the Windows segmenter does. `VadManager` is never used for voice detection; `processStreamingChunk` is never called with 512 samples. The compute unit starts as `.cpuOnly`; the `.cpuAndNeuralEngine` comparison is an M3 device measurement.

## Alternatives considered

- **`VadManager` with its own batching** ("Option A" in the API reference): rejected by R1, because the segmenter semantics must be identical to Windows; the spec's non-goals also rule out adding a `minSpeechChunks` pre-filter for the same reason.

## Consequences

- Segmentation on iOS is the same algorithm as on Windows, so the transcripts of both can be compared phrase for phrase (M3 measurement row 3, `pending device measurement`).
- ReVox depends on the export's input/output names and shapes, verified from the bundle's `model.mil`; a change upstream would surface as a load failure, which the app reports as "Voice detector failed to load. Re-download it in Models." and refuses to start.
- Whether the Windows 0.5 threshold transfers unchanged to the Core ML export is an ASSUMED item that only a device A/B can confirm.

## Sources

- Design spec [§6.3 SileroVAD](../superpowers/specs/2026-09-02-revox-mobile-design.md#63-silerovad-speechprobabilitymodel--api-32-r1) and [§2 Non-goals](../superpowers/specs/2026-09-02-revox-mobile-design.md#non-goals-v1) (the `VadManager` batching fallback is not added).
- README, "Why ReVox drives Silero VAD itself"; [`ReVoxMobile/VAD/SileroVAD.swift`](../../ReVoxMobile/VAD/SileroVAD.swift).
- [`docs/measurements/m3-microphone-mode.md`](../measurements/m3-microphone-mode.md) row 3.
