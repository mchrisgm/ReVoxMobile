# ReVox broadcast bridge ("RVXRING1")

How the `ReVoxBroadcast` Broadcast Upload Extension hands other apps' audio to the ReVox app (design spec §5.9, §6.2, §7, R10, A5). Everything that crosses the process boundary is listed here; nothing else is shared. `scripts/ci/check-broadcast-bridge-doc.py` fails CI if the header table below disagrees with `RingHeader.Offset` in `ReVoxCore/Sources/ReVoxCore/RingBridge.swift`.

## 1. Overview

```
 other app ─► ReplayKit (replayd) ─► ReVoxBroadcast (extension)           ReVoxMobile (app)
                 .audioApp CMSampleBuffer     │                                    │
                                              ├─ BroadcastConverter ─► 16 kHz mono Float32
                                              ├─ RingWriter ─► audio-ring-v1.bin ◄─ RingReader ◄─ BroadcastCapture ─► pipeline
                                              ├─ UserDefaults(suiteName:) "broadcast.state" ◄─ read; "capture.reader" ◄─ written by the app
                                              └─ Darwin notifications ─► DarwinNotificationObserver
```

The extension is a thin forwarder (≤ 15 MB resident target, 50 MB hard cap): format detection, one `AVAudioConverter`, `memcpy` into the ring, Darwin posts, a state record. Every model runs in the app. The extension never depends on the app being alive: if the app is absent the ring simply wraps (a Control Center broadcast started while ReVox is closed is buffered for at most 60 s).

## 2. The ring file

