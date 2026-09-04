# Milestone 5 on-device measurements

The design spec marks the M5 behaviours below ASSUMED (§10.4, §13 Q8–Q11). One row per item: procedure, evidence, pass criterion, result. Results are filled on an iPhone (iPhone 12 or newer, iOS 17+) from a TestFlight build or a Debug build; log lines come from Console.app (subsystems `revox` and `revox.broadcast`) or `log stream --predicate 'subsystem BEGINSWITH "revox"'`. A row that could not be measured stays `pending` with the reason and is listed in the PR body.

Devices used: `pending` (model, iOS version per device).

| # | ASSUMED item (spec) | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 1 | 30-minute background keep-alive, microphone mode (§6.8, §13 Q8) | Live → Microphone → Start; lock the phone; every 5 min play a Spanish sentence from a second device near the mic; after 30 min unlock | Settings → Diagnostics: "Gaps > 3 s", keep-alive log `Library/Application Support/ReVox/keepalive.log`; the transcript; `session` log lines | (1) zero gaps > 3 s; (2) all 6 probes transcribed; (3) "Engine running: yes" on return; (4) every `interruption began reason=…` line logged | pending |
| 2 | 30-minute background keep-alive, broadcast mode (§6.8, §13 Q8) | Task 60 spike: Settings → Diagnostics → "Hold broadcast session" on; start a broadcast (picker or Control Center) for ReVox; play a video in another app; lock the phone; every 5 min play a Spanish sentence in that app; after 30 min unlock | Diagnostics: "Gaps > 3 s", "Rate" ≈ 16000 frames/s while audio plays, "Level" reacting to the probes; `keepalive.log` | (1) zero gaps; (2) the ring level reflected all 6 probes (transcription of the probes is row 2b, re-run with the real extension in Task 68); (3) engine running on return; (4) interruption reasons logged | pending |
| 2b | Same as 2 with the real extension and `BroadcastCapture` (Task 68) | Live → Other apps → Start → broadcast; lock; 6 probes | the transcript | all 6 probes transcribed, zero gaps | pending |
| 3 | Keep-alive in Low Power Mode and on A2DP (§6.8) | Repeat rows 1 and 2 with Low Power Mode on; repeat with AirPods connected | same evidence | same criteria | pending |
| 4 | `.audioApp` ASBD on iOS 17/18/26 (§7.2, §13 Q9) | Start a broadcast, play a video | `revox.broadcast` log: `audioApp ASBD sampleRate=… flags=… channels=… bits=… framesPerBuffer=…` (once per broadcast) | recorded here per iOS version; expected 44100 Hz, SInt16, big-endian, 1–2 ch, 1024 frames | pending |
| 5 | `AVAudioConverter` accepts the big-endian flag (§7.2) | Task 63 build; `BroadcastConversionTests` print `MEASUREMENT bigEndian converterAccepted=…`; on device the `converter built swap=…` log line | test output, log line | recorded (either outcome is handled) | **simulator: answered, and made moot for shipping.** `BroadcastConversionTests` pass on CI run 33875559463 (Xcode 26.6, iOS simulator) with `usesByteSwap == true` asserted for big-endian input: the converter takes the deterministic swap branch unconditionally for 16-bit big-endian, and the amplitude, RMS and zero-crossing rate of a 1 kHz tone through 44.1 kHz big-endian stereo are asserted sample-by-sample. `converterAcceptedBigEndian` still records what `AVAudioConverter.init` said, printed as `MEASUREMENT bigEndian converterAccepted=… byteSwap=…` in the xcodebuild log. Device: pending — but the decode path no longer depends on the answer. |
| 6 | ReVox's own voice is re-captured; ducked or un-ducked level (§5.2, §13 Q9) | Task 68: play Music, Live → Other apps → Start, let ReVox speak; read `selfcapture` log lines with ducking on and off | `selfcapture edge=… lastVoiceEnd=… tailFrames=… peakWhileSpeaking=… peakAfterEdge=…` | re-capture present/absent recorded; the peak level with ducking on vs off recorded | pending |
| 7 | `captureLatencyFrames` for broadcast mode (§5.2, §10.4) | Task 68: 20 phrases; median of `tailFrames` | the 20 `selfcapture` lines | value ≥ 0 recorded and folded into `BroadcastTuning.captureLatencyFrames` | pending |
| 8 | Extension resident footprint with the mapping (§7, §13 Q10) | 10-minute broadcast | `revox.broadcast` log: `footprint residentMB=…` every ~30 s (Task 63) | ≤ 15 MB throughout; never near 50 MB | pending |
| 9 | Broadcast survives auto-lock (§13 Q10) | Set Auto-Lock to 30 s; start a broadcast; wait 2 min without touching the phone | Diagnostics "State" stays running; `broadcast.state` record | survives (or the outcome recorded and shown in the Live footnote) | pending |
| 10 | Atomics shim builds under `APPLICATION_EXTENSION_API_ONLY` (§6.2) | Task 57 CI run | the extension target compiled `RingAtomics.c` | compiles | measured: compiles (Task 57 CI run) |
| 11 | `MAP_SHARED` pages are not charged to the extension's jetsam footprint (§6.2) | Compare row 8 with and without the app running (the app maps the same file) | `footprint` lines | the extension's resident size does not grow by the 3.7 MB mapping when the app also maps it | pending |
| 12 | Cross-process `UserDefaults(suiteName:)` reads are fresh right after a Darwin wake (§6.2, §13 Q11) | Start and stop a broadcast 10 times while the app is in the foreground | `capture` log: `wake=stopped record.state=finished` vs `record.state=running` (Task 64 logs the record state at every wake) | the record read at the `stopped` wake shows `finished` in 10 of 10 cases; otherwise the timer fallback re-reads within 100 ms and the count of stale reads is recorded | pending |
| 13 | Lock-induced broadcast end heuristic (`protectedDataWillBecomeUnavailableNotification` within 5 s of `stopped`) — only if wanted (§6.2) | Decide after row 9; if the side button ends broadcasts on every test device, the static footnote suffices | — | decision recorded | pending |
| 14 | `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:)` spelling (API §2) | not used: the extension copies with `CMSampleBufferCopyPCMDataIntoAudioBufferList` into a preallocated buffer | — | not applicable | not applicable |

