#!/usr/bin/env bash
# Select the pinned Xcode on a GitHub macOS runner, falling back to the newest
# Xcode with the same major version if the image no longer ships the pinned one.
# Usage: scripts/ci/select-xcode.sh 26.6
set -euo pipefail

want=${1:?usage: select-xcode.sh <version, e.g. 26.6>}
app="/Applications/Xcode_${want}.app"

if [ ! -d "$app" ]; then
  major=${want%%.*}
  echo "::warning::Xcode ${want} is not on this runner image; falling back to the newest Xcode ${major}.x"
  app=$(ls -d /Applications/Xcode_"${major}".*.app 2>/dev/null | sort -V | tail -n 1 || true)
  if [ -z "$app" ]; then
    echo "::error::No Xcode ${major}.x found. Installed:"
    ls /Applications | grep -i xcode || true
    exit 1
  fi
fi

sudo xcode-select -s "$app"
echo "Selected $app"
xcodebuild -version
