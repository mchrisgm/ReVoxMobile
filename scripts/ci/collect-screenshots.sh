#!/usr/bin/env bash
# Copy the PNGs `ScreenshotTests` and `OnboardingScreenshotTests` wrote into the host app's Documents out of the
# simulator: `Documents/screenshots` (the README's 786 x 1704 renders) and `Documents/store-screenshots` (the
# 1290 x 2796 renders behind the App Store set, see docs/store/README.md).
#
# The tests write them inside the app container because that is the one directory a simulator app is certain to be
# able to write to. Two ways back out, because `simctl get_app_container` needs the app to still be registered
# after the test run and silently returns nothing when it is not: ask simctl first, then look directly in the
# device's data directory, which is a plain directory on the runner's disk.
#
# Usage: collect-screenshots.sh [destination] [bundle id] [output dir] [store output dir]
#
# Best effort by design: no screenshot is worth failing a build over, so every failure prints and exits 0.
set -uo pipefail

destination="${1:-}"
bundle_id="${2:-com.mchrisgm.revox}"
output="${3:-screenshots}"
store_output="${4:-store-screenshots}"

udid="${destination##*id=}"
udid="${udid%%,*}"
if [ -z "$udid" ] || [ "$udid" = "$destination" ]; then
  udid=$(xcrun simctl list devices booted -j | jq -r '[.devices[][]] | .[0].udid // empty')
fi
if [ -z "$udid" ]; then
  echo "no simulator to collect screenshots from"
  exit 0
fi
echo "collecting from $udid ($bundle_id)"

documents=""

container=$(xcrun simctl get_app_container "$udid" "$bundle_id" data 2>&1) || {
  echo "simctl get_app_container: $container"
  container=""
}
if [ -n "$container" ] && [ -d "$container/Documents/screenshots" ]; then
  documents="$container/Documents"
fi

# The device's data directory, when the app is no longer registered with simctl.
if [ -z "$documents" ]; then
  device_root="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Containers/Data/Application"
  found=$(find "$device_root" -maxdepth 3 -type d -name screenshots 2>/dev/null | head -n 1)
  if [ -n "$found" ]; then
    documents=$(dirname "$found")
    echo "found them under the device's data directory"
  fi
fi

if [ -z "$documents" ]; then
  echo "no screenshots directory found; the app container holds:"
  [ -n "$container" ] && ls -la "$container" "$container/Documents" 2>/dev/null
  exit 0
fi

# copy <folder under Documents> <output dir>
copy() {
  local source="$documents/$1"
  if [ ! -d "$source" ]; then
    echo "no $1 directory in $documents"
    return 0
  fi
  mkdir -p "$2"
  cp -R "$source/." "$2/" || true
  ls -l "$2" || true
}

copy screenshots "$output"
copy store-screenshots "$store_output"
