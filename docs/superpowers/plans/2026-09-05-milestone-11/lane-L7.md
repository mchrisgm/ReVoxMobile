## Lane L7: Wave 2 docs (README, ADR-0006/0007, bug template)

**Files**
- Modify: `/home/user/ReVoxMobile/README.md`
- Modify: `/home/user/ReVoxMobile/docs/adr/0006-whisper-translate-is-english-only.md`
- Modify: `/home/user/ReVoxMobile/docs/adr/0007-pocket-tts-english-only-system-voice-for-replies.md`
- Modify: `/home/user/ReVoxMobile/.github/ISSUE_TEMPLATE/bug_report.md`
- Create: nothing. There is no `CHANGELOG*` file in the repository (checked with `ls CHANGELOG*`), and the W8 row of the deviation table in `docs/superpowers/specs/2026-09-02-revox-mobile-design.md` was already written by L2 (line 51; W2 retired on line 45), so this lane does not touch that spec.
- Do NOT touch: `docs/onboarding.md` (L6), `docs/superpowers/specs/2026-09-02-revox-mobile-design.md` (L2), `docs/measurements/m11-model-benchmark.md` (L3), any Swift file.
- Test files: none are committed. This is a documentation lane, so every "test" is a shell assertion run before the edit (it must fail) and after it (it must pass), plus one throwaway link checker at `/tmp/claude-0/-home-user/1059ed5c-2bd6-57ef-98c8-c2996914a65b/scratchpad/l7-check-links.py` (written in Task 5, never committed).

**Interfaces**

