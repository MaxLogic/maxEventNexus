#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <benchmark-csv> [full|framework-only]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build/check-benchmark-smoke.bat")"
CSV_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/$1")"
MODE="${2:-full}"

/mnt/c/Windows/System32/cmd.exe /C "\"$BAT_PATH_WINDOWS\" \"$CSV_PATH_WINDOWS\" \"$MODE\""
