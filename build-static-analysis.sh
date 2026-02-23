#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${ROOT_DIR}/tests/MaxEventNexusTests.dproj"
OUT_DIR="${ROOT_DIR}/build/analysis"
SKILL_DIR="${STATIC_ANALYSIS_SKILL_DIR:-$HOME/.codex/skills/delphi-static-analysis}"
DOCTOR_LOG="${OUT_DIR}/doctor.txt"
ANALYZE_LOG="${OUT_DIR}/analyze.log"

if [[ ! -f "${PROJECT_PATH}" ]]; then
  echo "ERROR: Missing project: ${PROJECT_PATH}" >&2
  exit 2
fi

if [[ ! -f "${SKILL_DIR}/doctor.sh" ]] || [[ ! -f "${SKILL_DIR}/analyze.sh" ]]; then
  echo "ERROR: Missing delphi-static-analysis skill scripts under: ${SKILL_DIR}" >&2
  exit 2
fi

mkdir -p "${OUT_DIR}"

if ! bash "${SKILL_DIR}/doctor.sh" "${PROJECT_PATH}" >"${DOCTOR_LOG}" 2>&1; then
  cat "${DOCTOR_LOG}" >&2
  exit 2
fi

if grep -q "PascalAnalyzer.Path=<empty>" "${DOCTOR_LOG}"; then
  export DAK_PASCAL_ANALYZER=0
else
  export DAK_PASCAL_ANALYZER=1
fi

export DAK_OUT="${OUT_DIR}"
export DAK_CLEAN=1
export DAK_WRITE_SUMMARY=1

set +e
bash "${SKILL_DIR}/analyze.sh" "${PROJECT_PATH}" >"${ANALYZE_LOG}" 2>&1
ANALYZE_EXIT=$?
set -e

if [[ ! -f "${OUT_DIR}/summary.md" ]]; then
  cat "${ANALYZE_LOG}" >&2
  if [[ ${ANALYZE_EXIT} -eq 0 ]]; then
    exit 1
  fi
  exit "${ANALYZE_EXIT}"
fi

if [[ ${ANALYZE_EXIT} -ne 0 ]]; then
  if [[ -f "${OUT_DIR}/fixinsight/fixinsight.txt" ]]; then
    {
      echo
      echo "Non-zero analyzer exit (${ANALYZE_EXIT}) accepted because reports were produced."
    } >> "${OUT_DIR}/summary.md"
  else
    cat "${ANALYZE_LOG}" >&2
    exit "${ANALYZE_EXIT}"
  fi
fi

if [[ -f "${OUT_DIR}/fixinsight/fixinsight.txt" ]]; then
  cp "${OUT_DIR}/fixinsight/fixinsight.txt" "${OUT_DIR}/fixinsight.txt"
else
  cat > "${OUT_DIR}/fixinsight.txt" <<'EOF'
TOOL_UNAVAILABLE: FixInsight report was not produced.
See build/analysis/doctor.txt and build/analysis/analyze.log for details.
EOF
fi

if [[ -f "${OUT_DIR}/pascal-analyzer/pascal-analyzer.log" ]]; then
  cp "${OUT_DIR}/pascal-analyzer/pascal-analyzer.log" "${OUT_DIR}/pascal-analyzer.txt"
elif [[ -f "${OUT_DIR}/pascal-analyzer.log" ]]; then
  cp "${OUT_DIR}/pascal-analyzer.log" "${OUT_DIR}/pascal-analyzer.txt"
else
  cat > "${OUT_DIR}/pascal-analyzer.txt" <<'EOF'
TOOL_UNAVAILABLE: Pascal Analyzer was skipped or not configured.
See build/analysis/doctor.txt and build/analysis/summary.md for details.
EOF
fi

echo "Static analysis outputs:"
echo "  ${OUT_DIR}/summary.md"
echo "  ${OUT_DIR}/fixinsight.txt"
echo "  ${OUT_DIR}/pascal-analyzer.txt"
echo "  ${OUT_DIR}/doctor.txt"
echo "  ${OUT_DIR}/analyze.log"

exit 0
