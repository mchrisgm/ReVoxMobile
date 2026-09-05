# Milestone 11 — on-device model benchmark

Milestone 11 §5 adds **Settings › Models › Benchmark this iPhone**: the app reads one fixed sentence aloud with the
iPhone's own voice (silently, through `AVSpeechSynthesizer.write`), converts it to the pipeline's 16 kHz mono
Float32, and for every installed and verified Whisper model — strictly one at a time, unloading between them — times
the load, a first translate and a second (steady) translate, samples resident memory before and after, scores the
gate's English against the reference with a word error rate, and writes one `benchmark model=…` line to the
`measurements` log category. The run is saved under `Application Support/ReVox/Benchmarks/` and can be shared as
text from the screen. Until a run exists the Models screen recommends by memory size; after one, it recommends the
most accurate installed model that qualifies (`DeviceRecommendation.measured`) and says when it was measured.

Nothing in this file is measured yet. The published figures below are **expectations** from other people's runs,
not ReVox's numbers; the owner's table and the rows are filled by running the benchmark on real iPhones.

**Devices used:** `pending` (model, iOS version, RAM from the `device` log line: `physicalMemory=… tierGB=…`).

## How to run

1. Force-quit ReVox first, so the first load of each model is the process's first (Core ML keeps the compiled
   model across launches, so this is a warm compile and a cold process; the first-ever compile after a download
   happens during the install's verifying step and is not what this measures).
2. Settings › Models › **Benchmark this iPhone** › **Run benchmark**. Keep the app open and the screen on; a large
   model can take a minute.
3. **Share results** and paste the text under *Raw logs* below, one heading per device and date. The table it
   contains has the same columns as the owner's table, so the rows can be copied across.
4. In Console.app, filter `subsystem:revox category:measurements` and copy the `benchmark model=…` lines too.
5. The Models screen now shows the recommendation the benchmark produced and the date; note it in row 7.

## Published reference numbers (expectations, not ReVox's)

Argmax's regression data for WhisperKit on iPhones, read from the files behind the WhisperKit Benchmarks dashboard
and its raw dataset. Every speed figure is an offline transcription of two 10-minute files (librispeech-10mins and
earnings22-10mins) with VAD chunking and four concurrent workers on CPU + Neural Engine: a **speed factor**
(seconds of audio per second of wall-clock), not the per-phrase latency ReVox's benchmark measures. Load times are
warm loads of an already-compiled model. WER is the mean over the two sets, in percent. Cited rows only; the
dashboard was last updated 2025-10-17 and covers WhisperKit 0.9.1 to 0.14.0, so it will drift from these values.

