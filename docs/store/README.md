# App Store screenshots

The App Store listing shows six screenshots. Each is a poster with one claim in the app's own words and the real screen, whole, beneath it: no device bezel, no gradient, no stock imagery, no fabricated status bar, nothing composited over a screen it was not opened from. This page explains where the pieces live, how a set is produced after a CI run, and how to add or reword a frame.

## What is where

| Path | What it is |
|---|---|
| `store/screenshots.json` | The frames, in order, with their copy: an `id` (the output file name), the `capture` shown, a `headline` and a `subline`. Copy only; nothing about colour, type or geometry. |
| `scripts/store/compose-screenshots.py` | The compositor. Python 3 standard library plus a Chromium or Chrome binary. Holds the inks, the type and the geometry. |
| `store/fonts/` | Inter 4, Medium (500) and ExtraBold (800), the two weights the panel uses, with the SIL Open Font License in `OFL.txt`. |
| `docs/store/screenshots/` | The composed set, `01-….png` to `06-….png`, 1290 × 2796 px each. Committed after a CI run, never produced by CI itself. |
| `ReVoxMobileTests/ScreenshotTests.swift`, `OnboardingScreenshotTests.swift` | Where the captures come from: every screen is rendered by CI at the README's size and at the App Store size, through `ReVoxMobileTests/Support/ScreenCapture.swift`. |

## The set

Two inks, whole screen. The panels alternate the app's teal (`#12788C`) and a warm off-white (`#F6F4EF`), by position: odd frames teal, even frames off-white. Under a short rule in the other ink, the headline (Inter 800, 136 px) and the subline (Inter 500, 50 px) sit at the top left; the capture sits beneath them at 950 px wide, centred, its corners rounded like the display, with a hairline stroke and two soft shadows so the white Live screens and the grey grouped screens keep an edge on both inks. Read in order, the headlines are what a first session does.

| Frame | Ink | Capture | Headline |
|---|---|---|---|
| 01 | teal | `live-running` | Hear it in English. |
| 02 | off-white | `onboarding-welcome` | Nothing leaves the phone. |
| 03 | teal | `live-running-other-apps` | Listen to other apps. |
| 04 | off-white | `live-idle` | Reply in their language. |
| 05 | teal | `history-selecting` | Keep every conversation. |
| 06 | off-white | `learning-word` (close-up) | Tap a word. Learn it. |

Frame 06 breaks the phone rhythm on purpose. The word popover's content is something CI can only render on its own, on an otherwise empty page, so the frame shows it as a close-up card at the same width rather than as a mostly blank phone. The crop is expressed in points in the script (`CLOSE_UP`), so it holds for both capture sizes; if `testCapturesTheLearningWordPopover` changes the card's width or its top padding, update it.

Frame 03 names a stand-in. If `live-running-other-apps.png` is ever missing from the artifact, the compositor uses `benchmark.png` with its own headline and subline (both in the JSON, under `fallback`) and prints a note. No other frame has one: a missing capture without a fallback stops the run.

## From a CI run to the listing

