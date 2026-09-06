# ADR-0007: pocket-tts speaks English; replies are spoken by an iOS voice for the target language

## Status

Accepted

## Date

Rulings R6 and R7 in the design spec of 2026-09-02; the reply routing added in milestone 8 (2026-09-04); recorded 2026-09-04. Milestone 11 (2026-09-05) renamed the picker to **They speak**; the decision is unchanged. The 1.0.0 release (2026-09-06) dropped cosette from the offered voices because its source clip is licensed CC BY-NC 4.0 ([docs/model-revisions.md](../model-revisions.md)); the decision is unchanged.

## Context

ReVox's own voice is Kyutai's pocket-tts, run through FluidAudio with `language: .english`; the three offered voices (alba, azelma, javert) are English voices, and extra pocket-tts languages are a v1 non-goal. Until pocket-tts is downloaded — about 527 MB — and whenever it fails to load or to speak, ReVox uses `AVSpeechSynthesizer`, the iPhone's own voice, which needs no download. With two-way conversation ([ADR-0006](0006-whisper-translate-is-english-only.md)) ReVox also has to speak phrases that are *not* English.

## Decision

- The **system voice is the default and the automatic fallback**: it is used until pocket-tts is installed, and `EffectiveSpeaker` switches to it for the rest of a session if pocket-tts fails, posting the reason to the status line ("Using system voice: pocket-tts failed to load") without failing the pipeline. The Voices screen lists both engines and offers Retry.
- **pocket-tts speaks English only.** A phrase in any other language — the reply half of a two-way conversation — goes straight to the system voice with an `AVSpeechSynthesisVoice` for that language. If the iPhone has no voice for the language the user picks under **They speak**, the pill shows a crossed speaker and the ⓘ panel says so while they are picking it; the user adds one in iOS Settings › Accessibility › Spoken Content › Voices.
- Under memory pressure the pocket-tts models are dropped first and the session continues with the system voice.

## Consequences

- No download is required to hear ReVox at all; pocket-tts is an upgrade for the English direction.
- ReVox never selects pocket-tts unless its installed check passes (`bos_before_voice.bin` plus every offered voice file), because pocket-tts has fetch paths that bypass `ModelHub.offlineMode`; only the three offered voices are ever synthesised, so no request is issued after install (airplane-mode row, `pending device measurement`).
- The pocket-tts gain (`0.7`) is calibrated against the system voice at the same volume so switching engines does not change loudness; the value is an M4 measurement row.

## Sources

- Design spec [§6.5 PocketTTSSpeaker](../superpowers/specs/2026-09-02-revox-mobile-design.md#65-pocketttsspeaker-speaker--api-5-r6), [§6.6 SystemSpeaker](../superpowers/specs/2026-09-02-revox-mobile-design.md#66-systemspeaker-speaker--api-6-r7), §3 rows F5 and F6, [§12](../superpowers/specs/2026-09-02-revox-mobile-design.md#12-platform-limitations-to-document-and-the-ios-27-seams) item 6.
- [`ReVoxMobile/Speech/EffectiveSpeaker.swift`](../../ReVoxMobile/Speech/EffectiveSpeaker.swift) ("pocket-tts speaks English only (§6.5), so a phrase in any other language goes straight to the system voice with a voice for that language").
- README, "Two-way conversation", "How ReVox handles failure" (The voice, Memory pressure).
