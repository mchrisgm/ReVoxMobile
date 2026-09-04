## What

<!-- What changed, in the words a reader of `git log` will need. Which targets: ReVoxCore / ReVoxMobile / ReVoxBroadcast / tests / docs / CI. -->

## Why

<!-- The problem or the milestone item this closes. Link the design spec section (docs/superpowers/specs/…), the ADR (docs/adr/…) or the measurement row it follows from. A new decision gets a new ADR; an old one is superseded, never edited. -->

## How verified

- **CI run id:** <!-- the green `ci.yml` run for the head commit; for app-target changes this run *is* the compiler (docs/adr/0002-ci-is-the-compiler.md) -->
- **Tests added or changed:** <!-- names; core tests first, on Linux -->
- **Gates run locally:** <!-- e.g. swift test, check-core-imports, check-test-autoclosures, check-no-host-time -->
- **Device measurement:** <!-- For anything that can only be confirmed on an iPhone: the docs/measurements row you filled in, with device model and iOS version — or the row you added and left `pending`, and why. "Not applicable" if nothing in this change is device-only. -->
- **Docs touched:** <!-- README section, docs/broadcast-bridge.md, measurement record, ADR, screenshots refreshed from the `screenshots` artifact -->

## Checklist

- [ ] `ci.yml` is green on the head commit (all three jobs)
- [ ] No host-time API, no model in the extension, no new network path (the gates pass)
- [ ] Every user-visible change is described in the README
- [ ] No model identifier or AI product name in any committed file
