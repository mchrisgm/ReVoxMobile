# ADR-0004: Ducking is applied and released through the audio session's options

## Status

Accepted (the per-edge mechanism is confirmed by device measurement, still `pending`)

## Date

Ruling R8 in the design spec of 2026-09-02; the README wording of 2026-09-04; recorded 2026-09-04.

## Context

The Windows app lowers the *other* application's volume to a user-chosen level while the English voice plays. iOS cannot set another app's volume at all. The only tool it offers is the `AVAudioSession` option `.duckOthers`, and iOS chooses the amount and the ramp. ReVox's session is *mixable* (`.mixWithOthers`) so that it can run in the background and so that other apps keep playing; the engine must keep running through a phrase, because a paused engine captures no microphone audio and interrupts the running-engine keep-alive that background operation depends on. Apple's documented ducking behaviour begins at session activation and ends at deactivation, but `setActive(false)` with a rendering engine returns `.isBusy`.

## Decision

Ducking is a **toggle plus a voice-volume slider**, not a ducked-level slider. `duck()` on the speaking-true edge re-applies the resident category and mode with `.duckOthers` added to the options on the active session; `restore()` after the `DuckingCoordinator`'s ~250 ms hold removes `.duckOthers` the same way. Because the session mixes with others rather than interrupting them, dropping the option is what ends the duck. The session is never deactivated for ducking, and `.duckOthers` is never left resident while ReVox is silent.

The deactivation-cycle fallback (pause the engine, `setActive(false, options: .notifyOthersOnDeactivation)`, re-apply the mask, `setActive(true)`, restart the engine) stays in the code behind one constant in `AudioSessionController` in case a future iOS needs it; the mid-cycle reconciliation rule (`pendingDuck` / `appliedDuck`) guarantees that a duck or restore arriving during a cycle is honoured before the cycle ends.

## Alternatives considered

- **A ducked-level slider like Windows**: impossible; iOS has no API to set another app's volume (spec deviation W6).
- **Deactivating the session on every edge**: pauses the engine, so mic mode loses audio after every phrase and the background keep-alive is interrupted; kept only as the fallback above.
- **`.interruptSpokenAudioAndMixWithOthers` or `setMode`**: ruled out in §6.8 ("never").

## Consequences

- The Settings help text and the README explain that iOS decides the amount; the Voice volume slider adjusts ReVox's own voice only.
- Whether the options-only edge ducks a live session, how fast the other app returns, and the mic gap per edge are the M4 rows 1–10 of the measurement record and remain `pending device measurement`.
- Both modes duck "everything else"; broadcast mode adds `.duckOthers` to a `.playback` / `[.mixWithOthers]` session for the duration of a phrase only.

## Sources

- Design spec [§6.8 AudioSessionController](../superpowers/specs/2026-09-02-revox-mobile-design.md#68-audiosessioncontroller-ducker-session-and-engine-owner--api-8-r8), [§12 Platform limitations](../superpowers/specs/2026-09-02-revox-mobile-design.md#12-platform-limitations-to-document-and-the-ios-27-seams) item 1, §2 deviations W5 and W6.
- README, "Platform limitations" item 1; [`docs/measurements/m4-pocket-tts-ducking.md`](../measurements/m4-pocket-tts-ducking.md); [`docs/broadcast-bridge.md`](../broadcast-bridge.md) §10.
