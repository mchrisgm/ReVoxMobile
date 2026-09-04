# ADR-0002: CI is the compiler for the app and extension targets

## Status

Accepted

## Date

Set in the implementation plan of 2026-09-02; recorded 2026-09-04.

## Context

The environment in which ReVox Mobile is authored is a Linux host with a Swift toolchain and no Xcode. `ReVoxCore` builds and tests there, but the `ReVoxMobile`, `ReVoxBroadcast` and `ReVoxMobileTests` targets need the iOS SDK, SwiftUI, CoreML, AVFoundation and the two pinned packages, none of which exist on Linux. The only check available locally for those sources is `swiftc -parse`, which verifies syntax and nothing more: it resolves no imports, sees no inexhaustive `switch`, and accepts `await` inside an XCTest autoclosure that can never compile.

## Decision

The app and extension targets are compiled **only by CI**. Every change to them is syntax-checked locally with `swiftc -parse`, pushed, and considered done only when the `ios-simulator` job of `ci.yml` is green: it generates the project with XcodeGen, resolves the pinned packages, and runs `xcodebuild test` on an iPhone simulator with Xcode 26.

Because a macOS round costs minutes and bills at ten times the Linux minute rate, the mistakes that `swiftc -parse` is known to miss are caught earlier by small Python gates that run in seconds on a bare Ubuntu runner (`source-checks` job) and can be run locally:

| Gate | What it catches |
|---|---|
| `scripts/dev/check-core-imports.py` | A file that uses a public `ReVoxCore` type without `import ReVoxCore` — parses cleanly, fails to compile. |
| `scripts/dev/check-test-autoclosures.py` | `await` inside an XCTest assertion's autoclosure argument, which never compiles. |
| `scripts/dev/check-tests-are-discoverable.py` | `func test…` methods XCTest will never run (wrong class shape or inheritance). |

## Consequences

- Work on app targets is done in small pushes; a red simulator run is the compile error, read from the build log artifact.
- Compile errors the gates cannot see (an inexhaustive `switch` after a new enum case, for example) still cost a full macOS round; when one recurs, the fix is a new gate, not a bigger local toolchain.
- The core package stays the place where logic is proven, because that is where a test can be run before it is pushed ([ADR-0001](0001-foundation-only-core-package.md)).
- The `ios-simulator` job is also what renders the README's screenshots ([ADR-0009](0009-screenshots-rendered-by-ci.md)), so it is the single source of the app's compiled truth.

## Sources

- Implementation plan [global constraints](../superpowers/plans/2026-09-02-revox-mobile.md): "App and extension targets compile only in CI: there is no Xcode on the Linux host … the task is done only when the run is green".
- [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) (jobs `source-checks` and `ios-simulator`, and the comment "Two compile errors that swiftc -parse cannot see, so they otherwise cost a full macOS round each").
- The docstrings of [`scripts/dev/check-core-imports.py`](../../scripts/dev/check-core-imports.py), [`scripts/dev/check-test-autoclosures.py`](../../scripts/dev/check-test-autoclosures.py) and [`scripts/dev/check-tests-are-discoverable.py`](../../scripts/dev/check-tests-are-discoverable.py).
