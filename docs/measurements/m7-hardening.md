# Milestone 7 — on-device measurements

The ASSUMED items of milestone 7 and the open questions §13 Q13–Q16 of
`docs/superpowers/specs/2026-09-02-revox-mobile-design.md`. Every row is filled with `measured: …` and the device,
iOS version and build number, or with `pending: <reason>`. A row that changes a shipped default names the follow-up
commit. Nothing here is a code comment: the code carries the values, this file carries the evidence.

**Devices used:** `<device> / iOS <version> / TestFlight build <N>` (repeat per device).

**How to read the logs:** the app logs to the subsystems below; collect with Console.app (device connected) or
`log collect --device --last 30m` and filter on `subsystem:revox`.

| Category | What it logs |
|---|---|
| `revox:storage` | `storage total_mb=… free_mb=… kinds=…` on every refresh |
| `revox:models` | `recorded N files for installedFiles.<kind>`, `upstream changed for …: N added, N removed, N resized` |
| `revox:translation` | `reloading whisper after a failure model=…`, `whisper failed again after a reload …` |
| `revox:degradation` | `memory pressure: dropping pocket-tts`, `switching to model=…`, `thermal critical: pausing translation`, `thermal recovered: resuming translation` |
| `revox:measurements` | per-phrase detect/translate timings |

| # | Question (spec) | Procedure | Pass criterion | Result |
|---|---|---|---|---|
| 1 | Storage accounting accuracy (§13 Q14, §6.9) | Install small + the VAD + pocket-tts. Read the Models footer ("ReVox models: …") and compare with **Settings → General → iPhone Storage → ReVox** (Documents & Data) and with the per-row sizes. | The footer total is within 5 % of the Documents & Data figure, and each installed row shows a measured size within 5 % of the catalog estimate. | pending: needs a device |
| 2 | Free-space rule thresholds (§10.4, §6.9) | Fill the device until roughly 1.2 GB is free (large video files), then try to download small (487 MB) and medium (1 528 MB). | Medium is refused with "Not enough space: needs about 2.1 GB, 1.2 GB free" (`hasRoomToInstall`: expected × 1.25 + 200 MB); small is allowed and shows the "Only … will remain" warning; the install completes and the device does not run out of space. | pending: needs a device |
| 3 | Upstream-change detection (§13 Q14, §11) | After a completed VAD install, note `recorded N files for installedFiles.vad`. Re-install the VAD (delete, download again) and read the log. Then, with a debug build, append a byte to a file in `Models/silero-vad/…` and reopen Models. | The re-install logs either no diff or `upstream changed for installedFiles.vad: …` naming the files; the edited-file case shows "Files changed since download — re-download to be sure" on the VAD row and clears after a re-download. | pending: needs a device |
| 4 | Whisper load failure recovery on device (§9 row 1) | With base and small installed and small selected, corrupt small in a debug build (`rm` the `AudioEncoder.mlmodelc/coremldata.bin` under `Models/models/argmaxinc/whisperkit-coreml/openai_whisper-small/`), then press Start. | The banner reads "Couldn't load small. Using base instead.", the run works and translates, the status line shows `base · ready`, Settings still shows small as the selected model, and the app does not crash. With base deleted too, the banner reads "Couldn't load small. Re-download small in Models." and the pipeline never enters the error state. | pending: needs a device |
| 5 | Mid-run reload retry (§9 row 2) | Start a run on small, speak continuously, and in a debug build make `WhisperEngine.transcribe` throw once via the debug menu (or delete the model folder mid-run to force a real failure). | `revox:translation` logs one `reloading whisper after a failure`; translation continues after a gap of `< 5 s` (record it); a second failure surfaces the "Try again" banner and the pipeline stops cleanly. When the run had already seen a memory warning, `revox:degradation` also logs `whisper failed after N memory warning(s)` and `switching to model=…` — the "or fails next call" half of the §9 memory row (record which of the two happened). | pending: needs a device |
| 6 | Thermal thresholds and model eviction (§13 Q15) | Run 20 minutes of continuous speech on small (mic mode), Low Power Mode off, screen on. Log `ProcessInfo.thermalState` every minute (`revox:degradation`). Note whether `.serious` or `.critical` is reached and what the app did. | The thermal state reached is recorded; if `.serious` was reached, the "iPhone is hot: translation reduced" banner appeared, the **running** session kept translating on the model it had loaded (§9 asks for the smaller model for new sessions, so `restartRunning` is false there) and the **next** Start ran on base — confirm both in `revox:degradation` (`switching to model=base restartRunning=false`) and in the status line after the next Start; if `.critical` was reached, translation paused and resumed automatically on recovery. Records whether a loaded model was ever evicted **before** a call failed (Q15): `observable` / `not observable`; when it is not observable, the `whisperFailed` path of row 5 is what implements "if Whisper was evicted **or fails next call**". | pending: needs a device |
| 7 | Memory warnings and pocket-tts release (§13 Q15, §6.5, Q7 follow-up) | On a 4 GB device: install small + pocket-tts, start a run, then open several heavy apps to force `didReceiveMemoryWarning`. Log `MemoryMeter.residentBytes()` before and after the warning. | A memory warning is delivered **before** a jetsam kill at least once; the banner reads "Memory low: switched to the system voice"; resident memory drops by ≥ 300 MB after `unloadPocketTTS`; the run keeps translating with the system voice. If ReVox is killed without a warning, record that and note that the transcript's last entries survived (explicit saves, §6.10). | pending: needs a device |
| 8 | App Store scan of the SDKs' required-reason calls (§13 Q13, §10.4) | Upload the M7 build and read the App Store Connect email and the build's warnings. | No ITMS-91053 (missing required-reason API) notice; if one arrives, it names the API and the fix is a manifest entry in both plists in a follow-up commit. | pending: awaiting the App Store Connect processing report for the M7 build |
| 9 | Tokenizer redistribution and a ReVox-owned mirror (§13 Q16) | Decision, not a device test: confirm that `openai/whisper-<size>` tokenizer files are fetched from Hugging Face at the pinned `tokenizerRevision` at install time and are never redistributed inside the app bundle; check whether any pinned revision has disappeared upstream since 2026-09-02 (open `https://huggingface.co/openai/whisper-small/commit/<revision>`). | All five pinned tokenizer revisions still resolve. Conclusion recorded as `mirror not needed` or, if a revision has gone, a follow-up issue for a ReVox-owned mirror (out of scope for v1, §2 non-goals). | pending: not yet re-checked upstream |

## Raw logs

Paste the relevant `revox:*` lines, the storage figures of row 1 and the resident-memory numbers of row 7 here.

## Decisions taken

- Degradation thresholds: `<kept as shipped | changed to …>` — the shipped rule is one pocket-tts drop on the
  first memory warning, then one model step down per further warning **and** one on the first Whisper failure that
  follows a memory warning (§9 "evicted or fails next call"), both applied to a running session at once; one model
  step down at thermal `.serious` that takes effect at the **next** Start and leaves the running session alone
  (§9 "for new sessions"), a pause at `.critical` and a restore of the user's model on `.nominal`/`.fair`.
- Free-space rule (§6.9): `<kept 1.25 × expected + 200 MB | changed to …>`.
- Storage accounting (§6.9): `<kept .totalFileAllocatedSizeKey | changed to …>`.
