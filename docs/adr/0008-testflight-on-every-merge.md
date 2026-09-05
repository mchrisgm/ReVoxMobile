# ADR-0008: Every merge to `main` ships a TestFlight build

## Status

Accepted (the owner's decision, reinstated deliberately)

## Date

2026-09-04 (commit "ci: every merge to main ships a TestFlight build"); recorded 2026-09-04.

## Context

ReVox Mobile is delivered to testers through TestFlight, and the only proof that a milestone works is a build on a real iPhone. A TestFlight upload needs a macOS runner to archive, test, export and upload, and a macOS runner bills at **ten times** the minute rate — roughly 200 billed minutes per run — on top of the macOS job `ci.yml` already runs for every push on every branch. A push-to-`main` trigger existed before, was removed after it exhausted the account's Actions allowance twice (two runs died in seconds with no readable log — a job that was never started), and the question was whether to bring it back.

## Decision

`testflight.yml` runs on **every push to `main`** — in practice every merged pull request — and also on a `v*` tag and on demand from the Actions tab, where the signing path (automatic via the App Store Connect API key, or manual with a certificate and profiles from secrets) can be chosen. The push trigger names `main` and nothing else. Two jobs: `preflight` (Linux, seconds) checks that the four App Store Connect secrets exist and, if any is missing, prints a notice and skips the upload so the workflow stays green; `upload` (macOS, up to 90 minutes) generates the project, resolves the pinned packages, runs the full test suite (a failure blocks the upload), archives, exports, and uploads with `xcodebuild -exportArchive` (`destination = upload`), which returns a real exit code where `altool` did not. A `concurrency` group keeps two merges in quick succession from archiving in parallel.

## Consequences

- Testers get a build for every milestone merge without anyone running Xcode; the build number is the workflow run number.
- The cost is affordable at milestone-sized merges and **would not be at per-push frequency**; if the allowance runs short again, the first thing to reconsider is `ci.yml`'s macOS job on every branch, not this trigger.
- The workflow, the Apple setup, the secrets and the troubleshooting are documented for the repository owner in `docs/release.md`; the tester-facing guide is `docs/testing.md`.

## Sources

- [`docs/release.md`](../release.md), "What the workflow does" and "What it costs".
- [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml) (the header comment and the `on:` block).
- README, "Delivery".
