#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$ROOT_DIR/build-tests.sh"
"$ROOT_DIR/tests/MaxEventNexusTests.exe" --stress-suite
