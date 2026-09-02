#!/usr/bin/env bash
# Print "destination=platform=iOS Simulator,id=<udid>" for an available iPhone
# simulator on the newest installed iOS runtime, suitable for $GITHUB_OUTPUT.
set -euo pipefail

devices=$(xcrun simctl list devices available -j)
udid=$(printf '%s' "$devices" | jq -r '
  .devices
  | to_entries
  | map(select(.key | test("SimRuntime\\.iOS-")))
  | sort_by(.key | capture("iOS-(?<major>[0-9]+)-(?<minor>[0-9]+)") | [(.major | tonumber), (.minor | tonumber)])
  | reverse
  | map(.value[] | select(.name | test("^iPhone")))
  | .[0].udid // empty')

if [ -z "$udid" ]; then
  echo "::error::No available iPhone simulator found" >&2
  xcrun simctl list devices available >&2
  exit 1
fi

name=$(printf '%s' "$devices" | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .name')
echo "Using simulator: $name ($udid)" >&2
echo "destination=platform=iOS Simulator,id=$udid"
