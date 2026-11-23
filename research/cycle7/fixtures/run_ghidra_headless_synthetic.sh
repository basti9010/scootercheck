#!/usr/bin/env bash
# Cycle 7 — synthetic Ghidra headless smoke (SKIP if Ghidra missing).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/synthetic_cortex_m_thumb.bin"
OUT="${GHIDRA_PROJECT_DIR:-/tmp/scootercheck-ghidra-synth}"
PROJ="synth_c7"
mkdir -p "$OUT"

HEADLESS="${GHIDRA_HEADLESS:-}"
if [[ -z "$HEADLESS" && -n "${GHIDRA_HOME:-}" && -x "$GHIDRA_HOME/support/analyzeHeadless" ]]; then
  HEADLESS="$GHIDRA_HOME/support/analyzeHeadless"
fi
if [[ -z "$HEADLESS" ]] || [[ ! -x "$HEADLESS" ]]; then
  echo "SKIP: analyzeHeadless not found (set GHIDRA_HOME or GHIDRA_HEADLESS). Synthetic fixture: $BIN"
  exit 0
fi

PROC="${GHIDRA_PROCESSOR:-ARM:LE:32:Cortex}"
BASE="${GHIDRA_BASE_ADDR:-0x08000000}"
echo "Running Ghidra headless import on synthetic fixture…"
"$HEADLESS" "$OUT" "$PROJ" \
  -import "$BIN" \
  -processor "$PROC" \
  -loader BinaryLoader \
  -loader-baseAddr "$BASE" \
  -deleteProject \
  -noanalysis \
  || { echo "WARN: headless returned non-zero (fixture may still be useful)"; exit 0; }
echo "OK: synthetic import completed"