1. **CI renders the captures.** The `ios-simulator` job runs `ScreenshotTests` and `OnboardingScreenshotTests`, which write every screen twice into the host app's Documents: `screenshots/` at 393 × 852 points @2x (786 × 1704 px, the README's) and `store-screenshots/` at 430 × 932 points @3x (1290 × 2796 px, App Store Connect's 6.9-inch slot, exactly). The test asserts each PNG's pixel size and that neither render is blank. `scripts/ci/collect-screenshots.sh` copies both folders out of the simulator and the job uploads them as the `screenshots` and `store-screenshots` artifacts, kept for seven days.
2. **Fetch the artifact** from a green run of the branch you are shipping: from the run's page on GitHub, or `gh run download <run id> -n store-screenshots -D store-screenshots`.
3. **Compose.**

   ```bash
   python3 scripts/store/compose-screenshots.py --input store-screenshots \
     --spec store/screenshots.json --output docs/store/screenshots
   ```

   The script needs a Chromium or Chrome. It looks at `--chrome`, then `$CHROME`, then `/opt/pw-browsers/chromium-*/chrome-linux/chrome`, `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`, `google-chrome` and `chromium`. Each frame becomes an HTML panel with the capture and the fonts embedded as data URIs, rendered with `--headless=new --window-size=1290,2796 --force-device-scale-factor=1 --screenshot`. Each output is read back and refused unless it is exactly 1290 × 2796; a PNG with an alpha channel is rewritten as RGB, because App Store Connect refuses alpha.
4. **Look at every PNG.** The headline and the subline must each fit in two lines, nothing in the capture may be cut, and the copy must still be true of the screen under it (see below). `--keep-panels DIR` keeps the HTML panels for inspection; `--frame <id>` composes one frame.
5. **Commit** the six PNGs under `docs/store/screenshots/` with a `docs(store):` prefix, naming the CI run they came from.
6. **Upload** them to App Store Connect in the 6.9-inch iPhone slot, in file-name order. App Store Connect uses that set for the smaller iPhones when no other set is uploaded.

To check the toolchain without an artifact, `python3 scripts/store/compose-screenshots.py --self-test` composes synthetic 1290 × 2796 captures into a temporary folder and checks the sizes, the fallback, the refusal of a missing capture, the README-size input, that Chromium set the copy in the bundled fonts, and the alpha strip.

The README's own renders in `docs/screenshots/` are accepted as input too, for a preview: they are the same screens at 786 × 1704 and are upscaled, so the script prints a note and the shipped set is composed from the artifact.

## Adding or rewording a frame

Edit `store/screenshots.json`. A frame needs an `id` (the output file name; keep the two-digit prefix so the files sort in order), a `capture` (the name of a PNG `ScreenshotTests` writes, without the extension), a `headline` and a `subline`. Optional: `"presentation": "close-up"` for the popover treatment, and a `fallback` object with its own `capture`, `headline` and `subline`. Insert a frame where it belongs in the order; the inks re-alternate by position, so nothing else changes. If the set must shrink, drop frame 03 (or its stand-in) first, then 06, then 04, and keep the rest in order.

A new capture is a new call in `ScreenshotTests.testCapturesEveryScreenInTheReadme` (or the onboarding test), built the way the others are: a view model put into an exact state, then `capture("<name>", …)`. Both sizes come for free. The capture names the JSON refers to are the same names the README uses, so a renamed capture must be renamed in both places.

The copy is checked by reading it against the PNG under it, and the script refuses an em-dash or a manual line break. What it must be:

- **Literally true of the app as it is today, and of the screen it sits on.** The captions are the screen's own words wherever possible ("Nothing leaves the phone." is on the welcome screen). ReVox translates into English only; the reply direction and word meanings use Apple's translation on iOS 18, so a claim about either says "on iOS 18" or "from iOS 18". It cannot capture phone or FaceTime call audio, and some players (Safari, Music, some video apps) deliver silence to a broadcast, so frame 03 promises the mechanism (a screen broadcast you start), not any particular app. The first use needs a model download (small is about 487 MB, base about 147 MB, tiny under 80 MB); no screen says so, so that belongs in the App Store description, not on a panel.
- **Plain, British, specific.** Sentence case, a full stop, no marketing superlatives that cannot be defended, no product or company names other than ReVox's own. Headlines of three to five words; sublines of ten to twelve.
- **Two lines at most, each.** Inter 800 at 136 px with -4 px tracking wraps every current headline to exactly two lines inside 1050 px; Inter 500 at 50 px wraps every subline to two. A longer line pushes nothing (the capture never moves), it simply overlaps it, which the check in step 4 catches.

## The panel

Everything below is in the script, not the JSON, so a reworded frame cannot drift the design.

- **Canvas** 1290 × 2796 px, sRGB, PNG without alpha. Flat, full-bleed ink: teal `#12788C` or off-white `#F6F4EF`; no gradient, noise, vignette, logo or app name.
- **Rule** at (170, 140), 96 × 8 px, square corners, in the other ink.
- **Headline** Inter 800, 136 / 140 px, letter-spacing -4 px, white on teal (5.1:1) or `#0F2A30` on off-white (13.7:1), left-aligned at x = 170, max-width 1050 px, top-anchored at y = 176.
- **Subline** Inter 500, 50 / 62 px, letter-spacing -0.5 px, `#D4E7EA` on teal (4.0:1) or `#4A5B60` on off-white (6.5:1), 28 px under the headline box.
- **Screen** the whole capture scaled to 950 × 2060 at (170, 672), corners 120 px, a 1.5 px inside stroke (`#FFFFFF47` on teal, `#0F2A301A` on off-white), shadows `0 48px 120px` and `0 8px 24px` (black at 40 and 30 percent on teal, `#0F2A30` at 20 and 13 percent on off-white). The capture keeps its own background: no tint, no overlay, no added status bar. Its bottom lands at y = 2732, so the Start and Stop capsules, History's Merge and Delete bar and the tab bar are always in shot.
- **Close-up** (frame 06) the popover's card cropped with about 32 points of the capture's own white around its content, scaled to 950 wide, centred vertically in the band the phone occupies on the other frames, corners 96 px, the same stroke and shadows.
- **Fonts** Inter 4 from the project's GitHub releases, `web/Inter-Medium.woff2` and `web/Inter-ExtraBold.woff2` copied to `store/fonts/` with the licence. The fallback stack is the system sans, so a panel still reads if the files are missing, but the wraps above were measured with Inter; the self-test checks that Chromium used it.