## How to fill a row

1. Run the procedure; paste the relevant log lines under `Raw logs`.
2. Write `measured: …` in `Result` with the numbers, or `pending` with the reason.
3. Commit on the milestone branch; the PR body links this file.

## Raw logs

(paste trimmed Console excerpts here, one heading per row)

### Procedures for rows 8, 9, 11 and 12 (final build)

- **Row 8 (extension footprint):** start a broadcast, play a video for 10 minutes; in Console filter subsystem `revox.broadcast`; copy every `footprint residentMB=…` line (one per ~30 s). Pass: every value ≤ 15 MB.
- **Row 11 (MAP_SHARED accounting):** repeat row 8 twice — once with ReVox in the foreground on the Live tab (the app maps the ring), once with ReVox force-quit — and compare the `residentMB` values; the mapping (3.7 MB) must not appear as extension memory in the first run.
- **Row 9 (auto-lock):** Settings → Display & Brightness → Auto-Lock 30 seconds; start a broadcast; do not touch the phone for 2 minutes; unlock; Diagnostics "State" must still be `running` and the `broadcast.state` record `running`.
- **Row 12 (record freshness after a wake):** with ReVox on the Live tab in Other apps mode and not running, start and stop a broadcast from Control Center ten times, waiting 5 s between actions; in Console filter subsystem `revox` category `capture`; for every `wake=stopped` line the same line must show `record.state=finished` (or `failed`), and for every `wake=started` line `record.state=running`. Count stale reads.