| Model (Argmax folder) | Device | Speed factor (RTF) | Mean WER | Note | Source |
|---|---|---|---|---|---|
| tiny | iPhone 13 (A15, 4 GB) | 59.88× (0.017) | 16.78 % | iOS 18.7, 2025-10-07 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| base | iPhone 13 (A15, 4 GB) | 38.13× (0.026) | 12.46 % | iOS 18.7, 2025-10-07 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| small | iPhone 13 (A15, 4 GB) | 12.39× (0.081) | 8.7 % | iOS 18.7, 2025-10-07 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| large-v3 (`openai_whisper-large-v3_947MB`, the folder ReVox installs) | iPhone 13 (A15, 4 GB) | 1.56× (0.64) | 28.93 % (librispeech 4.6, earnings22 55.81) | warning flag in the support matrix | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| tiny | iPhone 13 Pro (A15, 6 GB) | 41.27× (0.024) | 16.85 % | iOS 18.1, 2025-06-16 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| base | iPhone 13 Pro (A15, 6 GB) | 30.04× (0.033) | 12.39 % | iOS 18.1, 2025-06-16 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| small | iPhone 13 Pro (A15, 6 GB) | 10.04× (0.10) | 8.8 % | iOS 18.1, 2025-06-16 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| large-v3 (947 MB) | iPhone 13 Pro (A15, 6 GB) | 1.37× (0.73) | 28.1 % (4.73 / 53.92) | iOS 18.1, 2025-06-16 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| tiny | iPhone 15 Pro (A17 Pro, 8 GB) | 60.09× (0.017) | 17.57 % | iOS 18.1, single run 2024-10-30 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| base | iPhone 15 Pro (A17 Pro, 8 GB) | 46.71× (0.021) | 12.53 % | iOS 18.1, single run 2024-10-30 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| small | iPhone 15 Pro (A17 Pro, 8 GB) | 14.95× (0.067) | 9.01 % | iOS 18.1, single run 2024-10-30 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| large-v3 (947 MB) | iPhone 15 Pro (A17 Pro, 8 GB) | 1.85× (0.54) | 25.65 % (4.8 / 48.69) | iOS 18.1, single run 2024-10-30 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| tiny | iPhone 16 Pro (A18 Pro, 8 GB) | 92.47× (0.011) | 16.6 % | iOS 26.1, 2025-10-08 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| base | iPhone 16 Pro (A18 Pro, 8 GB) | 57.63× (0.017) | 12.22 % | iOS 26.1, 2025-10-08 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| small | iPhone 16 Pro (A18 Pro, 8 GB) | 19.08× (0.052) | 8.84 % | iOS 26.1, 2025-10-08 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| large-v3 (947 MB) | iPhone 16 Pro (A18 Pro, 8 GB) | 2.31× (0.43) | 27.37 % (4.73 / 52.4) | iOS 26.0, 2025-08-13 | [performance_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/performance_data.json) |
| medium | every iPhone | not published | not published | medium appears in no run, no support-matrix row and no device tier; the benchmark is the only number | [support_data.csv](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/support_data.csv) |

Warm load times and resident memory from the raw run files (an already-compiled model, the benchmark app's own
resident size sampled during transcription, not a full-app footprint):

