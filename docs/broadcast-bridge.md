# ReVox broadcast bridge

This document describes how the `ReVoxBroadcast` extension hands other apps' audio to the app (design spec §5.9, §6.2, §7, R10). Task 69 completes the format description; this first version records the background keep-alive configuration from the milestone 5 spike (§6.8, C2).

## Background keep-alive configuration (spike result)

Requirement C2: translation must continue when the screen locks or the user switches to the app being translated. iOS keeps the app running through `UIBackgroundModes = [audio]` together with an active **mixable** audio session and a running `AVAudioEngine` with a live output. Apple documents no "must be non-silent" rule; the 30-minute locked-screen test of `docs/measurements/m5-broadcast-capture.md` rows 1–3 is the only proof.

Configuration under test (applied in the foreground before `pipeline.start`, `AudioSessionController.configure(for:)`):

| Mode | Category | Mode | Resident options | Engine |
|---|---|---|---|---|
| microphone | `.playAndRecord` | `.default` | `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]` | one `AVAudioEngine`, `isAutoShutdownEnabled = false`, input tap + player node, never stopped while a session runs (except inside a ducking cycle, §6.8) |
| broadcast | `.playback` | `.default` | `[.mixWithOthers]` | one `AVAudioEngine`, `isAutoShutdownEnabled = false`, player node only |

Pass criteria (§6.8): (1) zero keep-alive heartbeat gaps > 3 s in 30 minutes (`KeepAliveMonitor`, Settings → Diagnostics); (2) every 5-minute probe transcribed; (3) `engine.isRunning == true` on return to the foreground; (4) every `interruptionNotification` `.began` logged with its reason.

Escalation ladder, in cost order: (1) the engine-only keep-alive above — no cost; (2) a looping silent buffer on a second player node (`keepAliveNode`) — only if (1) fails, with an App Review note in `docs/release.md` (Guideline 2.5.4: the background audio *is* the translated speech; the silent buffer only bridges the gaps between phrases); (3) a mic tap under `.playAndRecord` in broadcast mode — **not permitted under R8** and contradicting §11; if (1) and (2) both fail, stop and request a re-ruling of R8 before implementing anything.

**Result:** `pending` — filled from rows 1–3 of `docs/measurements/m5-broadcast-capture.md`: the ladder step that passed, the devices and iOS versions, Low Power Mode and A2DP outcomes.
