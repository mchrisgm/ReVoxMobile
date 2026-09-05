# ADR-0006: Whisper translates into English only; the second direction uses Apple's Translation framework

## Status

Accepted

## Date

Non-goal in the design spec of 2026-09-02; the second direction added in milestone 8 (2026-09-04); recorded 2026-09-04. Milestone 11 (2026-09-05) renamed the surfaces to **You speak** / **They speak**; the decision is unchanged.

## Context

Whisper's `translate` task produces English and nothing else. That is what ReVox is built on — every phrase heard is translated to English on-device by WhisperKit — and non-English target languages were a stated v1 non-goal. Milestone 8 added a two-way conversation: the user's own language is skipped, and what they say should be spoken back to the other person in *their* language. That is a translation *out of* English (or out of the skipped language), which Whisper cannot do.

## Decision

The English direction stays on Whisper. The reply direction uses Apple's on-device **`Translation` framework**, which exists from **iOS 18**. The app's deployment target stays iOS 17, so `Translation.framework` is **weak-linked** in `project.yml` and every use sits behind `if #available(iOS 18, *)` (`TwoWayTranslation`); an iOS 17 iPhone must still launch. On iOS 17, and on any language pair iOS has no model for, the phrase is still transcribed in the language it was spoken in — it is simply not spoken back, and the Live screen says which case applies rather than falling silent.

## Alternatives considered

- **A second Whisper pass for the reply**: Whisper has no non-English target, so there is nothing to run.
- **Raising the deployment target to iOS 18**: would drop iOS 17 iPhones for a feature that degrades cleanly to transcript-only; not taken.

## Consequences

- Two-way needs **Source language = Auto-detect** (a pinned language is never detected) and the language you speak chosen under **You speak** (Settings › Your language, or the pill on the Live tab).
- The reply is only ever as available as iOS's own translation models on that iPhone; ReVox neither downloads nor ships them.
- The reply is spoken by an iOS voice for the target language ([ADR-0007](0007-pocket-tts-english-only-system-voice-for-replies.md)).

## Sources

- Design spec [§2 Non-goals](../superpowers/specs/2026-09-02-revox-mobile-design.md#non-goals-v1) ("Whisper translates only *to* English"), [§12](../superpowers/specs/2026-09-02-revox-mobile-design.md#12-platform-limitations-to-document-and-the-ios-27-seams).
- [`project.yml`](../../project.yml) (the `Translation.framework` dependency with `weak: true` and its comment); [`ReVoxMobile/Translation/TwoWayTranslation.swift`](../../ReVoxMobile/Translation/TwoWayTranslation.swift).
- README, "Two-way conversation" and "Platform limitations" item 6.
