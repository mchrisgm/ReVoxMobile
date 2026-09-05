# Contributing to ReVox Mobile

Thanks for helping. This page covers how the project is built and tested, the gates that run before a change can merge, the commit convention, and the milestone pull-request flow. The design itself is in [the design spec](docs/superpowers/specs/2026-09-02-revox-mobile-design.md); the reasons behind the big decisions are the ADRs under [`docs/adr/`](docs/adr/).

## Building

**App and extension** need **Xcode 26 on macOS** and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate            # writes ReVoxMobile.xcodeproj from project.yml; the project is never committed
open ReVoxMobile.xcodeproj   # scheme ReVoxMobile
```

`xcodegen generate` also copies the committed `Package.resolved` into the generated project (`options.postGenCommand`), and CI builds with `-onlyUsePackageVersionsFromResolvedFile`, so the dependency graph is exactly the one in the repository — WhisperKit 1.1.0 and FluidAudio 0.15.6. The README's [build notes](README.md#for-developers) explain how to update a pin on purpose, how `REVOX_BUNDLE_PREFIX` defines every bundle identifier, and what signing a device build needs.

**`ReVoxCore`** needs no Xcode. It is a Foundation-only package that builds and tests with the Swift toolchain on macOS or Linux:

```bash
cd ReVoxCore && swift test
```

CI runs it in a `swift:6.3-noble` container and again on macOS inside the simulator job, so both Apple Foundation and swift-corelibs-foundation are exercised on every push ([ADR-0001](docs/adr/0001-foundation-only-core-package.md)).

## CI is the compiler for app targets

ReVox is authored on a Linux host with no Xcode. `ReVoxCore` compiles and tests there; `ReVoxMobile`, `ReVoxBroadcast` and `ReVoxMobileTests` do not, because they need the iOS SDK. For those targets the rule is:

1. Syntax-check the files you touched locally: `swiftc -parse path/to/File.swift`. This catches syntax only — it resolves no imports and cannot see an inexhaustive `switch`.
2. Run the gates in `scripts/dev` (below). They catch the compile errors `swiftc -parse` is known to miss.
3. Push. The `ios-simulator` job of [`ci.yml`](.github/workflows/ci.yml) is the compiler: it generates the project, resolves the pinned packages and runs `xcodebuild test` on an iPhone simulator. A change to an app target is done only when that run is green; a red run's `xcodebuild-log` artifact is the compiler output.

Keep pushes small. A macOS round takes minutes and bills at ten times the Linux rate, so when a class of compile error recurs, the fix is a new gate in `scripts/dev`, not a longer wait. See [ADR-0002](docs/adr/0002-ci-is-the-compiler.md).

If you *do* have a Mac with Xcode 26, build and test locally first; the CI rule still applies to what merges.

## Gates

Every gate is a script you can run from the repository root. They are grouped by where CI runs them.

### `scripts/dev` — the mistakes `swiftc -parse` cannot see (job `source-checks`, seconds)

| Script | What it catches |
|---|---|
| `python3 scripts/dev/check-core-imports.py --all` | A Swift file that uses a public `ReVoxCore` type without `import ReVoxCore`. Parses cleanly, fails to compile. |
| `python3 scripts/dev/check-test-autoclosures.py` | `await` inside an XCTest assertion's autoclosure argument, which never compiles; hoist the `await` into a `let` first. |
| `python3 scripts/dev/check-tests-are-discoverable.py` | `func test…` methods that XCTest will never run because of the class's shape or inheritance. |

### `scripts/ci` — design-spec invariants and packaging (jobs `core-linux`, `source-checks`, `ios-simulator`)

| Script | What it catches | Where |
|---|---|---|
| `bash scripts/ci/check-constant-coverage.sh` | A constant ported from the Windows sources that is no longer asserted, by name and value, in `ReVoxCoreTests` (spec §10.3). | `core-linux` |
| `bash scripts/ci/check-no-host-time.sh [--require-checkouts]` | Any host-time API (`hostTime`, `mach_absolute_time`, `mach_continuous_time`, `systemUptime`) in ReVox's sources or, with the flag, in the resolved package checkouts — it would require the SystemBootTime reasons in both privacy manifests (spec §11). | `core-linux`, `ios-simulator`, TestFlight |
| `bash scripts/ci/check-extension-surface.sh` | Anything the broadcast extension must never contain: CoreML, WhisperKit, FluidAudio, an audio engine or session, network, keychain, Swift concurrency, dispatch, per-buffer allocation, a second place that grows the ring file, or an entitlement beyond the App Group (spec §7.5, §11). | `core-linux` |
| `python3 scripts/ci/check-broadcast-bridge-doc.py` | A header table in [`docs/broadcast-bridge.md`](docs/broadcast-bridge.md) that disagrees with `RingHeader.Offset` in `ReVoxCore` (spec §5.9). | `source-checks` |
| `python3 scripts/ci/check-plists.py` | An incomplete or inconsistent Info.plist, privacy manifest or entitlements file in either target (spec §11, C7). | `source-checks`, `ios-simulator` |
| `python3 scripts/ci/check-package-resolved.py` | A resolved package graph that differs from the committed `Package.resolved` — a pin that drifted (spec E1). | `ios-simulator`, TestFlight |

The remaining scripts in `scripts/ci` are CI plumbing rather than gates: `select-xcode.sh`, `pick-simulator.sh`, `install-package-resolved.sh` and `collect-screenshots.sh` (which copies the README's screenshots out of the simulator; [ADR-0009](docs/adr/0009-screenshots-rendered-by-ci.md)).

Run the whole Linux-side set before pushing:

```bash
(cd ReVoxCore && swift test)
bash scripts/ci/check-constant-coverage.sh
bash scripts/ci/check-no-host-time.sh
bash scripts/ci/check-extension-surface.sh
python3 scripts/dev/check-core-imports.py --all
python3 scripts/dev/check-test-autoclosures.py
python3 scripts/dev/check-tests-are-discoverable.py
python3 scripts/ci/check-broadcast-bridge-doc.py
python3 scripts/ci/check-plists.py
```

## Tests

- **`ReVoxCoreTests`** mirror the Windows tests one-to-one, including the backpressure and drop-marker cases. Time goes through an injected `sleep`; audio is `[Float]`; nothing touches the wall clock, a microphone or a model. Add the core test first, make it pass on Linux, then write the adapter.
- **`ReVoxMobileTests`** test the adapters and screens on the simulator with injected fakes; no test downloads anything or needs a model. Tests that can only be measured on an iPhone live in `DeviceMeasurementTests` and skip themselves on the simulator.
- Anything that can only be confirmed on a real device gets a row in [`docs/measurements/`](docs/measurements/) with the procedure, the log line to look for and the pass criterion; until someone runs it, the row says `pending`. Do not mark a row measured without the evidence it asks for.

## Commits

Commit subjects use conventional prefixes, optionally scoped, as the log does:

| Prefix | Use |
|---|---|
| `feat:` / `feat(core):` / `feat(app):` | New behaviour |
| `fix:` / `fix(live):` / `fix(settings):` | A bug, with the cause in the body |
| `test:` / `test(screens):` | Tests only |
| `docs:` / `docs(readme):` | Documentation, screenshots, measurement records |
| `ci:` | Workflows and CI scripts |
| `build:`, `chore:` | Packaging, pins, housekeeping |

Write the body for the reader who finds the commit in `git blame`: what changed and why, in prose. Never put a model identifier or an AI product name in a commit, a source file or a doc.

## Pull requests

Work happens on **milestone branches** (`milestone/<n>-<name>`) cut from `main`; each milestone ends in one pull request titled after it ("Merge milestone 9: …"), merged as a merge commit rather than squashed, so the milestone's commits stay readable in the log. Smaller fixes can go in their own PR. Every PR:

1. Is green on `ci.yml` — all three jobs.
2. Fills in the [pull-request template](.github/pull_request_template.md): what, why, and how it was verified, with the CI run id and, for anything device-only, the measurement row it filled in or left `pending`.
3. Updates the docs its change touches: the README for user-visible behaviour, `docs/broadcast-bridge.md` for the ring contract, a measurement record for ASSUMED items, a new ADR for a new decision (never edit an old one; supersede it).
4. Refreshes `docs/screenshots/` from the `screenshots` artifact when a screen changed.

Merging to `main` ships a TestFlight build ([ADR-0008](docs/adr/0008-testflight-on-every-merge.md)); that is intended for milestone-sized merges, so batch small changes rather than merging them one by one.

## Reporting problems

Use the [bug report](.github/ISSUE_TEMPLATE/bug_report.md) or [feature request](.github/ISSUE_TEMPLATE/feature_request.md) templates. For a TestFlight build, the in-app feedback path in [docs/testing.md](docs/testing.md) attaches the device, iOS version and build number for you.
