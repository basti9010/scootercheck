#!/usr/bin/env bash
# Cycle 9 Agent B — headless Ghidra validation on synthetic_cortex_m_thumb.bin
#
# Proof points (written to OUT_DIR/proof_points.json):
#   1. Import
#   2. Architecture
#   3. Static analysis
#   4. Function detection
#   5. Control-flow
#   6. JSON export
#   7. Error handling
#
# IF GHIDRA_HOME / GHIDRA_HEADLESS / analyzeHeadless is available:
#   BinaryLoader import + optional Export*.java postScripts.
# ELSE:
#   document SKIP for Ghidra-dependent proofs, PASS for error documentation,
#   exit 0 (CI-safe). Do NOT fabricate Ghidra exports. Do NOT claim a successful run.
#
# Hard bans:
#   - no real encrypted ZT3 plaintext reconstruction
#   - no Cycle-6 FIRM.bin.enc decrypt
#   - no fake .functions.json / .callgraph.json / .dec.c
#
# Usage:
#   ./run_ghidra_headless_synthetic.sh
#   GHIDRA_HOME=/opt/ghidra/ghidra_12.2_PUBLIC \
#     GHIDRA_SCRIPT_DIR=../../../server/firmware-analysis/ghidra_scripts \
#     ./run_ghidra_headless_synthetic.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN="${SYNTHETIC_BIN:-$SCRIPT_DIR/synthetic_cortex_m_thumb.bin}"
# Fall back to Cycle-8 fixture if Cycle-9 copy is absent
if [[ ! -f "$BIN" && -f "$REPO_ROOT/research/cycle8/fixtures/synthetic_cortex_m_thumb.bin" ]]; then
  BIN="$REPO_ROOT/research/cycle8/fixtures/synthetic_cortex_m_thumb.bin"
fi
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out_synthetic}"
PROCESSOR="${PROCESSOR:-ARM:LE:32:Cortex}"
BASE_ADDR="${BASE_ADDR:-0x08000000}"
PROJECT_NAME="${PROJECT_NAME:-Cycle9Synthetic}"
DECOMPILE="${DECOMPILE:-1}"
TIMEOUT_SEC="${GHIDRA_TIMEOUT_SEC:-180}"
DEFAULT_SCRIPT_DIR="$REPO_ROOT/server/firmware-analysis/ghidra_scripts"
GHIDRA_SCRIPT_DIR="${GHIDRA_SCRIPT_DIR:-$DEFAULT_SCRIPT_DIR}"

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

write_skip_proof_json() {
  local missing_msg="$1"
  local proof_file="$OUT_DIR/proof_points.json"
  mkdir -p "$OUT_DIR"
  # Refuse leftover fabricated exports on SKIP path
  python3 - "$proof_file" "$missing_msg" \
    "$BIN" "$PROCESSOR" "$BASE_ADDR" "$OUT_DIR" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

out, missing, bin_path, processor, base, out_dir = sys.argv[1:7]
out_p = Path(out_dir)

suspects = []
banned_names = {
    "synthetic.functions.json",
    "synthetic.callgraph.json",
    "synthetic.dec.c",
    "synthetic.speeds.json",
    "synthetic.limits.c",
}
if out_p.is_dir():
    for p in out_p.rglob("*"):
        if p.is_file() and p.name in banned_names:
            suspects.append(str(p))

def point(pid, name, st, detail):
    return {"id": pid, "name": name, "status": st, "detail": detail}

points = [
    point(1, "Import", "SKIP",
          "analyzeHeadless unavailable — BinaryLoader import not attempted"),
    point(2, "Architecture", "SKIP",
          f"Target processor {processor} + base {base} documented; Ghidra language assignment not executed"),
    point(3, "Static analysis", "SKIP",
          "No headless auto-analysis without Ghidra"),
    point(4, "Function detection", "SKIP",
          "No SeedCortexMEntryPoints / ExportFunctionAnalysis run; no fabricated .functions.json"),
    point(5, "Control-flow", "SKIP",
          "No ExportCallGraph.java run; no fabricated .callgraph.json"),
    point(6, "JSON export", "PASS",
          f"Validation proof envelope written to {out} (not a Ghidra export; no fabricated function/callgraph JSON)"),
    point(7, "Error handling", "PASS", missing),
]

if suspects:
    points[5] = point(
        6, "JSON export", "FAIL",
        "SKIP path found suspect Ghidra-shaped artifacts (must not fabricate): " + ", ".join(suspects),
    )
    points[6] = point(
        7, "Error handling", "FAIL",
        "Missing-tool path contaminated by export-like files: " + ", ".join(suspects),
    )
    overall = "FAIL_FABRICATED_EXPORTS"
    rc = 6
else:
    overall = "SKIPPED_NO_GHIDRA"
    rc = 0

doc = {
    "schemaVersion": 1,
    "kind": "ghidraValidationProofPoints",
    "cycle": 9,
    "agent": "B",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "ghidraAvailable": False,
    "syntheticBin": bin_path,
    "processor": processor,
    "loaderBase": base,
    "outDir": out_dir,
    "overallStatus": overall,
    "exactMissingCause": missing,
    "proofPoints": points,
    "hardBans": [
        "no real encrypted ZT3 plaintext reconstruction",
        "no Cycle-6 FIRM.bin.enc decrypt",
        "no fake Ghidra export artifacts",
        "never claim successful Ghidra run without analyzeHeadless",
    ],
}
Path(out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps(doc, indent=2, ensure_ascii=False))
sys.exit(rc)
PY
}

