#!/usr/bin/env bash
# Cycle 7 Agent C — headless Ghidra smoke on synthetic_cortex_m_thumb.bin
#
# IF GHIDRA_HOME / GHIDRA_HEADLESS / analyzeHeadless is available:
#   import the synthetic Cortex-M Thumb blob and optionally run decompile export.
# ELSE:
#   exit 0 with a clear SKIP message (CI-safe).
#
# Hard bans for this research cycle:
#   - do NOT reconstruct tuning / activation sequences
#   - do NOT decrypt Cycle-6 FIRM.bin.enc payloads
#
# Usage:
#   ./run_ghidra_headless_synthetic.sh
#   GHIDRA_HOME=/opt/ghidra/ghidra_12.2_PUBLIC ./run_ghidra_headless_synthetic.sh
#   DECOMPILE=1 GHIDRA_SCRIPT_DIR=/path/to/ghidra_scripts ./run_ghidra_headless_synthetic.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${SYNTHETIC_BIN:-$SCRIPT_DIR/synthetic_cortex_m_thumb.bin}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out_synthetic}"
PROCESSOR="${PROCESSOR:-ARM:LE:32:Cortex}"
BASE_ADDR="${BASE_ADDR:-0x08000000}"
PROJECT_NAME="${PROJECT_NAME:-Cycle7Synthetic}"
DECOMPILE="${DECOMPILE:-1}"
TIMEOUT_SEC="${GHIDRA_TIMEOUT_SEC:-180}"

resolve_headless() {
  if [[ -n "${GHIDRA_HEADLESS:-}" && -x "${GHIDRA_HEADLESS}" ]]; then
    echo "${GHIDRA_HEADLESS}"
    return 0
  fi
  if [[ -n "${GHIDRA_HOME:-}" ]]; then
    local cand nested
    cand="${GHIDRA_HOME}/support/analyzeHeadless"
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
    if [[ -d "${GHIDRA_HOME}" ]]; then
      for nested in "${GHIDRA_HOME}"/ghidra_*/support/analyzeHeadless; do
        if [[ -x "$nested" ]]; then
          echo "$nested"
          return 0
        fi
      done
    fi
  fi
  if command -v analyzeHeadless >/dev/null 2>&1; then
    command -v analyzeHeadless
    return 0
  fi
  for nested in /opt/ghidra/ghidra_*/support/analyzeHeadless; do
    if [[ -x "$nested" ]]; then
      echo "$nested"
      return 0
    fi
  done
  return 1
}

HEADLESS=""
if ! HEADLESS="$(resolve_headless)"; then
  echo "SKIP: Ghidra headless not available (set GHIDRA_HOME or GHIDRA_HEADLESS, or install analyzeHeadless on PATH)."
  echo "SKIP: synthetic fixture left untouched at: $BIN"
  exit 0
fi

if [[ ! -f "$BIN" ]]; then
  echo "ERROR: synthetic blob missing: $BIN" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
PROJ_DIR="$OUT_DIR/project"
mkdir -p "$PROJ_DIR"
OUT_C="$OUT_DIR/synthetic.dec.c"
OUT_FUNCTIONS="$OUT_DIR/synthetic.functions.json"
LOG="$OUT_DIR/analyzeHeadless.log"

echo "Ghidra headless: $HEADLESS"
echo "Import: $BIN"
echo "Processor: $PROCESSOR  base: $BASE_ADDR"
echo "Output dir: $OUT_DIR"

CMD=(
  "$HEADLESS"
  "$PROJ_DIR"
  "$PROJECT_NAME"
  -import "$BIN"
  -processor "$PROCESSOR"
  -cspec default
  -loader BinaryLoader
  -loader-baseAddr "$BASE_ADDR"
  -deleteProject
)

# Optional: use ScooterCheck Export*.java scripts when GHIDRA_SCRIPT_DIR is set
# (typically server/firmware-analysis/ghidra_scripts from unified-investigation-flow).
if [[ -n "${GHIDRA_SCRIPT_DIR:-}" && -d "${GHIDRA_SCRIPT_DIR}" ]]; then
  CMD+=(-scriptPath "$GHIDRA_SCRIPT_DIR")
  if [[ -f "${GHIDRA_SCRIPT_DIR}/SeedCortexMEntryPoints.java" ]]; then
    CMD+=(-preScript SeedCortexMEntryPoints.java)
  fi
  if [[ "$DECOMPILE" == "1" && -f "${GHIDRA_SCRIPT_DIR}/ExportAllDecompiled.java" ]]; then
    CMD+=(-postScript ExportAllDecompiled.java "$OUT_C")
  fi
  if [[ -f "${GHIDRA_SCRIPT_DIR}/ExportFunctionAnalysis.java" ]]; then
    CMD+=(-postScript ExportFunctionAnalysis.java "$OUT_FUNCTIONS")
  fi
else
  echo "NOTE: GHIDRA_SCRIPT_DIR unset — import-only smoke (no Export*.java / decompile)."
  echo "NOTE: set GHIDRA_SCRIPT_DIR to server/firmware-analysis/ghidra_scripts for full export."
fi

export GHIDRA_BASE_ADDR="$BASE_ADDR"
export SCOOTERCHECK_LOADER_BASE="$BASE_ADDR"
export GHIDRA_MAX_FUNCTIONS="${GHIDRA_MAX_FUNCTIONS:-2500}"

set +e
timeout "${TIMEOUT_SEC}" "${CMD[@]}" >"$LOG" 2>&1
RC=$?
set -e

if [[ $RC -eq 124 ]]; then
  echo "ERROR: analyzeHeadless timed out after ${TIMEOUT_SEC}s (log: $LOG)" >&2
  exit 3
fi
if [[ $RC -ne 0 ]]; then
  echo "ERROR: analyzeHeadless exited $RC (log: $LOG)" >&2
  tail -n 40 "$LOG" >&2 || true
  exit 4
fi

echo "OK: headless import completed (rc=0)"
if [[ -f "$OUT_C" ]]; then
  echo "OK: decompile export -> $OUT_C ($(wc -c <"$OUT_C") bytes)"
fi
if [[ -f "$OUT_FUNCTIONS" ]]; then
  echo "OK: functions export -> $OUT_FUNCTIONS ($(wc -c <"$OUT_FUNCTIONS") bytes)"
fi
echo "Log: $LOG"
exit 0
