# Milestone 6 on-device measurements

The design spec marks the History search predicate ASSUMED (§6.10, §10.4, §13 Q12) and M6 is the milestone that verifies the export and share path on a device. This file is the record, in the layout of `m3-microphone-mode.md`: one row per item, the procedure, the evidence, the pass criterion and the result. Results are filled on an iPhone (iPhone 12 or newer, iOS 17+) with the TestFlight build of this milestone or a Debug build from Xcode; log lines are read in Console.app (subsystem `revox`, category `history`) or with `log stream --predicate 'subsystem == "revox"'`. A row that could not be measured stays `pending` with the reason and is listed in the PR body.

Device used: `pending` (model, iOS version).

| # | ASSUMED item (spec) | Procedure | Evidence | Pass criterion | Result |
|---|---|---|---|---|---|
| 1 | The SwiftData store translates `localizedStandardContains` (§6.10, §10.4, §13 Q12) | Simulator: `TranscriptSearchTests.testTheStoreTranslatesLocalizedStandardContains` asserts it, so a green `ios-simulator` job is the evidence (a `print` would not be: xcbeautify does not carry test stdout into the CI log). Device: translate one phrase so the transcript contains a lowercase word, open History, search for that word in upper case. | the CI run; the History search result on the device | the test passes in CI and the lowercase entry appears for the upper-case query on the device. If either shows the fallback, record it here and add the sentence "Search matches exact case only" to the README's Transcripts section in the same commit; the code keeps the runtime fallback. | simulator: `measured` — see the CI run linked in the milestone PR; device: pending |
| 2 | `ShareLink` with a file URL offers the `.txt` to Files, Mail and AirDrop under the Windows file name (§6.10, API §10) | Session detail → Share → Save to Files; open the file in Files; repeat with Mail. | the saved file | the file name matches `yyyy-MM-dd_HH-mm-ss.txt`; the first line starts with `# ReVox session `; every entry has a `  → ` line | pending |
| 3 | Exported temp files are pruned after a day (§6.10) | Share one session, force-quit, set the date one day ahead (Settings → General → Date & Time, automatic off), relaunch. Restore automatic time afterwards. | `history` category: `pruned 1 export(s) older than a day` | the log line appears exactly once on the relaunch | pending |
| 4 | VoiceOver on History, Session detail and About (§8.8) | VoiceOver on; swipe through History (rows, Clear All), one session (header, rows, Share, Delete) and About (licence links). | manual | every element has a label; a row reads as one sentence; nothing is announced twice while idle | pending |
| 5 | Dynamic Type at the largest accessibility size (§8.1) | Settings → Accessibility → Display & Text Size → Larger Text, maximum; open the three screens. | screenshots | no clipped or overlapping text; the session header wraps | pending |

## How to fill a row

1. Run the procedure; copy the relevant log lines into `Evidence` or attach them under `Raw logs` below.
2. Write `measured: …` in `Result` with the numbers, or `pending` with the reason.
3. Commit the file on the milestone branch; the PR body links this file.

## Raw logs

(paste trimmed Console excerpts here, one heading per row)