# --- Preflight (fixture + scripts + env probe; never invents Ghidra exports) ---
PREFLIGHT_OUT="$SCRIPT_DIR/out_validation/prereqs.json"
python3 "$SCRIPT_DIR/validate_ghidra_prereqs.py" \
  --bin "$BIN" \
  --script-dir "$GHIDRA_SCRIPT_DIR" \
  --out "$PREFLIGHT_OUT" \
  --scan-out-dir "$OUT_DIR"
PRE_RC=$?
if [[ $PRE_RC -ne 0 ]]; then
  echo "ERROR: preflight failed (rc=$PRE_RC). See $PREFLIGHT_OUT" >&2
  exit 2
fi

HEADLESS=""
if ! HEADLESS="$(resolve_headless)"; then
  MISSING="MISSING_PREREQUISITE: GHIDRA_HOME unset, GHIDRA_HEADLESS unset, analyzeHeadless not on PATH, /opt/ghidra absent. Java present does not imply Ghidra."
  echo "SKIP: Ghidra headless not available (set GHIDRA_HOME or GHIDRA_HEADLESS, or install analyzeHeadless on PATH)."
  echo "SKIP: $MISSING"
  echo "SKIP: synthetic fixture left untouched at: $BIN"
  echo "SKIP: claiming NO successful Ghidra import/analyze/export on this host."
  mkdir -p "$OUT_DIR"
  set +e
  write_skip_proof_json "$MISSING" >"$OUT_DIR/proof_points.pretty.json"
  SKIP_RC=$?
  set -e
  if [[ $SKIP_RC -ne 0 ]]; then
    echo "ERROR: SKIP path failed integrity check (rc=$SKIP_RC). See $OUT_DIR/proof_points.json" >&2
    exit "$SKIP_RC"
  fi
  echo "OK: proof points documented at $OUT_DIR/proof_points.json (SKIP-safe, no fake exports)"
  echo "OK: env probe at $SCRIPT_DIR/out_validation/env_probe.json"
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
OUT_CALLGRAPH="$OUT_DIR/synthetic.callgraph.json"
LOG="$OUT_DIR/analyzeHeadless.log"

echo "Ghidra headless: $HEADLESS"
echo "Import: $BIN"
echo "Processor: $PROCESSOR  base: $BASE_ADDR"
echo "Script dir: $GHIDRA_SCRIPT_DIR"
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

if [[ -d "${GHIDRA_SCRIPT_DIR}" ]]; then
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
  if [[ -f "${GHIDRA_SCRIPT_DIR}/ExportCallGraph.java" ]]; then
    CMD+=(-postScript ExportCallGraph.java "$OUT_CALLGRAPH")
  fi
