#!/usr/bin/env bash
set -euo pipefail

lRootDir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$lRootDir"

lDelivery="async"
lEvents=2000
lConsumers=2
lSamples=9
lPlatform="Win32"
lMaxInflight=64
lMaxAttempts=0
lExePath=""
lOutPath=""

print_usage() {
  cat <<'EOF'
Usage: bench/run-framework-isolated.sh [options]
  --delivery=<mode>      posting|main|async|background (default: async)
  --events=<n>           events posted per sample (default: 2000)
  --consumers=<n>        subscriber count (default: 2)
  --samples=<n>          isolated-process samples per framework (default: 9)
  --max-attempts=<n>     max attempts per framework (default: samples + 2)
  --platform=<name>      Win32|Win64 (default: Win32)
  --max-inflight=<n>     max in-flight deliveries (default: 64)
  --exe=<path>           explicit SchedulerCompare.exe path
  --out=<path>           summary CSV output path
EOF
}

for lArg in "$@"; do
  case "$lArg" in
    --delivery=*)
      lDelivery="${lArg#*=}"
      ;;
    --events=*)
      lEvents="${lArg#*=}"
      ;;
    --consumers=*)
      lConsumers="${lArg#*=}"
      ;;
    --samples=*)
      lSamples="${lArg#*=}"
      ;;
    --platform=*)
      lPlatform="${lArg#*=}"
      ;;
    --max-attempts=*)
      lMaxAttempts="${lArg#*=}"
      ;;
    --max-inflight=*)
      lMaxInflight="${lArg#*=}"
      ;;
    --exe=*)
      lExePath="${lArg#*=}"
      ;;
    --out=*)
      lOutPath="${lArg#*=}"
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $lArg" >&2
      print_usage >&2
      exit 2
      ;;
  esac
done

if [[ "$lPlatform" != "Win32" && "$lPlatform" != "Win64" ]]; then
  echo "platform must be Win32 or Win64" >&2
  exit 2
fi

if ! [[ "$lEvents" =~ ^[0-9]+$ ]] || (( lEvents <= 0 )); then
  echo "events must be > 0" >&2
  exit 2
fi
if ! [[ "$lConsumers" =~ ^[0-9]+$ ]] || (( lConsumers <= 0 )); then
  echo "consumers must be > 0" >&2
  exit 2
fi
if ! [[ "$lSamples" =~ ^[0-9]+$ ]] || (( lSamples <= 0 )); then
  echo "samples must be > 0" >&2
  exit 2
fi
if ! [[ "$lMaxAttempts" =~ ^[0-9]+$ ]] || (( lMaxAttempts < 0 )); then
  echo "max-attempts must be >= 0" >&2
  exit 2
fi
if ! [[ "$lMaxInflight" =~ ^[0-9]+$ ]] || (( lMaxInflight < 0 )); then
  echo "max-inflight must be >= 0" >&2
  exit 2
fi
if (( lMaxAttempts == 0 )); then
  lMaxAttempts=$((lSamples + 2))
fi
if (( lMaxAttempts < lSamples )); then
  echo "max-attempts must be >= samples" >&2
  exit 2
fi

if [[ -z "$lExePath" ]]; then
  if [[ "$lPlatform" == "Win64" ]]; then
    if [[ -f "bench/Win64/Release/SchedulerCompare.exe" ]]; then
      lExePath="bench/Win64/Release/SchedulerCompare.exe"
    else
      lExePath="bench/SchedulerCompare.exe"
    fi
  else
    if [[ -f "bench/SchedulerCompare.exe" ]]; then
      lExePath="bench/SchedulerCompare.exe"
    else
      lExePath="bench/Win32/Release/SchedulerCompare.exe"
    fi
  fi
fi

if [[ ! -f "$lExePath" ]]; then
  echo "SchedulerCompare executable not found: $lExePath" >&2
  exit 2
fi

if [[ -z "$lOutPath" ]]; then
  lOutPath="bench/scheduler-${lDelivery}-isolated-summary-${lPlatform,,}.csv"
fi

lRootWin="$(wslpath -w -a "$lRootDir")"
lExeWinRel="${lExePath//\//\\}"

