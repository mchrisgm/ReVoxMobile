# ADR-0009: The README's screenshots are rendered by CI from the real views

## Status

Accepted

## Date

2026-09-04 (milestone 8, commit "test(screens): render the README's screenshots from the real views"); recorded 2026-09-04.

## Context

A README with screenshots is the first thing a tester or contributor sees, and hand-taken screenshots drift: the Live screen gained quick controls, Learning rows and ages in milestone 9 alone. There is no Xcode in the authoring environment ([ADR-0002](0002-ci-is-the-compiler.md)), so nobody can take a simulator screenshot by hand there either.

## Decision

`ScreenshotTests` (in `ReVoxMobileTests`) hosts each screen in a 393 × 852-point window — iPhone 15/16 portrait — with view models put into an exact state, renders it to a PNG in the host app's Documents folder, and the `ios-simulator` job copies the images out of the simulator's app container with `scripts/ci/collect-screenshots.sh` and uploads them as the `screenshots` artifact. It is a unit test, not a UI test, for the same reason `ScreenHostingTests` is one: the state is injected, so no simulator automation is needed to reach it. The step is best effort by design (`if: always()`, exits 0 on failure): no screenshot is worth failing a build over. The six images in `docs/screenshots/` are the artifact of a green run, committed as a docs change.

## Consequences

- Every image in the README shows the real view at the commit that rendered it; a caption can describe exactly what is in the image.
- A screen change is followed by a screenshot refresh from the artifact, not by a manual capture.
- The screenshots show the simulator's state, so figures like "Free: 50.0 GB" and "under 1 MB" are the simulator's, and the model rows show "Download" rather than an installed model.

## Sources

- [`ReVoxMobileTests/ScreenshotTests.swift`](../../ReVoxMobileTests/ScreenshotTests.swift) (the class docstring).
- [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) (steps "Collect screenshots" and "Upload screenshots"); [`scripts/ci/collect-screenshots.sh`](../../scripts/ci/collect-screenshots.sh).
- README, the note under the feature grid; the `docs: milestone 9 screenshots` commit.