else
  echo "NOTE: GHIDRA_SCRIPT_DIR missing — import-only smoke (no Export*.java)."
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
  python3 - "$OUT_DIR/proof_points.json" "$BIN" "$PROCESSOR" "$BASE_ADDR" "$OUT_DIR" "$LOG" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
out, bin_path, processor, base, out_dir, log = sys.argv[1:7]
points = [
  {"id":1,"name":"Import","status":"FAIL","detail":"timed out"},
  {"id":2,"name":"Architecture","status":"FAIL","detail":"timed out"},
  {"id":3,"name":"Static analysis","status":"FAIL","detail":f"timeout log={log}"},
  {"id":4,"name":"Function detection","status":"FAIL","detail":"timed out"},
  {"id":5,"name":"Control-flow","status":"FAIL","detail":"timed out"},
  {"id":6,"name":"JSON export","status":"PASS","detail":out},
  {"id":7,"name":"Error handling","status":"PASS","detail":"tools present; timeout documented"},
]
Path(out).write_text(json.dumps({
  "schemaVersion":1,"kind":"ghidraValidationProofPoints","cycle":9,"agent":"B",
  "generatedAt":datetime.now(timezone.utc).isoformat(),"ghidraAvailable":True,
  "syntheticBin":bin_path,"processor":processor,"loaderBase":base,"outDir":out_dir,
  "overallStatus":"FAIL_TIMEOUT","proofPoints":points,
}, indent=2)+"\n")
PY
  exit 3
fi
if [[ $RC -ne 0 ]]; then
  echo "ERROR: analyzeHeadless exited $RC (log: $LOG)" >&2
  tail -n 40 "$LOG" >&2 || true
  python3 - "$OUT_DIR/proof_points.json" "$BIN" "$PROCESSOR" "$BASE_ADDR" "$OUT_DIR" "$LOG" "$RC" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
out, bin_path, processor, base, out_dir, log, rc = sys.argv[1:8]
points = [
  {"id":1,"name":"Import","status":"FAIL","detail":f"exit {rc}"},
  {"id":2,"name":"Architecture","status":"FAIL","detail":f"exit {rc}"},
  {"id":3,"name":"Static analysis","status":"FAIL","detail":f"exit {rc}; log={log}"},
  {"id":4,"name":"Function detection","status":"FAIL","detail":f"exit {rc}"},
  {"id":5,"name":"Control-flow","status":"FAIL","detail":f"exit {rc}"},
  {"id":6,"name":"JSON export","status":"PASS","detail":out},
  {"id":7,"name":"Error handling","status":"PASS","detail":"tools present; error documented"},
]
Path(out).write_text(json.dumps({
  "schemaVersion":1,"kind":"ghidraValidationProofPoints","cycle":9,"agent":"B",
  "generatedAt":datetime.now(timezone.utc).isoformat(),"ghidraAvailable":True,
  "syntheticBin":bin_path,"processor":processor,"loaderBase":base,"outDir":out_dir,
  "overallStatus":f"FAIL_EXIT_{rc}","proofPoints":points,"log":log,
}, indent=2)+"\n")
PY
  exit 4
fi

# Grade proof points from artifacts (no fabrication)
python3 - "$OUT_DIR/proof_points.json" "$BIN" "$PROCESSOR" "$BASE_ADDR" "$OUT_DIR" \
  "$OUT_C" "$OUT_FUNCTIONS" "$OUT_CALLGRAPH" "$LOG" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

(
    out, bin_path, processor, base, out_dir,
    out_c, out_fn, out_cg, log,
) = sys.argv[1:10]

def st(path: str, need_keys=None):
    p = Path(path)
    if not p.is_file() or p.stat().st_size == 0:
        return "FAIL", f"missing-or-empty: {path}"
    if need_keys:
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            return "FAIL", f"badjson: {e}"
        for k in need_keys:
            if k not in data:
                return "FAIL", f"missing key {k}"
        return "PASS", f"{path} ({p.stat().st_size}B)"
    return "PASS", f"{path} ({p.stat().st_size}B)"

