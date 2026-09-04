#!/usr/bin/env bash
# Copy the PNGs `ScreenshotTests` wrote into the host app's Documents out of the booted simulator.
#
# The test writes them inside the app container because that is the one directory a simulator app is certain to
# be able to write to; `simctl get_app_container` is how the runner reaches it afterwards. Best effort by
# design: no screenshot is worth failing a build over, so every failure here prints and exits 0.
set -uo pipefail

destination="${1:-}"
bundle_id="${2:-com.mchrisgm.revox}"
output="${3:-screenshots}"

udid="${destination##*id=}"
udid="${udid%%,*}"
if [ -z "$udid" ] || [ "$udid" = "$destination" ]; then
  udid=$(xcrun simctl list devices booted -j | jq -r '[.devices[][]] | .[0].udid // empty')
fi
if [ -z "$udid" ]; then
  echo "no booted simulator to collect screenshots from"
  exit 0
fi

container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data 2>/dev/null || true)
if [ -z "$container" ] || [ ! -d "$container/Documents/screenshots" ]; then
  echo "no screenshots in $bundle_id's container on $udid"
  exit 0
fi

mkdir -p "$output"
cp -R "$container/Documents/screenshots/." "$output/" || true
ls -l "$output" || true