Consumes (names and strings this lane quotes; all exist on the branch after the L1/L2 merges unless marked):
- `LiveControlStrip.listenCaption = "Listen"`, `voiceCaption = "Voice"`, `languagesCaption = "Languages"`, `youSpeakTitle = "You speak"`, `theySpeakTitle = "They speak"`, `chooseLanguageTitle = "Choose…"`, `lockedText = "Stop to change"`, `duckingPillName = "Duck"`, `learningPillName = "Learn"`, `twoWayPillName = "Two-way"` (`ReVoxMobile/Screens/Live/LiveControlStrip.swift` lines 42–69).
- `LiveView.noLanguageTitle = "Not set"`, `LiveView.twoWaySummary(you:they:)` panel line "What you say in English is spoken to them in Spanish; what they say is spoken to you in English." (`ReVoxMobile/Screens/LiveView.swift` lines 291, 342).
- `LiveViewModel.voiceNote(for:)`: "This iPhone has no Spanish voice, so what you say to them stays in the transcript. Add one in Settings › Accessibility › Spoken Content › Voices." (`LiveViewModel.swift` line 247).
- `SettingsView` section header `Text("Your language")` and picker title `"You speak"` (`ReVoxMobile/Screens/SettingsView.swift` lines 54–64).
- `TranscriptFormatter.guessPrefix = "(unsure) "` (`ReVoxCore/Sources/ReVoxCore/TranscriptFormatter.swift` line 46); `Settings.keepGuesses` (key `keep_guesses`, default true); the Settings section **Unsure phrases** with the toggle **Keep unsure phrases in History** (`ReVoxMobile/Screens/GuessesSettingsSection.swift`, inserted into `SettingsView` by L5).
- From L3 (merged before wave 2): the Models row **Benchmark this iPhone**, `DeviceRecommendation.maxRealTimeFactor = 0.5` and `maxLoadSeconds = 10`, the file `docs/measurements/m11-model-benchmark.md`.
- From L4/L5: the word popover strings quoted in the Learning bullet ("Look up in the dictionary"; the Say button disabled while the microphone listens; meanings need iOS 18).
- From L6: the seven tutorial page names (Welcome; The Live controls; Start and read; Two-way conversation; Learning mode; Models and voices; You're ready) and the greyed unsure line on the transcript page.

Produces: nothing another lane compiles against. The README, ADR-0006/0007 and the bug template are the only user-facing documents that still contained "Leave alone", "Reply in", "Don't translate", "Skip a language" or "left alone" outside `docs/onboarding.md`; after this lane the grep in Task 6 is the milestone's proof that they are gone.

### Task 1: The pair is named by the people in the README's opening, the screenshots and the Two-way section

- [ ] **Step 1: The failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && ! grep -n -e "Leave alone" -e "Reply in" -e "Don't translate" -e "Skip a language" -e "left alone" README.md
  ```

  Expected now: the grep prints README lines 26, 32, 34, 138, 140, 141 and 142 and the command exits 1 (the `!` inverts a successful match). It passes only when none of the five phrases is left in the README.

- [ ] **Step 2: "Why ReVox".** Edit `/home/user/ReVoxMobile/README.md`. Replace the end of line 26 exactly:

  old:
  ```
  Since milestone 8 it also talks back: with **Two-way** on, your own language is left alone and what you say is spoken to the other person in theirs.
  ```
  new:
  ```
  Since milestone 8 it also talks back: with **Two-way** on, what you say is spoken to the other person in their language, and the language you speak is neither translated nor spoken back at you.
  ```

- [ ] **Step 3: The two Live alt texts (line 32).** Replace the first two image alt texts of the screenshot table:

  old:
  ```
  | ![The Live screen before a session: three rows of pills — Mic, Balanced, Duck on and an info button; Learn off, Two-way on and the volume; Leave alone English and Reply in Spanish — the status line, and a teal Start button](docs/screenshots/live-idle.png) | ![The Live screen translating: the pills dimmed behind a "Stop to change" lock, a Spanish phrase with the words as spoken above its English translation, three more phrases with their ages, and a red Stop button](docs/screenshots/live-running.png) |
  ```
  new:
  ```
  | ![The Live screen before a session: three captioned rows of pills — Listen: Mic, Balanced and an info button; Voice: Duck on and 100%; Languages: Two-way on and Learn off, with You speak English and They speak Spanish on the line beneath — the status line, and a teal Start button](docs/screenshots/live-idle.png) | ![The Live screen translating: the pills dimmed behind a "Stop to change" lock line, a Spanish phrase with the words as spoken as tappable chips above its English translation, three more phrases with their ages, and a red Stop button](docs/screenshots/live-running.png) |
  ```
  (Both remain the first two cells of that row; the third cell, the Models alt text, is edited in Task 4.)

- [ ] **Step 4: The Settings alt text (line 34).** Replace the middle cell:

  old:
  ```
  ![The Settings screen: the three latency modes with an example of what the selected one does, the Source language picker with an example, and the Skip a language section](docs/screenshots/settings.png)
  ```
  new:
  ```
  ![The Settings screen: the three latency modes with an example of what the selected one does, the Source language picker with an example, and the Unsure phrases toggle with its greyed sample row](docs/screenshots/settings.png)
  ```
  (The capture is 393 × 852 pt; the Unsure phrases section sits directly under Source language, which pushes the Your language header below the fold, so the alt text stops there.)

- [ ] **Step 5: The Two-way section (lines 138–142 and 147).** Replace the intro paragraph:

  old:
  ```
  By default ReVox translates everything it hears into English, including you. In a real conversation that is usually not what you want: your own language should be left alone, and what you say should be spoken back to the other person in *their* language.
  ```
  new:
  ```
  By default ReVox translates everything it hears into English, including you. In a real conversation that is usually not what you want: what you say should not be echoed back at you in English, it should be spoken to the other person in *their* language. So the two languages are named by the two people — **You speak** and **They speak** — on the Live tab, in Settings and in the tutorial alike.
  ```

  Replace the three numbered steps:

  old:
  ```
  1. In **Settings › Skip a language**, choose the language ReVox should leave alone — normally your own. From then on ReVox neither translates nor transcribes it, and **Source language** must stay on **Auto-detect** for it to work (a pinned language is never detected).
  2. On the **Live** tab, turn on **Two-way**. Two pickers appear: **Don't translate** (the same setting, so you can change it mid-conversation) and **Reply in**.
  3. Choose the other person's language under **Reply in**. Now both directions are live: their language is translated to English and spoken to you, and yours is transcribed and spoken back to them in the language you chose. Both sides appear in the transcript.
  ```
  new:
  ```
  1. Tell ReVox the language you speak: **Settings › Your language › You speak** (the first row is **Not set**). From then on ReVox neither translates nor transcribes that language, and **Source language** must stay on **Auto-detect** for it to work — a pinned language is never detected, and the pill says so.
  2. On the **Live** tab, turn on **Two-way** in the Languages row. A line appears beneath it with the pair: **You speak** (the same setting, so you can change it mid-conversation; it reads **Choose…** until it is set) and **They speak**, which shows **English** until you pick something else.
  3. Choose the other person's language under **They speak**. Now both directions are live: what they say is translated to English and spoken to you, and what you say is transcribed and spoken to them in their language. The ⓘ panel spells it out — "What you say in English is spoken to them in Spanish; what they say is spoken to you in English." — and both sides appear in the transcript.
  ```

  Replace the second "things to know" bullet:

  old:
  ```
  - The reply is spoken by an iOS voice for that language (pocket-tts speaks English only). If your iPhone has no voice for the language you picked, ReVox tells you while you are picking it; add one in **iOS Settings › Accessibility › Spoken Content › Voices**.
  ```
  new:
  ```
  - The reply is spoken by an iOS voice for that language (pocket-tts speaks English only). If your iPhone has no voice for the language under **They speak**, the pill shows a crossed speaker and the ⓘ panel says that what you say to them stays in the transcript; add one in **iOS Settings › Accessibility › Spoken Content › Voices**.
  ```

- [ ] **Step 6: Run the check from Step 1 again.** Expected: no output, exit 0.

- [ ] **Step 7: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add README.md && git commit -m "docs(readme): You speak / They speak — the two-way pair named by the people

The opening sentence, both Live screenshot alt texts, the Settings alt text and the Two-way
conversation section now use the milestone 11 names and describe the three captioned rows and
the pair line beneath them. No user-facing doc line says Leave alone, Reply in, Don't translate
or Skip a language any more (docs/onboarding.md is lane L6's).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

### Task 2: ADR-0006, ADR-0007 and the bug template

- [ ] **Step 1: The failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && ! grep -n -e "Leave alone" -e "Reply in" -e "Don't translate" -e "Skip a language" -e "left alone" docs/adr/0006-whisper-translate-is-english-only.md docs/adr/0007-pocket-tts-english-only-system-voice-for-replies.md .github/ISSUE_TEMPLATE/bug_report.md
  ```

  Expected now: prints ADR-0006 line 26, ADR-0007 line 18 and bug_report.md line 25; exits 1.

- [ ] **Step 2: ADR-0006.** Edit `/home/user/ReVoxMobile/docs/adr/0006-whisper-translate-is-english-only.md`.

  Replace the Date line:

  old:
  ```
  Non-goal in the design spec of 2026-09-02; the second direction added in milestone 8 (2026-09-04); recorded 2026-09-04.
  ```
  new:
  ```
  Non-goal in the design spec of 2026-09-02; the second direction added in milestone 8 (2026-09-04); recorded 2026-09-04. Milestone 11 (2026-09-05) renamed the surfaces to **You speak** / **They speak**; the decision is unchanged.
  ```

  Replace the first consequence:

  old:
  ```
  - Two-way needs **Source language = Auto-detect** (a pinned language is never detected) and a language chosen under Skip a language.
  ```
  new:
  ```
  - Two-way needs **Source language = Auto-detect** (a pinned language is never detected) and the language you speak chosen under **You speak** (Settings › Your language, or the pill on the Live tab).
  ```

- [ ] **Step 3: ADR-0007.** Edit `/home/user/ReVoxMobile/docs/adr/0007-pocket-tts-english-only-system-voice-for-replies.md`.

  Replace the Date line:

  old:
  ```
  Rulings R6 and R7 in the design spec of 2026-09-02; the reply routing added in milestone 8 (2026-09-04); recorded 2026-09-04.
  ```
  new:
  ```
  Rulings R6 and R7 in the design spec of 2026-09-02; the reply routing added in milestone 8 (2026-09-04); recorded 2026-09-04. Milestone 11 (2026-09-05) renamed the picker to **They speak**; the decision is unchanged.
  ```

  Replace the second Decision bullet:

  old:
  ```
  - **pocket-tts speaks English only.** A phrase in any other language — the reply half of a two-way conversation — goes straight to the system voice with an `AVSpeechSynthesisVoice` for that language. If the iPhone has no voice for the language the user picks under Reply in, ReVox says so while they are picking it; the user adds one in iOS Settings › Accessibility › Spoken Content › Voices.
  ```
  new:
  ```
  - **pocket-tts speaks English only.** A phrase in any other language — the reply half of a two-way conversation — goes straight to the system voice with an `AVSpeechSynthesisVoice` for that language. If the iPhone has no voice for the language the user picks under **They speak**, the pill shows a crossed speaker and the ⓘ panel says so while they are picking it; the user adds one in iOS Settings › Accessibility › Spoken Content › Voices.
  ```

- [ ] **Step 4: The bug template.** Edit `/home/user/ReVoxMobile/.github/ISSUE_TEMPLATE/bug_report.md`:

  old:
  ```
  - **Two-way:** off / on (Don't translate: …, Reply in: …)
  ```
  new:
  ```
  - **Two-way:** off / on (You speak: …, They speak: …)
  ```

- [ ] **Step 5: Run the check from Step 1 again.** Expected: no output, exit 0.

- [ ] **Step 6: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add docs/adr/0006-whisper-translate-is-english-only.md docs/adr/0007-pocket-tts-english-only-system-voice-for-replies.md .github/ISSUE_TEMPLATE/bug_report.md && git commit -m "docs: ADR-0006, ADR-0007 and the bug template say You speak / They speak

One-line milestone 11 notes on both ADRs' Date sections and the two sentences that named the
old pickers; the bug template asks for You speak and They speak. Nothing about either decision
changes.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

### Task 3: The Live screen as it is now — three rows, the lock line, quick controls, tappable words, the tutorial

- [ ] **Step 1: The failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && grep -q "three captioned rows of pills above the transcript" README.md && grep -q "Stop to change\*\* line appears" README.md && grep -q "Tap any word" README.md && grep -q "Learning with its tappable words" README.md && grep -q "one greyed and marked Unsure" README.md && echo ok
  ```

  Expected now: no `ok`, exit 1.

- [ ] **Step 2: The First-run paragraph (line 111).**

  old:
  ```
  The first launch opens a short interactive tutorial: seven pages that show a demo transcript typing itself in and let you try the source picker, Two-way, Learning, Romanize and the model choice without changing a setting. Skip it any time; **Settings › Show the tutorial** brings it back. [docs/onboarding.md](docs/onboarding.md) describes each page.
  ```
  new:
  ```
  The first launch opens a short interactive tutorial: seven pages that host the real Live controls and a demo transcript typing itself in, and let you try the pills, Two-way with You speak and They speak, Learning with its tappable words, Romanize and the model choice without changing a setting. Skip it any time; **Settings › Show the tutorial** brings it back. [docs/onboarding.md](docs/onboarding.md) describes each page.
  ```

- [ ] **Step 3: The tutorial transcript alt text (line 36).**

  old:
  ```
  ![The tutorial's transcript page: "Start and read", a demo transcript with four phrases and their ages, "Speaking the translation aloud", a red Stop capsule, and Back and Next buttons](docs/screenshots/onboarding-transcript.png)
  ```
  new:
  ```
  ![The tutorial's transcript page: "Start and read", a demo transcript with four phrases and their ages, one greyed and marked Unsure with a caption explaining it, "Speaking the translation aloud", a red Stop capsule, and Back and Next buttons](docs/screenshots/onboarding-transcript.png)
  ```

- [ ] **Step 4: The Translating intro (line 122).**

  old:
  ```
  The Live screen keeps its controls to two rows of pills above the transcript — source, latency, ducking, Learning, Two-way and volume, with a third row for the two-way languages — and an ⓘ button that unfolds what each one does, so the transcript gets the screen. A pill's text says what it is set to; tap it to change it.
  ```
  new:
  ```
  The Live screen keeps its controls to three captioned rows of pills above the transcript — **Listen** (Mic or Other apps, the latency mode, and an ⓘ that unfolds what every pill does), **Voice** (ducking and the voice volume) and **Languages** (Two-way and Learning, with a **You speak** / **They speak** line beneath while Two-way is on) — so the transcript gets the screen. A pill's text says what it is set to; tap it to change it.
  ```

- [ ] **Step 5: Locking (line 131).**

  old:
  ```
  The source and the two-way controls are locked while a session runs: ReVox reads them once, at Start. Stop and start again to change them.
  ```
  new:
  ```
  Every pill except the voice volume and the ⓘ is locked while a session runs, and a **Stop to change** line appears under the rows: ReVox reads them once, at Start. Stop and start again to change them.
  ```

- [ ] **Step 6: The Quick controls bullet (line 154).**

  old:
  ```
  - **Quick controls** sit on the Live screen under the two-way card: latency mode, ducking, Learning and the voice volume. Volume changes at once; the other three are read at Start, so they lock while a session runs.
  ```
  new:
  ```
  - **Quick controls** are the pills on the Live screen: Listen (the source and the latency mode), Voice (ducking and the voice volume) and Languages (Two-way and Learning). Volume changes at once; everything else is read at Start, so it locks while a session runs.
  ```

- [ ] **Step 7: The Learning bullet (line 159).**

  old:
  ```
  - **Learning** shows the words as they were spoken above the translation, so you can follow the other language as well as understand it. Each phrase is decoded a second time, so it takes a little longer to appear. **Romanize** (Settings › Learning) adds how the original sounds in Latin letters under a script you cannot read; Japanese kana are right, kanji come out with their Chinese readings.
  ```
  new:
  ```
  - **Learning** shows the words as they were spoken above the translation, so you can follow the other language as well as understand it. Each phrase is decoded a second time, so it takes a little longer to appear. Tap any word for its pronunciation and meaning: a small popover shows how it sounds in Latin letters, says it aloud (not while the microphone is listening, or ReVox would hear itself), gives its English meaning on iOS 18, offers **Look up in the dictionary** when the iPhone has a dictionary for that language, and shows the sentence with the word highlighted. Right-to-left languages show plain text for now. **Romanize** (Settings › Learning) adds how the whole original sounds in Latin letters under a script you cannot read; Japanese kana are right, kanji come out with their Chinese readings.
  ```

- [ ] **Step 8: Run the check from Step 1 again.** Expected: `ok`.

- [ ] **Step 9: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add README.md && git commit -m "docs(readme): the Live screen's three captioned rows, the lock line and tappable words

The Translating intro, the locking sentence and the Quick controls bullet describe Listen, Voice
and Languages; the Learning bullet says what tapping a word shows; the first-run paragraph and
the tutorial alt text follow the milestone 11 tutorial pages.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

### Task 4: Unsure phrases — the gate bullet, a feature bullet and the Transcripts paragraph

- [ ] **Step 1: The failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && grep -c "Unsure" README.md
  ```

  Expected now: `1` (the alt texts from Tasks 1 and 3 count; the count is only there to show the delta) and no line starting with `- **Unsure phrases.**`: `grep -q '^- \*\*Unsure phrases\.\*\*' README.md; echo $?` prints `1`.

- [ ] **Step 2: The Gates bullet (line 68).**

  old:
  ```
  - **Gates.** Language detection (unless a source language is pinned) with a probability gate, then Whisper's no-speech and log-probability gates and a hallucination list — the Windows gates, ported one-to-one.
  ```
  new:
  ```
  - **Gates.** Language detection (unless a source language is pinned) with a probability gate, then Whisper's no-speech and log-probability gates and a hallucination list — the Windows gates, ported one-to-one, with one deviation: a phrase the gates are unsure about is kept as a greyed, unspoken **Unsure** phrase instead of being dropped (row W8 of [the design spec](docs/superpowers/specs/2026-09-02-revox-mobile-design.md)).
  ```

- [ ] **Step 3: The new feature bullet.** Insert a bullet directly after the "Falling behind" bullet of the "While translating" list. The anchor is the existing line

  ```
  - If phrases arrive faster than they can be translated, ReVox keeps the newest three, shows **Falling behind** and marks the gap in the transcript.
  ```
  and the inserted line after it is:
  ```
  - **Unsure phrases.** When ReVox is not sure of the language or the words — the language guess is weak, or the phrase scores between the log-probability gate and the noise floor — the phrase is not thrown away: it appears greyed, marked **Unsure** with a question-mark symbol and in italics, and is never spoken aloud. **Settings › Unsure phrases › Keep unsure phrases in History** (on by default) decides whether History and the exported file keep them too, marked `(unsure)`; off keeps them on the Live screen only. A change takes effect the next time you tap Start.
  ```

- [ ] **Step 4: The Transcripts paragraph (line 281).**

  old:
  ```
  Every session is stored on the iPhone (SwiftData, in the app's own container, never synced). The **History** tab lists sessions newest first with the time, source, duration, entry count and first English line; the search field filters by English text and shows the matching line per session; a session opens to its header (start time, source, model, voice, source language) and its entries in the Live row style. **Share** exports the session as a `.txt` in the same format as the Windows app — a `# ReVox session <timestamp>` header, then `[HH:MM:SS] [<lang>] ` and `  → <english>` per entry, with `… (skipped: falling behind)` markers — through the share sheet (Files, Mail, AirDrop). The original-language text is empty on both platforms; only the English translation is stored. Swipe a row to delete it; **Clear All** and the per-session **Delete** ask for confirmation. Exported files live in the app's temporary folder and are removed after a day.
  ```
  new:
  ```
  Every session is stored on the iPhone (SwiftData, in the app's own container, never synced). The **History** tab lists sessions newest first with the time, source, duration, entry count and first English line; the search field filters by English text and shows the matching line per session; a session opens to its header (start time, source, model, voice, source language) and its entries in the Live row style. **Share** exports the session as a `.txt` in the same format as the Windows app — a `# ReVox session <timestamp>` header, then `[HH:MM:SS] [<lang>] ` and `  → <english>` per entry, with `… (skipped: falling behind)` markers — through the share sheet (Files, Mail, AirDrop). Since milestone 11 a phrase ReVox was unsure about is kept as well, while **Keep unsure phrases in History** is on: greyed under an **Unsure** heading in the session, counted on the session's row ("1 unsure phrase"), never matched by the search, and exported with `(unsure) ` at the start of its English line. The original-language text is empty on both platforms; only the English translation is stored. Swipe a row to delete it; **Clear All** and the per-session **Delete** ask for confirmation. Exported files live in the app's temporary folder and are removed after a day.
  ```

- [ ] **Step 5: Run the checks again.**

  ```bash
  cd /home/user/ReVoxMobile && grep -q '^- \*\*Unsure phrases\.\*\*' README.md && grep -q '(unsure) ' README.md && grep -q 'row W8' README.md && echo ok
  ```
  Expected: `ok`.

- [ ] **Step 6: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add README.md && git commit -m "docs(readme): unsure phrases — greyed, never spoken, kept in History by choice

The Gates bullet records the one deviation from the Windows gates (W8), a feature bullet
explains the Unsure row and the Keep unsure phrases in History setting, and the Transcripts
paragraph documents the (unsure) export marker, the Unsure heading and the search rule.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

### Task 5: Models — the benchmark row, the measured recommendation and the "Which model?" expectations table

- [ ] **Step 1: Preconditions and the failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && test -f docs/measurements/m11-model-benchmark.md && echo "L3 file present" ; ! grep -q "Which model" README.md && echo "README has no Which model section yet"
  ```

  Expected: `L3 file present` (if it is missing, lane L3 is not merged yet — stop and report; the link added below would dangle) and `README has no Which model section yet`.

- [ ] **Step 2: The link checker (scratchpad, not committed).** Write `/tmp/claude-0/-home-user/1059ed5c-2bd6-57ef-98c8-c2996914a65b/scratchpad/l7-check-links.py`:

  ```python
  import pathlib
  import re
  import sys

  root = pathlib.Path("/home/user/ReVoxMobile")
  files = [
      "README.md",
      "docs/adr/0006-whisper-translate-is-english-only.md",
      "docs/adr/0007-pocket-tts-english-only-system-voice-for-replies.md",
  ]
  bad = []
  for name in files:
      path = root / name
      for target in re.findall(r"\]\(([^)\s]+)\)", path.read_text(encoding="utf-8")):
          if target.startswith(("http://", "https://", "mailto:", "#")):
              continue
          resolved = (path.parent / target.split("#")[0]).resolve()
          if not resolved.exists():
              bad.append(f"{name}: {target}")
  print("\n".join(bad) or "all relative links resolve")
  sys.exit(1 if bad else 0)
  ```

  Run it now: `python3 /tmp/claude-0/-home-user/1059ed5c-2bd6-57ef-98c8-c2996914a65b/scratchpad/l7-check-links.py`. Expected: `all relative links resolve` (every screenshot under `docs/screenshots/` and every ADR exists on the branch).

- [ ] **Step 3: First run step 1 (line 113).**

  old:
  ```
  1. Open ReVox and go to **Settings › Models**. Tap **Download** next to a Whisper model. **Small** is the default and the right choice for most iPhones; the screen marks which models suit yours and warns about the ones that will be slow or hot. The voice detector downloads with your first model.
  ```
  new:
  ```
  1. Open ReVox and go to **Settings › Models**. Tap **Download** next to a Whisper model. **Small** is the default and the right choice for most iPhones; the screen marks which models suit yours and warns about the ones that will be slow or hot. The voice detector downloads with your first model. Once a model is installed, **Settings › Models › Benchmark this iPhone** times every installed model on your phone and moves the recommendation to what it measured.
  ```

- [ ] **Step 4: The Models alt text (line 32, third cell).**

  old:
  ```
  ![The Models screen: tiny, base, small (Recommended, selected), medium and large-v3 with sizes and Download buttons, and the storage footer](docs/screenshots/models.png)
  ```
  new:
  ```
  ![The Models screen: tiny, base, small (Recommended, selected), medium and large-v3 with sizes and Download buttons, the Benchmark this iPhone row, and the storage footer](docs/screenshots/models.png)
  ```

- [ ] **Step 5: Platform limitation 7 (line 255).**

  old:
  ```
  7. **Heat and battery.** Every model can be downloaded on every supported iPhone. ReVox recommends small by default (base below 4 GB); medium is in the suitable set from 6 GB, large-v3 from 8 GB; on 8 GB devices both medium and large-v3 carry a "long load time and heat" warning; models outside the suitable set for this iPhone are labelled "Not recommended for this iPhone" but are never hidden.
  ```
  new:
  ```
  7. **Heat and battery.** Every model can be downloaded on every supported iPhone. Until you run the benchmark ReVox recommends by memory size: small by default (base below 4 GB); medium is in the suitable set from 6 GB, large-v3 from 8 GB; on 8 GB devices both medium and large-v3 carry a "long load time and heat" warning. After **Benchmark this iPhone** it recommends the most accurate installed model that ran at least twice as fast as real time and loaded in under 10 s, and the Models screen says when it was measured; models outside the suitable set for this iPhone are labelled "Not recommended for this iPhone" but are never hidden.
  ```

- [ ] **Step 6: The "Which model?" table.** Insert after the last bullet of "Models and storage" (the anchor is the existing line beginning `- **Offline.** After the downloads finish, ReVox contacts no server at all.`) and before the `## Transcripts` heading, this block (one blank line before and after it):

  ```
  ### Which model?

  What to expect, from Argmax's published WhisperKit runs on iPhones — 10-minute files transcribed offline, so a speed factor rather than a per-phrase latency; iPhone 12 mini to iPhone 17 Pro, iOS 17 to 26, dashboard last updated 2025-10-17 — until your own benchmark replaces them:

  | Model | Published speed (× real time, slowest to fastest iPhone) | Published word error rate (mean of two test sets) | Notes |
  |---|---|---|---|
  | tiny | 27–94× | ≈ 16–18 % | The quickest and the roughest. |
  | base | 15–61× | ≈ 12–13 % | The recommendation below 4 GB. |
  | small | 7–21× | ≈ 8.7–9.1 % | The default; flagged with a warning on the iPhone 12 family. |
  | medium | not published | not published | No published iPhone run exists; the benchmark is the only number. |
  | large-v3 (the 947 MB build ReVox installs) | 1.4–2.3× | ≈ 24–29 % on long recordings, 4.6–4.9 % on clean read speech | A15 and later; the slowest and hottest. |

  Source: the WhisperKit Benchmarks dashboard on Hugging Face ([`argmaxinc/whisperkit-benchmarks`](https://huggingface.co/spaces/argmaxinc/whisperkit-benchmarks), `dashboard_data/performance_data.json` and `support_data.csv`); a warm load of an already-compiled model is under a second for small and one to two seconds for large-v3 in those runs, while the first load after an install compiles for the Neural Engine and takes longer. Short phrases in a live conversation carry a per-phrase overhead these batch figures do not show; **Benchmark this iPhone** measures that on your iPhone, and [docs/measurements/m11-model-benchmark.md](docs/measurements/m11-model-benchmark.md) carries the cited reference numbers as expectations, the recommendation thresholds, and the table the owner fills by pasting the app's shared text.
  ```

- [ ] **Step 7: Run the checks.**

  ```bash
  cd /home/user/ReVoxMobile && grep -q "### Which model?" README.md && grep -q "m11-model-benchmark.md" README.md && grep -q "Benchmark this iPhone row" README.md && echo ok && python3 /tmp/claude-0/-home-user/1059ed5c-2bd6-57ef-98c8-c2996914a65b/scratchpad/l7-check-links.py
  ```
  Expected: `ok` then `all relative links resolve`.

- [ ] **Step 8: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add README.md && git commit -m "docs(readme): Benchmark this iPhone and the published model expectations

First run points at Settings > Models > Benchmark this iPhone, the Models alt text names the
row, platform limitation 7 states the measured recommendation rule (twice real time, under
10 s to load), and a Which model? table quotes Argmax's published iPhone speed and word error
rate per model, pointing at docs/measurements/m11-model-benchmark.md for the cited numbers and
the owner's own results.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

### Task 6: The roadmap row, the repository-wide phrase check and the gates

- [ ] **Step 1: The failing check.** Run

  ```bash
  cd /home/user/ReVoxMobile && grep -q "^| 11 |" README.md && echo has-row-11
  ```
  Expected now: nothing (exit 1).

- [ ] **Step 2: The roadmap (lines 239–241).**

  old:
  ```
  | 10 | UI compaction, full review, README, first-run tutorial | **Current** |
  ```
  new:
  ```
  | 10 | UI compaction, full review, README, first-run tutorial | Done |
  | 11 | Grouped Live controls, You speak / They speak, tappable words, unsure phrases, the History bar, on-device benchmark, tutorial refresh | **Current** |
  ```

  Then, after the paragraph beginning `Milestone 9 was the owner's second round of fixes and improvements:` (keep it), insert a new paragraph:

  ```
  Milestone 11 is the owner's third round: the Live pills sit in three captioned rows, the two-way pair is named by the two people, a word in Learning mode opens its pronunciation and meaning, a phrase ReVox is unsure about stays greyed instead of vanishing, the Merge / Delete bar sits above the tab bar, **Benchmark this iPhone** measures the models on the phone in your hand, and the tutorial hosts the real controls.
  ```

- [ ] **Step 3: The phrase check across every user-facing document this lane owns or that CI publishes.** Run

  ```bash
  cd /home/user/ReVoxMobile && ! grep -rn -i -e "leave alone" -e "reply in" -e "don't translate" -e "skip a language" -e "left alone" README.md CONTRIBUTING.md docs/adr docs/testing.md docs/release.md docs/broadcast-bridge.md docs/measurements .github/ISSUE_TEMPLATE
  ```
  Expected: no output, exit 0. `docs/onboarding.md` is deliberately not in the list because lane L6 rewrites it; run `grep -n -i -e "reply in" -e "don't translate" docs/onboarding.md` as well and, if it still matches, say so in the handoff instead of editing it.

- [ ] **Step 4: The gates the executor runs before the last commit** (docs-only lane, but the rule is the rule; they must all exit 0):

  ```bash
  cd /home/user/ReVoxMobile && python3 scripts/dev/check-core-imports.py --all && python3 scripts/dev/check-test-autoclosures.py && python3 scripts/dev/check-tests-are-discoverable.py && bash scripts/ci/check-constant-coverage.sh && python3 /tmp/claude-0/-home-user/1059ed5c-2bd6-57ef-98c8-c2996914a65b/scratchpad/l7-check-links.py
  ```
  Also confirm no Swift file was touched: `git diff --name-only HEAD~5 -- '*.swift'` prints nothing, and `git status --short` shows nothing unstaged but `.claude/`.

- [ ] **Step 5: Commit.**

  ```bash
  cd /home/user/ReVoxMobile && git add README.md && git commit -m "docs(readme): milestone 11 on the roadmap

Row 10 is done, row 11 is current, and a paragraph lists what the third round of the owner's
fixes changed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017rNMt2Xns5wUvUYmLHyjKR"
  ```

**Cross-lane needs**
- L3 must have merged `docs/measurements/m11-model-benchmark.md` and the Models row **Benchmark this iPhone** before Task 5 runs; the README links to the file (the link checker fails otherwise) and the Models alt text names the row.
- L5 inserts `GuessesSettingsSection` into `SettingsView` (the Settings alt text of Task 1 describes the Unsure phrases toggle under Source language) and wires the tappable words into `LiveTranscriptRowView` (the live-running alt text says "tappable chips").
- L6 owns `docs/onboarding.md`, which still says "Don't translate / Reply in" on its line 3; the Task 6 grep reports it but this lane does not edit it. The tutorial alt text in Task 3 assumes L6's transcript page shows the greyed unsure line with its caption.
- `docs/measurements/m3-microphone-mode.md` rows 6 and 10 (per-phrase latency for base and small) are superseded by the M11 benchmark rows; no lane owns that file in §7, so the pointer "pending — superseded by m11" is left for the owner or the review step.
- The screenshots (`docs/screenshots/*.png`) are refreshed from the CI artifact at the milestone's final step; the alt texts written here describe the post-wave-2 screens, so they should be re-read against the refreshed images then (in particular whether the Your language header is visible in `settings.png`).