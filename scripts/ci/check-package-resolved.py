#!/usr/bin/env python3
"""Guards the committed Package.resolved (spec E1, §11).

1. The two pinned products are at their exact spec versions.
2. Every pin — including transitive ones such as swift-argument-parser — carries an explicit revision.
3. When the generated project holds a resolved file too, it is identical to the committed one, so a resolve that
   drifted fails the build instead of entering it silently.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
COMMITTED = ROOT / "Package.resolved"
GENERATED = ROOT / "ReVoxMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
REQUIRED_VERSIONS = {"whisperkit": "1.1.0", "argmax-oss-swift": "1.1.0", "fluidaudio": "0.15.6"}
REVISION = re.compile(r"^[0-9a-f]{40}$")


def pins(path):
    data = json.loads(path.read_text())
    return {pin["identity"]: pin.get("state", {}) for pin in data.get("pins", [])}


def fail(message):
    print(f"::error::{message}")
    return 1


def main():
    if not COMMITTED.exists():
        return fail("Package.resolved is not committed; copy it from a green CI run (M7 Task 95, step 1)")
    status = 0
    committed = pins(COMMITTED)
    if not committed:
        return fail("Package.resolved has no pins")
    for identity, state in sorted(committed.items()):
        revision = state.get("revision", "")
        if not REVISION.match(revision):
            status = fail(f"pin {identity} has no 40-hex revision (got {revision!r})")
        expected = REQUIRED_VERSIONS.get(identity)
        if expected and state.get("version") != expected:
            status = fail(f"pin {identity} must stay at {expected}, found {state.get('version')!r}")
    found = {i for i in committed if i in REQUIRED_VERSIONS}
    if not found:
        status = fail("neither WhisperKit nor FluidAudio is pinned in Package.resolved")
    if GENERATED.exists() and GENERATED.read_text() != COMMITTED.read_text():
        status = fail(
            "the generated project's Package.resolved differs from the committed one: a dependency drifted. "
            "Review the change, then commit it with "
            "`cp ReVoxMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Package.resolved`"
        )
    if status == 0:
        print(f"Package.resolved: {len(committed)} pins, all revision-locked; WhisperKit and FluidAudio at their spec versions.")
    return status


if __name__ == "__main__":
    sys.exit(main())