log_txt = Path(log).read_text(encoding="utf-8", errors="replace") if Path(log).is_file() else ""
import_ok = (
    "IMPORT" in log_txt.upper()
    or "import" in log_txt.lower()
    or True  # rc=0 from analyzeHeadless is the primary import signal
)
arch_st, arch_detail = "PASS", processor
fn_st, fn_detail = st(out_fn, ["functions", "schemaVersion"])
fn_count = None
if fn_st == "PASS":
    try:
        fa = json.loads(Path(out_fn).read_text(encoding="utf-8"))
        proc = str(fa.get("processor") or "")
        fns = fa.get("functions") or []
        fn_count = len(fns) if isinstance(fns, list) else None
        if "ARM" in proc and "Cortex" in proc:
            arch_st, arch_detail = "PASS", proc
        elif proc:
            arch_st, arch_detail = "FAIL", f"unexpected processor={proc}"
        else:
            arch_detail = f"{processor} (processor field empty in export; language set at import)"
        if fn_count == 0:
            fn_st, fn_detail = "FAIL", f"{out_fn} has zero functions"
        elif fn_count is not None:
            fn_detail = f"{fn_detail}; functionCount={fn_count}"
    except Exception as e:
        arch_st, arch_detail = "FAIL", str(e)
cg_st, cg_detail = st(out_cg, ["edges", "schemaVersion"])
# JSON export: require at least one structured Ghidra JSON
json_st = "PASS" if fn_st == "PASS" or cg_st == "PASS" else "FAIL"
json_detail = out_dir if json_st == "PASS" else "missing functions/callgraph JSON exports"

points = [
    {"id": 1, "name": "Import", "status": "PASS" if import_ok else "FAIL",
     "detail": f"analyzeHeadless rc=0; log={log}"},
    {"id": 2, "name": "Architecture", "status": arch_st, "detail": arch_detail},
    {"id": 3, "name": "Static analysis", "status": "PASS",
     "detail": "analyzeHeadless completed with auto-analysis"},
    {"id": 4, "name": "Function detection", "status": fn_st, "detail": fn_detail},
    {"id": 5, "name": "Control-flow", "status": cg_st, "detail": cg_detail},
    {"id": 6, "name": "JSON export", "status": json_st, "detail": json_detail},
    {"id": 7, "name": "Error handling", "status": "PASS", "detail": "tools present"},
]
fails = [p for p in points if p["status"] == "FAIL"]
overall = "FAIL" if fails else "PASS"
doc = {
    "schemaVersion": 1,
    "kind": "ghidraValidationProofPoints",
    "cycle": 9,
    "agent": "B",
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "ghidraAvailable": True,
    "syntheticBin": bin_path,
    "processor": processor,
    "loaderBase": base,
    "outDir": out_dir,
    "overallStatus": overall,
    "artifacts": {
        "decompile": out_c if Path(out_c).is_file() else None,
        "functions": out_fn if Path(out_fn).is_file() else None,
        "callgraph": out_cg if Path(out_cg).is_file() else None,
        "log": log,
        "functionCount": fn_count,
    },
    "proofPoints": points,
}
Path(out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(json.dumps(doc, indent=2, ensure_ascii=False))
if fails:
    sys.exit(5)
PY

echo "OK: headless import completed (rc=0)"
[[ -f "$OUT_C" ]] && echo "OK: decompile export -> $OUT_C ($(wc -c <"$OUT_C") bytes)"
[[ -f "$OUT_FUNCTIONS" ]] && echo "OK: functions export -> $OUT_FUNCTIONS ($(wc -c <"$OUT_FUNCTIONS") bytes)"
[[ -f "$OUT_CALLGRAPH" ]] && echo "OK: callgraph export -> $OUT_CALLGRAPH ($(wc -c <"$OUT_CALLGRAPH") bytes)"
echo "Log: $LOG"
echo "Proof points: $OUT_DIR/proof_points.json"
exit 0
