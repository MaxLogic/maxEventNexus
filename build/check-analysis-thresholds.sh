#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <analysis-summary-md> [threshold-csv]" >&2
  exit 2
fi

lSummaryPath="$1"
lThresholdPath="${2:-build/analysis/analysis-thresholds.csv}"

if [[ ! -f "$lSummaryPath" ]]; then
  echo "ERROR: analysis summary not found: $lSummaryPath" >&2
  exit 2
fi

if [[ ! -f "$lThresholdPath" ]]; then
  echo "ERROR: threshold CSV not found: $lThresholdPath" >&2
  exit 2
fi

awk -F',' -v threshold_file="$lThresholdPath" '
function trim(aValue) {
  gsub(/\r/, "", aValue);
  sub(/^[ \t]+/, "", aValue);
  sub(/[ \t]+$/, "", aValue);
  return aValue;
}

FNR == NR {
  if (FNR == 1) {
    next;
  }
  lCode = toupper(trim($1));
  lMaxCount = trim($2);
  if (lCode == "") {
    next;
  }
  if (lMaxCount !~ /^[0-9]+$/) {
    printf("ERROR: invalid max_count for code %s in %s: %s\n", lCode, threshold_file, lMaxCount) > "/dev/stderr";
    exit 2;
  }
  lMaxByCode[lCode] = lMaxCount + 0;
  lThresholdRows++;
  next;
}

{
  lLine = $0;
  gsub(/\r/, "", lLine);
  if (lLine !~ /^[[:space:]]*-[[:space:]]*[A-Za-z][0-9][0-9][0-9][[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*$/) {
    next;
  }
  sub(/^[[:space:]]*-[[:space:]]*/, "", lLine);
  split(lLine, lParts, ":");
  lCode = toupper(trim(lParts[1]));
  lCount = trim(lParts[2]) + 0;
  lFoundByCode[lCode] = lCount;
}

END {
  if (lThresholdRows == 0) {
    printf("ERROR: threshold CSV has no data rows: %s\n", threshold_file) > "/dev/stderr";
    exit 2;
  }

  for (lCode in lMaxByCode) {
    if (!(lCode in lFoundByCode)) {
      printf("FAIL: summary missing code %s\n", lCode) > "/dev/stderr";
      lFailed = 1;
      continue;
    }

    lCurrent = lFoundByCode[lCode];
    lAllowed = lMaxByCode[lCode];
    if (lCurrent > lAllowed) {
      printf("FAIL: code=%s current=%d max=%d\n", lCode, lCurrent, lAllowed) > "/dev/stderr";
      lFailed = 1;
    }
    lChecked++;
  }

  if (lChecked == 0) {
    printf("ERROR: no threshold codes were checked against %s\n", threshold_file) > "/dev/stderr";
    exit 2;
  }
  if (lFailed) {
    exit 1;
  }

  printf("Analysis thresholds passed: %d code(s) checked using %s\n", lChecked, threshold_file);
}
' "$lThresholdPath" "$lSummaryPath"