| Model | Device | Warm load | Resident during transcription | Source |
|---|---|---|---|---|
| tiny | iPhone 16 Pro, iOS 26.1 | 0.376 s | peak 214 MB, mean 189 MB | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |
| base | iPhone 16 Pro, iOS 26.1 | 0.419 s | peak 220 MB, mean 184 MB | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |
| small | iPhone 16 Pro, iOS 26.1 | 0.592 s | peak 254 MB, mean 210 MB (thermal rose to fair) | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |
| small | iPhone 13, iOS 18.7 | 0.804 s | peak 197 MB, mean 186 MB | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |
| base | iPhone 12 mini, iOS 18.7 | 0.643 s | peak 161 MB, mean 157 MB | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |
| small | iPhone 12 mini, iOS 18.7 | 0.913 s | peak 194 MB, mean 182 MB (thermal critical for the whole run) | [run 2025-10-17T004021_3900754](https://huggingface.co/datasets/argmaxinc/whisperkit-evals-dataset/tree/main/benchmark_data/2025-10-17T004021_3900754) |

Device-independent quality (Apple Silicon Mac cluster, full test sets), for the accuracy order between models:

| Model | librispeech WER | earnings22-12hours WER | Source |
|---|---|---|---|
| tiny | 7.46 % | 20.97 % | [quality_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/quality_data.json) |
| base | 4.94 % | 16.4 % | [quality_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/quality_data.json) |
| small | 3.21 % | 13.0 % | [quality_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/quality_data.json) |
| large-v3 (947 MB, the folder ReVox installs) | 2.41 % | 17.08 % | [quality_data.json](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks/resolve/main/dashboard_data/quality_data.json) |

What these say for ReVox: tiny, base and small keep up on every iPhone from the 12 family on; the 947 MB large-v3
build ReVox pins is 1.4–2.3× real time in batch and collapses on long recordings, so it is unlikely to meet the
`maxRealTimeFactor` rule on any iPhone; and a short phrase in a live conversation carries a per-call overhead these
batch figures do not show, which is exactly what the benchmark measures.

## Measured on this iPhone (the owner fills this)

Paste the shared text's table rows here, one block per device. The columns are the ones `BenchmarkReport.markdown`
writes, so a row can be copied as it is.

**Device:** `pending` · **iOS:** `pending` · **Memory tier:** `pending` · **WhisperKit:** 1.1.0 · **Date:** `pending` · **Sentence:** `pending`

| Model | Load s | First s | Steady s | Audio s | RTF | WER | Resident before MB | Peak delta MB | Thermal | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| tiny | pending | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| base | pending | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| small | pending | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| medium | pending | pending | pending | pending | pending | pending | pending | pending | pending | pending |
| large-v3 | pending | pending | pending | pending | pending | pending | pending | pending | pending | pending |

## Rows

| # | ASSUMED item (spec) | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 1 | Load time per model as the process's first load (§5) | Force-quit, run the benchmark, once per device | `measurements`: `benchmark model=… load_ms=…`; the share text's `Load s` column | recorded per device; note which models exceed `maxLoadSeconds` (10 s) | pending |
| 2 | Real-time factor on the synthesised sentence (§5) | The same run | `rtf=…` and `audio_ms=…`; the `RTF` and `Audio s` columns | small < 0.5 on every test device; compare with the published speed factor for the same device above and note the per-phrase gap | pending |
| 3 | Accuracy of the synthesised sentence against the same sentence spoken by a person (§5) | Run the benchmark, then say the sentence into Live with Learning off and read the transcript | the share text's `WER` column vs the Live transcript | synthesised WER ≤ spoken WER; note the gap | pending |
| 4 | Resident-memory delta per model on a 4 GB and an 8 GB iPhone (§5, §9) | The same run on each device; afterwards check Settings › Privacy & Security › Analytics for a JetsamEvent | `resident_before_mb=… peak_delta_mb=…` | no JetsamEvent; delta ≤ 1.5 × the catalogue size; a delta of 0 means an earlier model's memory was never returned, note it | pending |
| 5 | Thermal state reached by one full run of every installed model (§5, §9) | The same run | `thermal=…` per model and any `Skipped: iPhone too hot` row; the "iPhone is hot" banner on the Live tab if it appeared | recorded per model | pending |
| 6 | `AVSpeechSynthesizer.write` delivers the terminating buffer (closes M3 row 6) | Five runs | `measurements`: `write ended by terminating buffer` vs `write ended by timeout` | 5 of 5 by terminating buffer | pending |
| 7 | The recommendation thresholds `maxRealTimeFactor = 0.5`, `maxLoadSeconds = 10` (ASSUMED) | After the run, a 10-minute Live session on the recommended model | the Models screen's "Measured on this iPhone on …" row; the transcript | no `… (skipped: falling behind)` markers; otherwise propose new thresholds under *Decisions taken* | pending |
| 8 | Which sentence each device could say (es / fr / de / en) | The same run | the `Sentence (…)` line of the share text | recorded per device | pending |
| 9 | Background task and idle timer keep the run alive (§5) | Lock the screen while large-v3 loads | the run finishes, or the screen says `Stopped after N of M models; the results so far are kept.` and the partial file exists under `Benchmarks/` | one of the two; never a killed app | pending |

## How to fill a row

1. Run the procedure; copy the relevant log lines into `Evidence` or attach them under `Raw logs` below.
2. Write `measured: …` in `Result` with the numbers, or `pending: <reason>`.
3. Commit the file on the milestone branch; the PR body links this file.

## Raw logs

(paste the shared text and the trimmed Console excerpts here, one heading per device and date)

## Decisions taken

- Recommendation thresholds: `<kept maxRealTimeFactor 0.5 and maxLoadSeconds 10 | changed to …>` after row 7.
- Catalogue follow-up: the pinned large-v3 folder (`openai_whisper-large-v3_947MB`) is 2–4× slower on iPhones and far
  worse on long recordings than the 626 MB `v20240930` build in Argmax's data; `<confirmed on device | not confirmed>`,
  and whether a catalogue change through `docs/model-revisions.md`'s one-commit rule is opened.
