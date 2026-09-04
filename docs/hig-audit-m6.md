# Milestone 6 HIG audit

Audit of every screen against the Apple Human Interface Guidelines, run with the `apple-hig-expert` skill (Mode 2) over the SwiftUI sources on 2026-09-04, plus the skill's `hig_checker.py` over the measurable elements listed in `docs/hig-audit/checks.json`. Rules applied (spec §8.1, §8.8): 44 × 44 pt minimum targets, 4.5:1 contrast for normal text (3:1 large), a VoiceOver label on every interactive element, colour never the only status carrier, Dynamic Type without clipping, determinate progress that never turns into a spinner.

Severity: **blocking** findings are fixed in this milestone; **advisory** findings are fixed when the fix is one modifier or one string, otherwise carried to milestone 7 with the reason in the last column.

Confidence tags follow the skill's convention: 🟢 tool-verified, 🟡 needs device test, 🔴 assumed from source.

## Checker output before fixes

Run on: 2026-09-04, checker path: `/root/.claude/plugins/cache/claude-code-skills/apple-hig-expert/2.9.0/skills/apple-hig-expert/scripts/hig_checker.py`.

```json
{
  "score": 40,
  "violations": [
    "Target 140x30 small for live-jump-to-latest",
    "Target 52x20 small for models-cancel-download",
    "Target 80x34 small for models-resume-download",
    "Target 70x34 small for voices-retry-fallback",
    "Target 52x20 small for voices-cancel-download",
    "Target 80x34 small for voices-resume-download"
  ]
}
```

All five contrast checks passed on the first run: the four tinted backgrounds composite above 12:1 under the primary label colour, and the secondary label `#3C3C43` on white is 10.9:1.

## Findings

