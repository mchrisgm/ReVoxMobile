# Milestone 4 on-device measurements: pocket-tts and ducking

The design spec marks the ducking mechanism per edge, the memory entitlement and the pocket-tts numbers ASSUMED (§5.6, §6.7, §6.8, §10.4, §13 Q5–Q7). This file is the record, in the layout of `m3-microphone-mode.md`: one row per item, the procedure, the evidence, the pass criterion and the result. Results are filled on an iPhone (iPhone 12 or newer, iOS 17+) with the TestFlight build of this milestone or a Debug build from Xcode; log lines are read in Console.app (subsystem `revox`, categories `ducking`, `measurements`, `session`) or with `log stream --predicate 'subsystem == "revox"'`. A row that could not be measured stays `pending` with the reason and is listed in the PR body.

Devices used: `pending` (model, iOS version, RAM from the `device` log line; at least one 4 GB device for rows 11 and 12).

Setup for the ducking rows: Music (or any player) at a fixed volume on the same iPhone, ReVox on Live in microphone mode, Settings → Ducking on, Voice volume 1.0, a foreign-language phrase ready to speak. "Level drop" is observed by ear and, where a second iPhone is available, by recording the room with Voice Memos on that second device.

## Ducking (§6.8, §13 Q5)

| # | ASSUMED item | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 1 | **A-on**: the options-only "on" mask ducks a live session at all (R8's prescribed on-edge) | TestFlight build (defaults `defaultOnEdge = .optionsOnly`, `defaultOffEdge = .deactivationCycle`). Start, speak one phrase, listen for Music to drop when ReVox starts speaking. Repeat 5 times. | `ducking`: `on-edge options-only applied duck=true`, `session categoryOptions=… duckOthers=true`, `cycle done edge=on … ms=` | Music drops within ~300 ms of the first clip in 5 of 5 phrases | pending |
| 2 | **B-on** (only if row 1 fails): the full-cycle on-edge ducks, and its first-clip start latency | Debug build with `AudioSessionController.defaultOnEdge = .fullCycle`. Same procedure. | `cycle done edge=on onEdge=fullCycle … ms=` (the held first clip starts after this cycle) | ducks in 5 of 5; `ms` < 150 (ASSUMED target) | pending |
| 3 | **A-off**: the options-only "off" mask un-ducks without a deactivation and without a configuration-change notification | Debug build with `defaultOffEdge = .optionsOnly`. Speak, wait for the hold, listen for Music to return. Watch for `routeChanged` events. | `off-edge options-only applied duck=false`, `session … duckOthers=false`; `session` category: no `route change` with reason `.categoryChange` beyond the one per `setCategory`; no `AVAudioEngineConfigurationChange` | Music returns to full within 500 ms of the hold in 5 of 5; the engine never stops (`engineRunning=true`) | pending |
| 4 | **B-off** (default): the deactivation cycle un-ducks; ramp time; mic gap per cycle | TestFlight build. Speak 10 phrases; note when Music returns; read the cycle time. | `cycle done edge=off offEdge=deactivationCycle … engineRunning=true ms=` | Music returns after every phrase; `ms` (the mic gap upper bound, the tap stops with the paused engine) < 150 in 9 of 10 (ASSUMED target) | pending |
| 5 | Background survival across ≥ 100 consecutive off-edge cycles with the screen locked | Lock the phone, keep speaking short phrases for 20 minutes (a looping foreign-language recording on a second device works). | count of `cycle done edge=off` lines; no `pausedByIOS` in `session`; the transcript has no "paused by iOS" marker | ≥ 100 cycles, last line `engineRunning=true`, no interruption `.began` without a cause | pending |
| 6 | No lost `.dataPlayedBack` completions: clips scheduled while the engine is paused are held and play after `engine.start()` | During row 5, count spoken phrases vs transcript entries. | transcript entries vs phrases heard; `ducking` lines | every entry was spoken; no phrase stuck (speaking pill never stays on) | pending |
| 7 | Mid-cycle: a second phrase scheduled while the off-edge cycle runs plays ducked | Speak two short phrases with a ~0.5 s gap so the second clip arrives during the first phrase's restore cycle. Repeat 5 times. | `cycle done … ducked=true extraPasses=…` for the reconciliation; Music stays ducked through the second phrase | second phrase ducked in 5 of 5; `extraPasses` grows by at most 1 per occurrence | pending |
| 8 | Mute issued mid-cycle leaves the other app un-ducked and no `.duckOthers` resident | While a phrase plays, tap Mute; then tap Mute during a restore cycle (right after a phrase ends). Repeat 5 times each. | last `session … duckOthers=false` after the last `cycle done`; Music at full level | 10 of 10: Music back at full within 500 ms, last mask without `.duckOthers`, `ducked=false` | pending |
| 9 | Routes and versions: speaker, wired headphones, A2DP, HFP; ReVox in the background; iOS 17, 18 and 26 | Rows 1 and 4 (or 2 and 3 if adopted) on each route and OS available. | per-route note | ducks and un-ducks on every route; HFP: no route loss (`routeChanged` reason logged) | pending |
| 10 | Ducking cycle failures and the never-inactive invariant (§6.8) | Grep the `ducking` log of rows 1–9 for `ducking cycle failed`. | `ducking cycle failed: …` and the following `session recovery` lines | zero failures, or every failure followed by a recovery that ends `engineRunning=true` | pending |

