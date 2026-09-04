#!/usr/bin/env bash
# Design spec §7.5 and §11: the extension (ReVoxBroadcast/) and the sources it shares with the app (Shared/) never
# contain models, an audio engine or session, network or keychain code, Swift concurrency or dispatch, or host-time
# APIs; the extension target depends on ReVoxCore only; its entitlements carry the App Group and nothing else.
# Usage: scripts/ci/check-extension-surface.sh [repository root]
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root"
failures=0

scan() {  # $1 = extended regex, $2 = description
  if grep -rnE --include='*.swift' --include='*.c' --include='*.h' -e "$1" ReVoxBroadcast Shared; then
    echo "::error::extension surface: $2"
    failures=$((failures + 1))
  fi
}

scan 'import (CoreML|WhisperKit|FluidAudio|UIKit|SwiftUI|SwiftData|Network|Security|CryptoKit)' "forbidden import (§7.5)"
scan 'AVAudioEngine|AVAudioSession|URLSession|SecItem|NSURLConnection|WKWebView' "forbidden API (§7.5, §11)"
scan 'Task[[:space:]]*(\{|\.detached|\.sleep)|DispatchQueue|OperationQueue|\<await\>|\<async\>' "Swift concurrency or dispatch in the extension path (§7.3)"
scan 'hostTime|mach_absolute_time|mach_continuous_time|systemUptime' "host-time API (SystemBootTime reason, §11)"

# The ring file is grown in exactly one place: `RingFileMapping.openCreating` (§7.5). That one sanctioned call site
# lives in Shared/Ring/RingFileMapping.swift and is excluded here; anywhere else the call is a violation.
if grep -rnE --include='*.swift' -e 'truncate\(atOffset' ReVoxBroadcast Shared | grep -v '^Shared/Ring/RingFileMapping\.swift:'; then
  echo "::error::extension surface: the ring file is grown only through RingFileMapping.openCreating (§7.5)"
  failures=$((failures + 1))
fi

# project.yml: the ReVoxBroadcast target's dependencies are exactly the local ReVoxCore package.
deps=$(awk '/^  ReVoxBroadcast:/{inside=1; next} inside && /^  [A-Za-z]/{inside=0} inside && /dependencies:/{deps=1; next} inside && deps && /^      - /{print} inside && deps && /^    [a-z]/{deps=0}' project.yml)
if [ "$(printf '%s\n' "$deps" | sed 's/^ *//' | sort -u | tr '\n' ' ' | sed 's/ $//')" != "- package: ReVoxCore" ]; then
  echo "::error::ReVoxBroadcast dependencies must be exactly '- package: ReVoxCore', found: $deps"
  failures=$((failures + 1))
fi

# Entitlements: App Group only, never the increased-memory-limit entitlement (§5.6, §11).
if grep -q 'increased-memory-limit' ReVoxBroadcast/ReVoxBroadcast.entitlements; then
  echo "::error::the extension must not carry com.apple.developer.kernel.increased-memory-limit"
  failures=$((failures + 1))
fi
keys=$(grep -o '<key>[^<]*</key>' ReVoxBroadcast/ReVoxBroadcast.entitlements | sed 's/<[^>]*>//g' | sort -u | tr '\n' ' ' | sed 's/ $//')
if [ "$keys" != "com.apple.security.application-groups" ]; then
  echo "::error::extension entitlements must contain only com.apple.security.application-groups, found: $keys"
  failures=$((failures + 1))
fi

# The ring atomics shim and the mapping are the only C and the only file-system code in the extension path.
if [ "$(ls Shared/Ring/*.c | wc -l | tr -d ' ')" != "1" ]; then
  echo "::error::exactly one C file is expected under Shared/Ring (the atomics shim)"
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  echo "::error::$failures extension-surface rule(s) violated"
  exit 1
fi
echo "extension surface verified: ReVoxBroadcast/ and Shared/ contain no models, engines, sessions, network, concurrency or host-time APIs"
