#!/usr/bin/env bash
# §11 privacy gate: no host-time API in ReVox's own code or in the resolved package checkouts, so neither
# PrivacyInfo.xcprivacy ever needs the SystemBootTime reasons 35F9.1 / 8FFB.1. All timing in ReVox is frame
# counts, Date, ContinuousClock and CMTime (§5.9, §6.8, §7.5).
set -euo pipefail

require_checkouts=0
if [ "${1:-}" = "--require-checkouts" ]; then
  require_checkouts=1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"

identifiers='hostTime|mach_absolute_time|mach_continuous_time|systemUptime'

# Comments never call an API, and the design documents these identifiers in prose. Strip // line comments and
# /* */ block comments while keeping one output line per input line, so grep -n still reports real line numbers.
strip_comments='
BEGIN { inblock = 0 }
{
  line = $0; out = ""; i = 1
  while (i <= length(line)) {
    two = substr(line, i, 2)
    if (inblock) { if (two == "*/") { inblock = 0; i += 2 } else { i += 1 }; continue }
    if (two == "//") { break }
    if (two == "/*") { inblock = 1; i += 2; continue }
    out = out substr(line, i, 1); i += 1
  }
  print out
}'

status=0

scan() {
  local label="$1"
  shift
  local file matches match
  while IFS= read -r file; do
    matches="$(awk "$strip_comments" "$file" | grep -nE "$identifiers" || true)"
    [ -z "$matches" ] && continue
    while IFS= read -r match; do
      echo "::error file=$file::host-time API in $label — $match"
      status=1
    done <<< "$matches"
  done < <(find "$@" -type f \( -name '*.swift' -o -name '*.m' -o -name '*.h' -o -name '*.c' \) 2>/dev/null)
}

scan "ReVox sources" ReVoxMobile ReVoxMobileTests ReVoxBroadcast ReVoxCore Shared

if [ -d .spm/checkouts ]; then
  for checkout in .spm/checkouts/*/; do
    [ -d "${checkout}Sources" ] || continue
    scan "package checkout $(basename "$checkout")" "${checkout}Sources"
  done
elif [ "$require_checkouts" -eq 1 ]; then
  echo "::error::.spm/checkouts is missing; resolve the packages before running this gate with --require-checkouts"
  exit 1
else
  echo "note: .spm/checkouts is absent, only ReVox's own sources were scanned"
fi

if [ "$status" -ne 0 ]; then
  echo "::error::A host-time API was found. Remove it, or add the SystemBootTime reasons 35F9.1/8FFB.1 to BOTH PrivacyInfo.xcprivacy files in the same pull request (spec §11)."
  exit 1
fi

echo "No host-time API in ReVox sources or the resolved package checkouts."