**Decision table (§6.8), filled from rows 1–4:**

| Outcome | Decision | Code change | Ruling |
|---|---|---|---|
| A-on ducks (row 1 passes) and A-off does **not** un-duck (row 3 fails) | keep the hybrid: A-on + B-off | none (the defaults) | request the R8 amendment for the off-edge engine pause (the acknowledged deviation) |
| A-on does not duck (row 1 fails), B-on ducks (row 2 passes) | B-on + B-off | `defaultOnEdge = .fullCycle` | request the R8 amendment for both edges (engine pause on both edges, full cycle instead of the options-only "add `.duckOthers`") |
| A-off un-ducks without a configuration change (row 3 passes) | A on both edges, B the fallback | `defaultOffEdge = .optionsOnly` (and `defaultOnEdge` per row 1/2) | R8 stands as written for the on-edge; note that the deactivation with `.notifyOthersOnDeactivation` is now the fallback only |
| neither A-on nor B-on ducks | stop; F12 has no working mechanism on this iOS version | none | request a re-ruling of R8 with the log excerpts |

Decision taken: **A on both edges** (`defaultOnEdge = .optionsOnly`, `defaultOffEdge = .optionsOnly`), on device
evidence rather than on rows 1–4, which are still `pending`.

The owner reported on build 13 that microphone audio was sometimes not picked up, having reported the microphone
working on build 10 — the last build with ducking off. The deactivation off-edge pauses the engine after every
phrase and a paused engine's input tap delivers nothing, so every phrase was followed by a guaranteed capture gap
on top of `CaptureGate`'s 300 ms self-capture hold. That gap is not a price worth paying: the resident mask
carries `.mixWithOthers`, so other apps are never interrupted, only ducked, and `notifyOthersOnDeactivation`
exists to release apps that *were* interrupted. Dropping `.duckOthers` is what ends the duck.

Row 3 is therefore no longer a candidate check but a **confirmation of the shipped behaviour**: if Music does not
return to full within 500 ms after ReVox stops speaking, flip `defaultOffEdge` back to `.deactivationCycle` (it is
still implemented and covered by `AudioSessionMaskTests`) and record the mic gap of row 4 as the accepted cost.

Row 19 is answered: TestFlight run 33856483961 archived, exported and uploaded build 13 with the
increased-memory-limit entitlement attached by cloud signing, with no ITMS warning naming it.

## pocket-tts and memory (§5.6, §6.5, §6.7, §11, §13 Q6–Q7)

