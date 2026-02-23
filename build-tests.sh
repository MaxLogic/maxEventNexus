#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/build-delphi.sh" tests/MaxEventNexusTests.dproj -config Debug -enforce-diagnostics-policy -diagnostics-policy build/diagnostics-policy.regex
