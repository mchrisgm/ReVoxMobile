# ADR-0005: The broadcast extension forwards audio through an App Group ring and nothing else

## Status

Accepted

## Date

Rulings R10 and C4 in the design spec of 2026-09-02; recorded 2026-09-04.

## Context

The only way for an iOS app to hear other apps' audio is a ReplayKit Broadcast Upload Extension, which runs in its own process under a **50 MB memory cap** and is started and stopped by the user (the picker in ReVox, or Control Center's Screen Recording control). A Whisper model alone is hundreds of megabytes; nothing that runs a model can live in the extension. The extension must also survive the app being closed — a broadcast started from Control Center while ReVox is not running has nowhere to send audio.

## Decision

`ReVoxBroadcast` is a thin forwarder: it reads the `.audioApp` sample buffers' format at runtime, converts them with one `AVAudioConverter` to 16 kHz mono Float32, and `memcpy`s the samples into a memory-mapped ring file (`audio-ring-v1.bin`, magic `RVXRING1`) in the shared App Group container: a 4 096-byte header plus 60 s of audio, **3 844 096 bytes** in total. Cursors are 64-bit and accessed with acquire/release atomics; the writer stores data, then the cursor, then a heartbeat. It posts payload-free Darwin notifications and writes a `UserDefaults(suiteName:)` state record only at transitions. The app maps the same file, attaches with a decision table (live / stale / idle / no ring), reads in 512-multiples and jumps forward when lapped. Every model runs in the app.

Everything the extension may **not** do is a CI gate (`scripts/ci/check-extension-surface.sh`): no CoreML, WhisperKit, FluidAudio, `AVAudioEngine`, `AVAudioSession`, network, keychain, Swift concurrency, dispatch queues, per-buffer allocation or logging, host-time APIs, shrinking the ring file, or `finishBroadcastWithError` for anything but a real failure. Its entitlements carry the App Group and nothing else. `docs/broadcast-bridge.md` is the contract, and `scripts/ci/check-broadcast-bridge-doc.py` fails CI if its header table disagrees with `RingHeader.Offset` in `ReVoxCore`.

## Consequences

- The extension's footprint is the 3.7 MB mapping plus under 1 MB of preallocated buffers plus the runtime; the target is ≤ 15 MB resident, measured in M5 (`pending device measurement`).
- A Control Center broadcast started while ReVox is closed is buffered for at most 60 s; opening ReVox later joins it "in progress".
- The ring's data region is zeroed at every start and finish, so a broadcast's audio does not outlive it; the ring file is created with `completeUntilFirstUserAuthentication` and excluded from backup.
- Positions are absolute frame counts on the writer's timeline, which is what lets the self-capture gate compare capture time with capture time without any host-time API (and keeps the SystemBootTime reasons out of both privacy manifests).
- iOS 27 deprecates the ReplayKit broadcast API; the replacement (ScreenCaptureKit) would sit behind the same `AudioSource` protocol.

## Sources

- Design spec [§7 ReVoxBroadcast extension design](../superpowers/specs/2026-09-02-revox-mobile-design.md#7-revoxbroadcast-extension-design), §5.9, [§11 Security and privacy](../superpowers/specs/2026-09-02-revox-mobile-design.md#11-security-and-privacy), [§12](../superpowers/specs/2026-09-02-revox-mobile-design.md#12-platform-limitations-to-document-and-the-ios-27-seams) item 3.
- [`docs/broadcast-bridge.md`](../broadcast-bridge.md); [`scripts/ci/check-extension-surface.sh`](../../scripts/ci/check-extension-surface.sh); [`scripts/ci/check-broadcast-bridge-doc.py`](../../scripts/ci/check-broadcast-bridge-doc.py); [`docs/measurements/m5-broadcast-capture.md`](../measurements/m5-broadcast-capture.md).
