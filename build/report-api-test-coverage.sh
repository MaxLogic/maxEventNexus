#!/usr/bin/env bash
set -euo pipefail

lRootDir="$(cd "$(dirname "$0")/.." && pwd)"
lTokenPath="$lRootDir/build/api-test-coverage.tokens"
lTargetPath="$lRootDir/build/api-test-coverage-target.txt"
lOutputPath="$lRootDir/build/analysis/test-api-coverage.md"
lEnforceTarget=0

if [[ "${1:-}" == "--enforce-target" ]]; then
  lEnforceTarget=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--enforce-target]" >&2
  exit 2
fi

if [[ ! -f "$lTokenPath" ]]; then
  echo "ERROR: token list not found: $lTokenPath" >&2
  exit 2
fi

mkdir -p "$(dirname "$lOutputPath")"

declare -a lUncoveredTokens=()
lCovered=0
lTotal=0

while IFS= read -r lLine || [[ -n "$lLine" ]]; do
  lLine="${lLine%%#*}"
  lLine="$(printf '%s' "$lLine" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ -z "$lLine" ]]; then
    continue
  fi

  lTotal=$((lTotal + 1))
  if rg -n --fixed-strings --glob '*.pas' --glob '*.dpr' "$lLine" \
    "$lRootDir/tests/src" "$lRootDir/tests/MaxEventNexusTests.dpr" >/dev/null; then
    lCovered=$((lCovered + 1))
  else
    lUncoveredTokens+=("$lLine")
  fi
done < "$lTokenPath"

if [[ $lTotal -eq 0 ]]; then
  echo "ERROR: no coverage tokens loaded from $lTokenPath" >&2
  exit 2
fi

lPercent=$(( (lCovered * 100 + (lTotal / 2)) / lTotal ))

{
  echo "# API Test Coverage Proxy"
  echo
  echo "- Tokens covered: $lCovered / $lTotal"
  echo "- Coverage percent: ${lPercent}%"
  if [[ ${#lUncoveredTokens[@]} -gt 0 ]]; then
    echo "- Uncovered tokens:"
    for lToken in "${lUncoveredTokens[@]}"; do
      echo "  - \`$lToken\`"
    done
  fi
} > "$lOutputPath"

if [[ $lEnforceTarget -eq 1 ]]; then
  if [[ ! -f "$lTargetPath" ]]; then
    echo "ERROR: target file not found: $lTargetPath" >&2
    exit 2
  fi

  lTarget="$(tr -d '[:space:]' < "$lTargetPath")"
  if [[ ! "$lTarget" =~ ^[0-9]+$ ]]; then
    echo "ERROR: invalid coverage target in $lTargetPath: $lTarget" >&2
    exit 2
  fi

  if [[ $lPercent -lt $lTarget ]]; then
    echo "FAIL: API coverage proxy ${lPercent}% is below target ${lTarget}%." >&2
    echo "      See report: $lOutputPath" >&2
    exit 1
  fi
fi

echo "API coverage proxy: ${lCovered}/${lTotal} (${lPercent}%)."
echo "Report written: $lOutputPath"