framework_tokens=(weak strong ipub eventhorizon)
declare -A lNameByToken
declare -A lUsByToken
declare -A lThroughputByToken
declare -A lAttemptsByToken
declare -A lSuccessByToken

median_from_values() {
  if [[ $# -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END { print a[int((NR + 1) / 2)] }'
}

csv_value_for_column() {
  local lFile="$1"
  local lColumn="$2"
  awk -F',' -v lScenario="framework-compare" -v lColumn="$lColumn" '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        gsub(/\r/, "", $i);
        lIdx[$i] = i;
      }
      next;
    }
    $1 == lScenario {
      if (!(lColumn in lIdx)) {
        exit 2;
      }
      gsub(/\r/, "", $(lIdx[lColumn]));
      print $(lIdx[lColumn]);
      exit;
    }
  ' "$lFile"
}

for lFramework in "${framework_tokens[@]}"; do
  lAttempt=0
  lSuccess=0
  while (( lSuccess < lSamples )) && (( lAttempt < lMaxAttempts )); do
    ((lAttempt += 1))
    lCsvRel="bench/scheduler-${lDelivery}-isolated-${lFramework}-${lPlatform,,}-$(printf '%02d' "$lAttempt").csv"
    lCsvWinRel="${lCsvRel//\//\\}"

    /mnt/c/Windows/System32/cmd.exe /C "cd /d $lRootWin && $lExeWinRel --skip-schedulers --framework=$lFramework --events=$lEvents --consumers=$lConsumers --runs=1 --delivery=$lDelivery --max-inflight=$lMaxInflight --csv=$lCsvWinRel" >/tmp/framework-isolated-run.log 2>&1 || {
      echo "sample failed to execute: framework=$lFramework attempt=$lAttempt" >&2
      continue
    }

    lStatus="$(csv_value_for_column "$lCsvRel" "status")"
    lAvgUs="$(csv_value_for_column "$lCsvRel" "avg_us")"
    lThroughput="$(csv_value_for_column "$lCsvRel" "avg_throughput_evt_s")"
    lName="$(csv_value_for_column "$lCsvRel" "scheduler")"
    lError="$(csv_value_for_column "$lCsvRel" "error")"

    if [[ "$lStatus" != "ok" ]]; then
      echo "sample failed in harness: framework=$lFramework attempt=$lAttempt status=$lStatus error=$lError" >&2
      continue
    fi

    lNameByToken["$lFramework"]="$lName"
    lUsByToken["$lFramework"]+="${lAvgUs} "
    lThroughputByToken["$lFramework"]+="${lThroughput} "
    ((lSuccess += 1))
  done

  lAttemptsByToken["$lFramework"]="$lAttempt"
  lSuccessByToken["$lFramework"]="$lSuccess"
  if (( lSuccess < lSamples )); then
    echo "insufficient successful samples: framework=$lFramework success=$lSuccess required=$lSamples attempts=$lAttempt" >&2
    exit 1
  fi
done

{
  echo "framework,delivery,platform,successful_samples,attempts,median_avg_us,median_throughput_evt_s,best_avg_us,worst_avg_us"
  for lFramework in "${framework_tokens[@]}"; do
    read -r -a lUsValues <<<"${lUsByToken[$lFramework]}"
    read -r -a lThroughputValues <<<"${lThroughputByToken[$lFramework]}"

    lMedianUs="$(median_from_values "${lUsValues[@]}")"
    lMedianThroughput="$(median_from_values "${lThroughputValues[@]}")"
    lBestUs="$(printf '%s\n' "${lUsValues[@]}" | sort -n | head -n1)"
    lWorstUs="$(printf '%s\n' "${lUsValues[@]}" | sort -n | tail -n1)"

    printf '%s,%s,%s,%d,%d,%s,%s,%s,%s\n' \
      "${lNameByToken[$lFramework]}" \
      "$lDelivery" \
      "$lPlatform" \
      "${lSuccessByToken[$lFramework]}" \
      "${lAttemptsByToken[$lFramework]}" \
      "$lMedianUs" \
      "$lMedianThroughput" \
      "$lBestUs" \
      "$lWorstUs"
  done
} >"$lOutPath"

echo "Wrote isolated summary: $lOutPath"
cat "$lOutPath"