| Property | Value |
|---|---|
| Location | `<App Group container>/Library/Application Support/ReVox/audio-ring-v1.bin` (`RingFileMapping.ringURL(in:)`) |
| App Group | `group.<REVOX_BUNDLE_PREFIX>.revox`, read from `REVOXAppGroup` in both Info.plists |
| Size | 4 096-byte header + 960 000 frames × 4 bytes = 3 840 000 bytes of data = **3 844 096** bytes |
| Contents | 60 s ring of mono 16 kHz Float32 little-endian samples (`RingLayout.v1`: magic `RVXRING1`, headerBytes 4 096, capacityFrames 960 000, sampleRate 16 000) |
| Created by | the extension only (`RingFileMapping.openCreating`), with `FileProtectionType.completeUntilFirstUserAuthentication` (Apple's documented default, the only class a process can open after a later lock) and `isExcludedFromBackup = true` |
| Grown by | the extension only, with `FileHandle.truncate(atOffset:)` upward; never shrunk; a layout change gets a new file name (`audio-ring-v2.bin`), never a resize |
| Mapped by | both processes with `mmap(nil, 3 844 096, PROT_READ \| PROT_WRITE, MAP_SHARED, fd, 0)`; the app opens with `RingFileMapping.openExisting` and never creates, truncates or grows the file (absent or short → `AttachState.noRing`) |
| Zeroed | the data region, by the extension, on every `broadcastStarted` **and** on `broadcastFinished` and on its own failures — a broadcast's audio does not outlive it (design spec §11, `docs/security-review-m5.md` finding 4) |
| Cursors | 64-bit, accessed only through `RingStorage.loadCursor` / `storeCursor`: `RingAtomics.c` (`atomic_load_explicit(memory_order_acquire)` / `atomic_store_explicit(memory_order_release)`) in both processes, an `NSLock` in the test `HeapRingStorage` |

## 3. Header layout

All fields little-endian; 8-byte fields 8-byte aligned; the header is one 4 096-byte page. Writer column: ext = extension, app = app.

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
| 172 | 3924 | | `reserved` | | zero |
| 4096 | 3 840 000 | Float32 × 960 000 | data region | ext | 60 s ring of mono 16 kHz samples |

## 4. Ordering rules

- **Writer** (`RingWriter.write`, one ReplayKit thread): copy the frames at `writeCursor % capacityFrames` (split at the wrap), then store `writeCursor` (release), then `lastWriteAt` and the level meter.
- **Reader** (`RingReader.read`, one capture task): load `writeCursor` (acquire); if `writeCursor − readCursor > capacityFrames − guardFrames (16 000)` the reader has been lapped → `.gap`; otherwise copy `[readCursor, writeCursor)` in 512-multiples (at most 16 000 frames per call), re-load `writeCursor`, and if the writer lapped the reader during the copy discard it (`overrunCount` += 1, `.gap`); on a gap jump to `writeCursor − catchUpFrames (32 000)`.
- Aligned 64-bit loads and stores are single-copy atomic on arm64, so a cursor is never torn; acquire/release ordering guarantees that a cursor value is never observed before the frames it covers are visible.
- Positions are absolute frame counts on the writer's timeline. The app stamps every chunk with the ring position of its last sample and every player speaking edge with the `writeCursor` at that moment, so the self-capture gate compares capture time with capture time (§5).

## 5. Attach decision table (`RingReader.attach(now:storedReadCursor:storedGeneration:)`)

| Condition | Result |
|---|---|
| file absent, short, bad magic or header not yet written | `.noRing` |
| `state == running` and `now − lastWriteAt ≤ 3 s` and generation matches the stored `capture.reader` record (or no record) | `.attachedLive(generation)`; `readCursor = max(stored cursor for this generation, writeCursor − 32 000)` |
| `state == running` and heartbeat older than 3 s | `.stale(lastWriteAt)`; nothing is read; the app writes `state = lost` into `broadcast.state` |
| `state ∈ {idle, paused, finished, failed}` | `.idle` |
| header generation ≠ stored generation | the header is trusted, the stored cursor is reset, then re-evaluated |

The app polls the ring on every Darwin wake and on a 100 ms timer; missed notifications only add latency. "Joined in progress" (session flag, Live header row) means the attach happened more than 32 000 frames behind the writer.

## 6. Darwin notifications (no payload, system-wide)

Posted with `CFNotificationCenterPostNotification(center, name, nil, nil, true)`; observed with `CFNotificationCenterAddObserver(…, .deliverImmediately)` on the main run loop. Names are derived from the App Group id:

| Name | Direction | When |
|---|---|---|
| `<appGroup>.broadcast.started` | ext → app | after `RingWriter.begin` and the record write |
| `<appGroup>.broadcast.paused` / `.resumed` | ext → app | `broadcastPaused` / `broadcastResumed` |
| `<appGroup>.broadcast.stopped` | ext → app | `broadcastFinished` and the extension's own failures |
| `<appGroup>.broadcast.formatChanged` | ext → app | every source-format change (including the first format) |
| `<appGroup>.broadcast.audio` | ext → app | at most every 1 600 written frames (≤ 10/s) |
| `<appGroup>.app.attached` | app → ext | diagnostics only; the extension does not observe it |

A notification is a hint, never a fact: the app re-reads the header and the record on every wake. The names derive from the App Group id, which ships in the Info.plist, and Darwin notifications are system-wide and unauthenticated, so any app on the device can post them. A foreign post cannot start the pipeline (that needs a real `running` header with a fresh heartbeat) and carries nothing into the app, but each one used to cost a property-list decode and — on `started`/`stopped` — an `mmap` of the whole ring on the main actor. Since `docs/security-review-m5.md` finding 6 the observer streams keep only the newest name, wake-driven polls are coalesced to one per 10 ms (the 100 ms timer is not), and the coordinator holds one mapping for its lifetime instead of one per probe.

## 7. UserDefaults records (`UserDefaults(suiteName: appGroup)`, privacy reason 1C8F.1 in both manifests)

`"broadcast.state"` — written by the extension only at transitions (started, annotation, format change, first mic buffer, paused, resumed, finished, failed) and once by the app with `state = lost` when the heartbeat went stale:

| Key | Type | Meaning |
|---|---|---|
| `contractVersion` | Int | 1 |
| `ringFile` | String | `audio-ring-v1.bin` |
| `generation` | UInt64 | mirrors the header |
| `state` | String | `running`, `paused`, `finished`, `failed`, `lost` |
| `startedAt`, `finishedAt` | Double | Unix time |
| `finishReason` | String? | **only** the extension's own error text when it called `finishBroadcastWithError` (e.g. "ReVox could not open its shared audio buffer"); nil for every system- or user-ended broadcast — the app never learns why a broadcast ended |
| `writerPID` | Int32 | |
| `sourceASBD` | dictionary | `sampleRate`, `formatID`, `formatFlags`, `bytesPerPacket`, `framesPerPacket`, `bytesPerFrame`, `channelsPerFrame`, `bitsPerChannel` |
| `asbdChangeCount` | Int | |
| `annotatedBundleID` | String? | `RPApplicationInfoBundleIdentifierKey` from `broadcastAnnotated` (diagnostic; shown on the Diagnostics screen, never logged). Cleared by `finished()` and `failed()`: it names the app whose content the user was consuming, and this plist — unlike the ring file — is not excluded from backup |
| `micToggleSeen` | Bool | a `.audioMic` buffer was received (the buffers themselves are ignored) |

`"capture.reader"` — written by the app on attach, on every gap and at most once per second while reading: `lastAttachedAt` (Double), `lastReadCursor` (UInt64), `generation` (UInt64).

## 8. Extension flow (`ReVoxBroadcast/SampleHandler.swift`, design spec §7)

1. `broadcastStarted`: read `REVOXAppGroup`; map or grow the ring; `generation = max(header, record) + 1`; zero the data region; `RingWriter.begin`; write `broadcast.state` (`running`); post `started`.
2. `broadcastAnnotated`: store the bundle id in the record.
3. `processSampleBuffer`: `.video` → return; `.audioMic` → count; `.audioApp` → `BroadcastConverter.convert` inside `autoreleasepool` (runtime ASBD, rebuild on change, big-endian byte swap when `AVAudioConverter` refuses the flag, preallocated 45 192-frame input and 90 448-frame output buffers, once-`.haveData`-then-`.noDataNow` until `.inputRanDry`) → `RingWriter.write` → `.audio` every 1 600 frames. The first ASBD is logged at `.info`, later changes at `.error`; a resident-footprint line every ~30 s.
4. `broadcastPaused` / `broadcastResumed`: header state + record + notification; `converter.reset()` on resume.
5. `broadcastFinished`: state `finished`, record with `finishedAt` and `annotatedBundleID` cleared, post `stopped`, zero the data region, `munmap`, close. Never truncate.
6. `finishBroadcastWithError` only for real failures (App Group missing, container missing, ring mapping failed), with an `NSError` in domain `REVOXBroadcastErrorDomain` whose `localizedDescription` iOS shows to the user; the record gets `failed` + `finishReason`.

Never in the extension (`scripts/ci/check-extension-surface.sh`): CoreML, WhisperKit, FluidAudio, `AVAudioEngine`, `AVAudioSession`, network, keychain, models, VAD, per-buffer allocation or logging, Swift concurrency, dispatch queues, host-time APIs, shrinking the ring file, `finishBroadcastWithError` for non-failures, reliance on the app being alive. Entitlements: the App Group only (no increased-memory-limit). Privacy manifest: UserDefaults `1C8F.1`, FileTimestamp `C617.1`.

## 9. Self-capture suppression (design spec §5.2, R9)

The broadcast also hears ReVox's own English voice. The core `CaptureGate` drops chunks from the player's speaking-true edge until `p₀ + 4 800 + captureLatencyFrames`, where `p₀` is the ring `writeCursor` stamped on the speaking-false edge; chunks are keyed on their ring positions, so no host-time API is needed. `BroadcastTuning.captureLatencyFrames` (`ReVoxMobile/Capture/BroadcastTuning.swift`) absorbs the delay between "the player finished" and "the extension wrote the last sample of ReVox's voice"; it is measured with `SelfCaptureProbe` (the `selfcapture` log lines: `tailFrames` per phrase) and recorded in `docs/measurements/m5-broadcast-capture.md` rows 6–7. Current value: see `BroadcastTuning.captureLatencyFrames` (0 = not yet measured on this branch).

## 10. Ducking in broadcast mode

Both modes duck "everything else" through the session controller (design spec §6.8, W6); the on-edge / off-edge mechanism and its measured outcome are recorded in `docs/measurements/m4-pocket-tts-ducking.md`. Broadcast mode uses the `.playback` / `.default` / `[.mixWithOthers]` session; a duck adds `.duckOthers` for the duration of a phrase only.

## 11. Background keep-alive configuration (spike result)

Requirement C2: translation must continue when the screen locks or the user switches to the app being translated. iOS keeps the app running through `UIBackgroundModes = [audio]` together with an active **mixable** audio session and a running `AVAudioEngine` with a live output. Apple documents no "must be non-silent" rule; the 30-minute locked-screen test of `docs/measurements/m5-broadcast-capture.md` rows 1–3 is the only proof.

Configuration under test (applied in the foreground before `pipeline.start`, `AudioSessionController.configure(for:)`):

| Mode | Category | Mode | Resident options | Engine |
|---|---|---|---|---|
| microphone | `.playAndRecord` | `.default` | `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]` | one `AVAudioEngine`, `isAutoShutdownEnabled = false`, input tap + player node, never stopped while a session runs (except inside a ducking cycle, §6.8) |
| broadcast | `.playback` | `.default` | `[.mixWithOthers]` | one `AVAudioEngine`, `isAutoShutdownEnabled = false`, player node only |

Pass criteria (§6.8): (1) zero keep-alive heartbeat gaps > 3 s in 30 minutes (`KeepAliveMonitor`, Settings → Diagnostics); (2) every 5-minute probe transcribed; (3) `engine.isRunning == true` on return to the foreground; (4) every `interruptionNotification` `.began` logged with its reason.

Escalation ladder, in cost order: (1) the engine-only keep-alive above — no cost; (2) a looping silent buffer on a second player node (`keepAliveNode`) — only if (1) fails, with an App Review note in `docs/release.md` (Guideline 2.5.4: the background audio *is* the translated speech; the silent buffer only bridges the gaps between phrases); (3) a mic tap under `.playAndRecord` in broadcast mode — **not permitted under R8** and contradicting §11; if (1) and (2) both fail, stop and request a re-ruling of R8 before implementing anything.

**Result:** `pending` — filled from rows 1–3 of `docs/measurements/m5-broadcast-capture.md`: the ladder step that passed, the devices and iOS versions, Low Power Mode and A2DP outcomes.

## 12. Platform limitations that follow from this design

- The user must start the broadcast (the picker on the Live screen or Control Center's Screen Recording control); ReVox cannot start or stop it programmatically; pressing the side button ends it.
- Some players (AVPlayer-based apps, Safari, Music) deliver silence to broadcasts; the Live screen says "No audio from the app (some players are not captured)" after 10 s below −60 dBFS.
- A broadcast started while ReVox is closed is buffered for 60 s; opening ReVox afterwards joins it "in progress".
- iOS 27 deprecates the ReplayKit broadcast API; the replacement (ScreenCaptureKit, `excludesCurrentProcessAudio = true`) would sit behind the same `AudioSource` protocol and make the self-capture gate unnecessary in that mode (design spec §12).
