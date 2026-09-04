#!/usr/bin/env bash
# XcodeGen postGenCommand: put the committed pins into the freshly generated project so that
# `xcodebuild -onlyUsePackageVersionsFromResolvedFile` has something to honour (spec E1, §11).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$root/Package.resolved"
target_dir="$root/ReVoxMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"

if [ ! -f "$source_file" ]; then
  echo "note: no committed Package.resolved yet; xcodebuild will resolve and write one"
  exit 0
fi

mkdir -p "$target_dir"
cp "$source_file" "$target_dir/Package.resolved"
echo "installed the committed Package.resolved ($(wc -c < "$source_file" | tr -d ' ') bytes) into ReVoxMobile.xcodeproj"
