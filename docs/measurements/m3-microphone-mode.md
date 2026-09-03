# Milestone 3 on-device measurements

The design spec marks several M3 behaviours ASSUMED (§10.4, §13 Q1–Q4). This file is the record: one row per item, the procedure, where the evidence comes from, the pass criterion, and the result. Results are filled on an iPhone (iPhone 12 or newer, iOS 17+) running a TestFlight build or a Debug build from Xcode; log lines are read in Console.app (subsystem `revox`) or with `log stream --predicate 'subsystem == "revox"'`. A row that could not be measured in the milestone stays `pending` and is listed in the PR body.

Device used: `pending` (model, iOS version, RAM as reported by the `device` log line).

| # | ASSUMED item (spec) | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 1 | `physicalMemory` values and the GiB rounding (§5.6, §10.4) | Launch the app once on each test device | `device` category: `physicalMemory=… tierGB=… recommended=…` | `tierGB` equals the nominal RAM (4/6/8) on every device | pending |
| 2 | `exp(langProbs[language])` is a probability in [0, 1]; how often the 0.4 gate fires (R2, §13 Q2) | Speak 30 phrases in Spanish, 30 in German, 10 in English with Auto-detect | `whisper` category: `language=… probability=…`; `measurements`: `detect ms=…`; any `language probability outside [0, 1]` error line | zero out-of-range lines; note the count of phrases dropped by the 0.4 gate | pending |
| 3 | Windows 0.5 threshold transfers to the CoreML 512-sample export; `.cpuOnly` vs `.cpuAndNeuralEngine` (R1, §13 Q1) | Play the same 3-minute recording into the iPhone mic and into the Windows app; count phrases and compare boundaries from both transcripts; run `DeviceMeasurementTests.testSileroScoresSilenceBelowThreshold` | the two `.txt` exports; the test result | phrase count within ±10 %; no phrase split that Windows did not split; silence scores < 0.5 on both compute units | pending |
| 4 | Converter feeding pattern (`.haveData` then `.noDataNow`) has no chunk-edge clicks (§6.1) | One 2-minute session on the built-in mic (48 kHz) and one on a Bluetooth HFP headset | `microphone` category: five `tap frames=… rate=… out=…` lines per session; the transcripts | no word truncated at buffer edges in 20 consecutive phrases on either route | pending |
| 5 | Tokenizer snapshot path equals WhisperKit's search path; airplane-mode load succeeds (§6.9) | Install small, enable airplane mode, force-quit, relaunch, Start, speak one phrase | status line `small · ready`; the phrase translates; Settings → Cellular shows no data for ReVox during the session | load and translate succeed with no network | pending |
| 6 | `AVSpeechSynthesizer.write` delivers a zero-length terminating buffer reliably (R7, §13 Q3) | 50 phrases with the system voice | `measurements` category: `write ended by terminating buffer` vs `write ended by timeout` | ≥ 49 of 50 end by terminating buffer; otherwise adopt the `speak()` fallback of §6.6 in M4 | pending |
| 7 | `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` spelling compiles (API §7) | CI build of Task 29 | `PCMConverterDriver.swift` compiled | compiles | measured: compiles (Task 29 CI run) |
| 8 | Hallucination rate on 0.4–1 s phrases with `windowClipTime: 0`; how often faster-whisper's fallback ladder would have fired (W3, §13 Q4) | 40 short interjections ("sí", "vale", "hm") plus 40 normal phrases | `measurements` category: `translate ms=… samples=… segments=… minAvgLogProb=…`; the transcript | hallucinated entries per 40 short phrases; count of phrases with `minAvgLogProb < -1.0` (faster-whisper's `log_prob_threshold`) as "would have fallen back" | pending |
| 9 | First-token check: `firstTokenLogProbThreshold: nil` keeps hesitant openings (R3, §10.4) | Record `hesitant-es.wav`, add it to the test target, run `DeviceMeasurementTests.testFirstTokenThresholdComparison` on the device | the `MEASUREMENT firstToken …` line | text with nil; note what the default −1.5 returns | pending |
| 10 | Per-phrase latency of base and small on the test devices (§13 Q4) | 20 normal phrases with base, 20 with small | `measurements`: `translate ms=…` and `detect ms=…` | median and p90 per model recorded here | pending |
| 11 | Reference resampler vs `AVAudioConverter` agree within ±16 samples on real tap audio (W1) | Read the five `tap frames=… out=…` lines of row 4 | `out` vs `frames × 16000 / rate` | difference ≤ 16 on every line | pending |
| 12 | App Store Connect scan of the SDKs' `attributesOfItem` calls; manifests complete (§13 Q13) | First TestFlight upload (Task 44) | App Store Connect processing e-mail / ITMS warnings | no ITMS-91053 warning | pending |
| 13 | Tap-rebuild retry budget: `MicrophoneCapture.rebuildRetryLimit` 3 × `rebuildRetryDelay` 0.2 s covers the input-unavailable transient after a route change (§6.1) | Start a session on a wired or Bluetooth headset, speak continuously, unplug or power off the headset mid-phrase, keep speaking on the built-in mic; repeat 10 times | `microphone` category: `tap rebuild attempt N of 3 failed` lines and whether "No microphone input" appeared on the Live status line | in ≥ 9 of 10 unplugs the tap is back within the 3 attempts and no status line appears; if the line appears more often, raise the limit or the delay here and in `MicrophoneCapture` | pending |

## How to fill a row

1. Run the procedure; copy the relevant log lines into `Evidence` or attach them under `Raw logs` below.
2. Write `measured: …` in `Result` with the numbers, or `pending` with the reason.
3. Commit the file on the milestone branch; the PR body links this file.

## Raw logs

(paste trimmed Console excerpts here, one heading per row)