| # | ASSUMED item | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 11 | Resident memory with pocket-tts `.ane` loaded, **with** the increased-memory-limit entitlement, on a 4 GB device and on a 6/8 GB device | Settings → Voices → Download, then Play sample; then a 5-minute session with small + alba. | `measurements`: `memory pocket-tts loaded resident_mb=… peak_mb=…`; `pocket-tts synthesis … resident_mb=` | numbers recorded; no jetsam during the session (the app is not killed; check Settings → Privacy → Analytics for a `JetsamEvent` log) | pending |
| 12 | The same **without** the entitlement (Debug build with the key removed from `ReVoxMobile.entitlements`; restore it afterwards) on the 4 GB device | Same procedure. | same lines | numbers recorded side by side; note whether the session survived. This row decides whether the entitlement stays (it stays unless it demonstrably breaks signing or processing; §5.6) | pending |
| 13 | `DeviceRecommendation.pocketTTSAdvisory` threshold (6 GB) | From rows 11–12: does the 4 GB device fall back for memory pressure during a session (status "System voice — memory low")? | `memory pocket-tts dropped for memory pressure` | the advisory is shown exactly on the tier that fell back; otherwise propose the threshold change in the PR | pending |
| 14 | pocket-tts `.ane` real-time factor and cold ANE compile | Run `DeviceMeasurementTests.testPocketTTSSynthesisesEveryOfferedVoiceOffline` (airplane mode, pack installed); then 20 translated phrases. | `MEASUREMENT pocket-tts load ms=` (first load after install = cold compile), `MEASUREMENT pocket-tts voice=… rtf=`; `pocket-tts synthesis … rtf=` | RTF < 1.0 for every voice (median over the 20 phrases recorded); cold compile time recorded | pending |
| 15 | ANE contention when translate(N+1) overlaps speak(N) (§4.3, §13 Q6) | 20 phrases with the system voice, then 20 with alba; compare Whisper latency. | `measurements`: `translate ms=` (M3 `TimedTranslator`) and `pocket-tts synthesis s=` | p90 `translate ms` with pocket-tts speaking ≤ 1.3 × p90 without; otherwise record the numbers and raise §13 Q6 (a serialising switch) in the PR — never added silently | pending |
| 16 | Gain calibration: `PlayerNodeSink.pocketTTSEngineGain = 0.7` | Voices → select alba → Play sample; select a system voice → Play sample; Voice volume 1.0 both times. | `playback clip rms_dbfs=… gain=0.7` vs `… gain=1.0` | the two RMS values within ±2 dB; otherwise change the constant so they are, re-measure, record the value | pending |
| 17 | ARC releases the models when the manager is dropped (§13 Q7) | On the 4 GB device: Play sample with alba (note `memory pocket-tts loaded`), then run a session with the largest installed Whisper model plus alba until iOS posts a memory warning — the `memory low` fallback of §9 drops the manager (rows 11–13 usually produce the warning; if it never fires in 15 minutes the row stays pending with that reason). | `memory pocket-tts dropped for memory pressure resident_mb=` and the `5 s later` line | resident memory 5 s after the drop is lower by at least the increment `loaded` added over the pre-load reading; otherwise §13 Q7 is answered "no" and M7's degradation policy must not rely on unloading | pending |
| 18 | Airplane mode: `initialize()` plus one synthesis per offered voice issues no request (§6.5, §11) | Airplane mode on; run `DeviceMeasurementTests.testPocketTTSSynthesisesEveryOfferedVoiceOffline`; then Play sample for each voice from the Voices screen; Settings → Cellular → ReVox shows no new data. | test result; Console: no `AssetDownloader` / `FileDownloader` / `URLSession` lines from the app | test passes for all four voices; no request | pending |
| 20 | **The start-of-phrase artifact the owner reported on build 13** — still heard on build 20 before "This is ReVox", so it survived M4's 5 ms ramp. M9 (build 22+) drops everything before the first *sustained* swing in the clip and ramps the 10 ms ahead of it (`ClipHead`, ReVoxCore) | Install build 22 or later, select alba, Play sample five times, then translate five phrases. Listen for the artifact. | `measurements`: `pocket-tts head trimmed_ms=… onset_ms=…` per clip, plus the M4 `playback head first=… peak10ms=… dc10ms=…` line | The artifact is gone. `trimmed_ms` says what was cut ahead of the speech; a consistent non-zero value is the transient the ramp could not remove. If the artifact remains with `trimmed_ms=0` and a quiet head, the cause is downstream of the buffer (engine start, session activation) — record the numbers and re-open there | pending |
| 19 | The increased-memory-limit entitlement is accepted by signing and App Store Connect | The TestFlight run of this milestone. | archive log; processing e-mail | archive and upload succeed; no ITMS warning naming the entitlement | pending |

## How to fill a row

1. Run the procedure; copy the relevant log lines into `Evidence` or under `Raw logs`.
2. Write `measured: …` in `Result` with the numbers, or `pending` with the reason.
3. Fill "Decision taken" from the table; apply the code change it names in the same commit.
4. Commit on the milestone branch (`docs(measurements): record M4 device results`); the PR body links this file and states the decision.

## Raw logs

(paste trimmed Console excerpts here, one heading per row)