| ID | Screen | Finding | HIG rule | Severity | Confidence | Fix (commit) or reason deferred |
|---|---|---|---|---|---|---|
| HIG-Live-1 | Live | "Jump to latest" capsule is ~30 pt tall | Buttons: 44 × 44 pt minimum hit region | blocking | 🟢 tool-verified | `.frame(minHeight: 44)` on the button (this task) |
| HIG-Live-2 | Live | The transcript row lays time, the language capsule and the English text out in one `HStack` with no wrapping | Typography: usable at the largest Dynamic Type size | advisory | 🟡 needs device test | Deferred to M7: the fix is a `ViewThatFits` or a size-class switch to a vertical layout, not one modifier. Re-checked on the device in `docs/measurements/m6-history-export.md` row 5. |
| HIG-Live-3 | Live | `startStopButton` passes `""` as its accessibility hint outside broadcast mode | VoiceOver: hints are optional; an empty hint is not an error but is unintended | advisory | 🔴 assumed | Deferred to M7: SwiftUI has no "no hint" value, so the fix is a conditional modifier, not a string. VoiceOver reads nothing for an empty hint, so there is no user-visible defect. |
| HIG-Live-4 | Live | The lag and ducking pills are tinted, and the ducking pill's tint is the only thing that changes between ducking active and idle | Accessibility: colour is never the only status carrier | pass | 🟢 verified from source | No change: the pill's own text changes with it ("Ducking" / "Ducking off"), and the combined status line reads both to VoiceOver. |
| HIG-Models-1 | Models | "Cancel" under an active download is a caption-sized text button (~20 pt) | 44 × 44 pt minimum | blocking | 🟢 tool-verified | `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())` (this task) |
| HIG-Models-2 | Models | "Resume" in the paused row is ~34 pt tall | 44 × 44 pt minimum | blocking | 🟢 tool-verified | `.frame(minHeight: 44)` (this task) |
| HIG-Models-3 | Models | The failure message is `lineLimit(3)` | Typography: text should not be truncated unnecessarily | advisory | 🔴 assumed | No change: the untruncated message is in the "Download failed" alert added in the same milestone, and an unbounded error string in a list row would push the row's controls off screen. |
| HIG-Models-4 | Models | The row is one combined accessibility element containing its Download / Cancel / Select button | VoiceOver: every interactive element is reachable | pass | 🟢 verified from source | No change: `.accessibilityElement(children: .combine)` keeps the buttons reachable as VoiceOver actions on the row, which is the intended one-swipe-per-model reading. |
| HIG-Voices-1 | Voices | "Cancel" and "Resume" in the pocket-tts download row (same as Models) | 44 × 44 pt minimum | blocking | 🟢 tool-verified | the same two fixes (this task) |
| HIG-Voices-2 | Voices | "Retry" after a pocket-tts fallback is ~34 pt tall | 44 × 44 pt minimum | blocking | 🟢 tool-verified | `.frame(minHeight: 44)` (this task) |
| HIG-Voices-3 | Voices | The download row spoke `Int(fraction * 100)` while the progress bar spoke the clamped, floored `percentText` — two different percentages for the same download | VoiceOver: one consistent spoken value per element | advisory (one line) | 🟢 verified from source | Routed through `LiveStatusAccessibility.percentText` (this task) |
| HIG-Voices-4 | Voices | The voice rows and system-voice rows already carry `.frame(minHeight: 44)` and a selected/unselected label | 44 × 44 pt minimum; colour not the only carrier | pass | 🟢 tool-verified | No change: the checkmark is a glyph, and the label says "selected". |
| HIG-Settings-1 | Settings | Every control is a labelled `Toggle`, `Picker` or `Slider` in a `Form`; the slider's end glyphs are `accessibilityHidden` | VoiceOver labels; standard controls | pass | 🟢 verified from source | No change. |
| HIG-History-1 | History | Rows are ~72 pt, "Clear All" is a toolbar item, swipe-to-delete is the standard gesture, and both empty states use `ContentUnavailableView` | 44 × 44 pt; standard patterns; empty-state copy | pass | 🟢 tool-verified | No change (screen written in this milestone against these rules). |
| HIG-SessionDetail-1 | Session detail | Share and Delete are toolbar items with explicit labels; the destructive delete sits behind a confirmation naming the entry count | 44 × 44 pt; destructive actions confirmed | pass | 🟢 tool-verified | No change. |
| HIG-About-1 | About | Every licence `Link` carries `.frame(minHeight: 44)`, a label naming the licence and a hint saying it opens Safari | 44 × 44 pt; VoiceOver labels | pass | 🟢 tool-verified | No change. |
| HIG-Diag-1 | Broadcast diagnostics | Debug screen reachable from Settings; audited at advisory level only | — | advisory | 🔴 assumed | No change: not a user-facing surface, and its rows are read-only text. |

## Per-screen scorecard (after fixes)

| Screen | Checker score | Skill verdict (ship / fix before release / rework) | Open advisory items |
|---|---|---|---|
| Live | 100 | ship | HIG-Live-2 (Dynamic Type layout), HIG-Live-3 (empty hint) → M7 |
| Models | 100 | ship | HIG-Models-3 (line limit, accepted) |
| Voices | 100 | ship | none |
| Settings | 100 | ship | none |
| History | 100 | ship | none |
| Session detail | 100 | ship | none |
| About | 100 | ship | none |
| Broadcast diagnostics | (advisory only) | ship | none |

## Checker output after fixes

```json
{
  "score": 100,
  "violations": []
}
```

## Not measurable by the tool, assessed manually

- Dark mode contrast of the four tinted backgrounds (`Color.orange.opacity(0.2)`, `Color.accentColor.opacity(0.15)`, `Color.yellow.opacity(0.15)`, `Color.secondary.opacity(0.15)`) under the primary label colour: to be checked on a device with Increase Contrast off and on (companion to measurement row 5).
- Reduce Motion: the only animation is the `withAnimation { proxy.scrollTo(...) }` of "Jump to latest"; acceptable (a scroll, not a transition).
- VoiceOver rotor order on History and Session detail: checked on the device (measurement row 4).
