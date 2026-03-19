#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <benchmark-csv>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build/check-benchmark-smoke.bat")"
CSV_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/$1")"

/mnt/c/Windows/System32/cmd.exe /C "\"$BAT_PATH_WINDOWS\" \"$CSV_PATH_WINDOWS\""
