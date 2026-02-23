#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <benchmark-csv> [threshold-csv]" >&2
  exit 2
fi

lCsvPath="$1"
lThresholdPath="${2:-bench/scheduler-thresholds.csv}"

if [[ ! -f "$lCsvPath" ]]; then
  echo "ERROR: benchmark CSV not found: $lCsvPath" >&2
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
  lScheduler = trim($1);
  lDelivery = trim($2);
  lKey = lScheduler "|" lDelivery;
  if (lKey == "|") {
    next;
  }
  lMinThroughput[lKey] = trim($3) + 0;
  lMaxP95[lKey] = trim($4) + 0;
  lMaxP99[lKey] = trim($5) + 0;
  lMaxAvg[lKey] = trim($6) + 0;
  lThresholdRows++;
  next;
}

FNR == 1 {
  for (lIdx = 1; lIdx <= NF; lIdx++) {
    lHeader = trim($lIdx);
    lColumns[lHeader] = lIdx;
  }
  lRequired["scheduler"] = 1;
  lRequired["delivery"] = 1;
  lRequired["status"] = 1;
  lRequired["error"] = 1;
  lRequired["avg_throughput_evt_s"] = 1;
  lRequired["p95_us"] = 1;
  lRequired["p99_us"] = 1;
  lRequired["avg_us"] = 1;
  for (lName in lRequired) {
    if (!(lName in lColumns)) {
      printf("ERROR: benchmark CSV missing required column: %s\n", lName) > "/dev/stderr";
      exit 2;
    }
  }
  next;
}

{
  for (lIdx = 1; lIdx <= NF; lIdx++) {
    $lIdx = trim($lIdx);
  }
  lScheduler = $lColumns["scheduler"];
  lDelivery = $lColumns["delivery"];
  lStatus = $lColumns["status"];
  lError = $lColumns["error"];
  lKey = lScheduler "|" lDelivery;

  if (lStatus != "ok") {
    printf("FAIL: scheduler=%s delivery=%s status=%s error=%s\n", lScheduler, lDelivery, lStatus, lError) > "/dev/stderr";
    lFailed = 1;
    next;
  }

  if (!(lKey in lMinThroughput)) {
    printf("FAIL: missing threshold row for scheduler=%s delivery=%s\n", lScheduler, lDelivery) > "/dev/stderr";
    lFailed = 1;
    next;
  }

  lThroughput = $lColumns["avg_throughput_evt_s"] + 0;
  lP95 = $lColumns["p95_us"] + 0;
  lP99 = $lColumns["p99_us"] + 0;
  lAvg = $lColumns["avg_us"] + 0;

  if (lThroughput < lMinThroughput[lKey]) {
    printf("FAIL: scheduler=%s delivery=%s throughput %.0f < min %.0f\n", lScheduler, lDelivery, lThroughput, lMinThroughput[lKey]) > "/dev/stderr";
    lFailed = 1;
  }
  if (lP95 > lMaxP95[lKey]) {
    printf("FAIL: scheduler=%s delivery=%s p95 %.0f > max %.0f\n", lScheduler, lDelivery, lP95, lMaxP95[lKey]) > "/dev/stderr";
    lFailed = 1;
  }
  if (lP99 > lMaxP99[lKey]) {
    printf("FAIL: scheduler=%s delivery=%s p99 %.0f > max %.0f\n", lScheduler, lDelivery, lP99, lMaxP99[lKey]) > "/dev/stderr";
    lFailed = 1;
  }
  if (lAvg > lMaxAvg[lKey]) {
    printf("FAIL: scheduler=%s delivery=%s avg %.0f > max %.0f\n", lScheduler, lDelivery, lAvg, lMaxAvg[lKey]) > "/dev/stderr";
    lFailed = 1;
  }

  lChecked++;
}

END {
  if (lThresholdRows == 0) {
    print "ERROR: threshold CSV has no data rows" > "/dev/stderr";
    exit 2;
  }
  if (lChecked == 0) {
    print "ERROR: benchmark CSV has no data rows" > "/dev/stderr";
    exit 2;
  }
  if (lFailed) {
    exit 1;
  }
  printf("Benchmark thresholds passed: %d row(s) checked using %s\n", lChecked, threshold_file);
}
' "$lThresholdPath" "$lCsvPath"
