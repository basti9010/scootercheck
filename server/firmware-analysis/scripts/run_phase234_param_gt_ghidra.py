#!/usr/bin/env python3
"""Run ExportDataFlowSummary on Phase 2.3.4 parameter GT firmware (isolated)."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GT_DIR = ROOT / "testdata" / "phase234" / "param_gt"
SCRIPTS = ROOT / "ghidra_scripts"


def _headless() -> Path | None:
    home = os.environ.get("GHIDRA_HOME", "").strip()
    candidates: list[Path] = []
    if home:
        candidates.append(Path(home) / "support" / "analyzeHeadless")
        candidates.extend(Path(home).glob("ghidra_*/support/analyzeHeadless"))
    candidates.append(Path.home() / "ghidra" / "ghidra_12.2_PUBLIC" / "support" / "analyzeHeadless")
    candidates.extend(Path("/opt/ghidra").glob("ghidra_*/support/analyzeHeadless"))
    which = shutil.which("analyzeHeadless")
    if which:
        candidates.append(Path(which))
    for c in candidates:
        if c.is_file() and os.access(c, os.X_OK):
            return c
    return None


def main() -> int:
    headless = _headless()
    if headless is None:
        print("GHIDRA_NOT_CONFIGURED")
        return 3
    bin_path = GT_DIR / "bin" / "param_gt.bin"
    elf_path = GT_DIR / "bin" / "param_gt.elf"
    obj_path = GT_DIR / "bin" / "param_gt.o"
    # Prefer ELF (symbols) over raw bin/object.
    image = elf_path if elf_path.is_file() else bin_path if bin_path.is_file() else obj_path
    if not image.is_file():
        print("BIN_MISSING — run build_phase234_param_gt.py first", file=sys.stderr)
        return 2

    out_dir = GT_DIR / "out"
    out_dir.mkdir(parents=True, exist_ok=True)
    df_out = out_dir / "param_gt.dataflow.json"
    fn_out = out_dir / "param_gt.functions.json"

    with tempfile.TemporaryDirectory(prefix="sc-p234-ghidra-") as td:
        proj = Path(td) / "proj"
        proj.mkdir()
        env = os.environ.copy()
        env.setdefault("GHIDRA_DATAFLOW_DECOMP_PARAMS", "1")
        env.setdefault("GHIDRA_DATAFLOW_DECOMP_BUDGET", "40")
        env.setdefault("GHIDRA_MAX_FUNCTIONS", "200")
        cmd = [
            str(headless),
            str(proj),
            "ParamGT",
            "-import",
            str(image),
        ]
        if image.suffix.lower() in {".bin", ".o"}:
            cmd += [
                "-loader",
                "BinaryLoader",
                "-loader-baseAddr",
                "0x08000000",
                "-processor",
                "ARM:LE:32:Cortex",
                "-cspec",
                "default",
            ]
        cmd += [
            "-analysisTimeoutPerFile",
            "120",
            "-scriptPath",
            str(SCRIPTS),
            "-postScript",
            "SeedCortexMEntryPoints.java",
            "-postScript",
            "ExportFunctionAnalysis.java",
            str(fn_out),
            "-postScript",
            "ExportDataFlowSummary.java",
            str(df_out),
            "-deleteProject",
        ]
        print("+", " ".join(cmd))
        t0 = time.time()
        r = subprocess.run(cmd, env=env, capture_output=True, text=True)
        dt = time.time() - t0
        (out_dir / "headless.log").write_text(
            (r.stdout or "") + "\n---stderr---\n" + (r.stderr or ""), encoding="utf-8"
        )
        print("exit", r.returncode, "time_s", round(dt, 2))
        if r.returncode != 0 and not df_out.is_file():
            print(r.stderr[-2000:] if r.stderr else r.stdout[-2000:])
            return r.returncode or 1

    gt = json.loads((GT_DIR / "ground_truth.json").read_text(encoding="utf-8"))
    df = json.loads(df_out.read_text(encoding="utf-8")) if df_out.is_file() else {"functions": []}
    by_name = {str(f.get("name")): f for f in df.get("functions") or []}
    # Also match FUN_* by scanning logical names as substrings after create.
    stats = {
        "tp": 0,
        "fp": 0,
        "fn": 0,
        "unknown": 0,
        "partial": 0,
        "exact": 0,
        "accepted": 0,
        "wrong": 0,
        "missing": 0,
        "details": [],
    }
    # Prefer address-order match when ELF symbols survive as FUN_* names.
    ordered = sorted(
        [f for f in (df.get("functions") or []) if f.get("name") != "reset_handler"],
        key=lambda x: int(str(x.get("address") or "0"), 16),
    )
    for i, spec in enumerate(gt["functions"]):
        name = spec["logicalName"]
        row = by_name.get(name)
        if row is None and i < len(ordered):
            row = ordered[i]
        if row is None:
            stats["missing"] += 1
            stats["details"].append({"id": spec["id"], "status": "MISSING", "name": name})
            continue
        got = row.get("parameterCount")
        quality = row.get("parameterQuality") or "UNKNOWN_PARAMETER_COUNT"
        exp = spec["expectedParameterCount"]
        allow_u = bool(spec.get("allowUnknown"))
        if quality == "PARTIAL_SIGNATURE":
            stats["partial"] += 1
        if got is None:
            stats["unknown"] += 1
            if allow_u:
                stats["accepted"] += 1
                status = "UNKNOWN_ACCEPTED"
            else:
                stats["fn"] += 1
                status = "UNKNOWN_UNEXPECTED"
        elif int(got) == int(exp):
            stats["tp"] += 1
            stats["exact"] += 1
            stats["accepted"] += 1
            status = "EXACT"
        else:
            stats["wrong"] += 1
            stats["fp"] += 1
            if allow_u:
                stats["accepted"] += 1
                status = "WRONG_ACCEPTED_AMBIGUOUS"
            else:
                status = "WRONG"
        stats["details"].append(
            {
                "id": spec["id"],
                "name": name,
                "ghidraName": row.get("name"),
                "expected": exp,
                "got": got,
                "quality": quality,
                "signatureSource": row.get("signatureSource"),
                "status": status,
            }
        )

    n = len(gt["functions"]) or 1
    exact_acc = stats["exact"] / n * 100.0
    accepted_rate = stats["accepted"] / n * 100.0
    unknown_rate = stats["unknown"] / n * 100.0
    partial_rate = stats["partial"] / n * 100.0
    recovered = sum(
        1
        for d in stats["details"]
        if d.get("got") is not None
        and d.get("quality")
        in ("RECOVERED_PARAMETER_COUNT", "CONFIRMED_ZERO_PARAMETERS", "PARTIAL_SIGNATURE")
    )
    report = {
        "phase": "2.3.4",
        "ghidraHome": str(headless.parent.parent),
        "image": str(image),
        "runtimeSec": round(dt, 3),
        "functionExportCount": len(df.get("functions") or []),
        "evaluatedCases": n,
        "exactParameterAccuracy": exact_acc,
        "acceptedOrAmbiguousRate": accepted_rate,
        "unknownParameterRate": unknown_rate,
        "partialSignatureRate": partial_rate,
        "recoveredParameterCoverage": recovered / n * 100.0,
        # Legacy alias: never equate with exact accuracy.
        "recoveryAccuracyPercent": exact_acc,
        "note": (
            "exactParameterAccuracy counts only exact matches. "
            "acceptedOrAmbiguousRate may include documented allowUnknown cases. "
            "Do not equate accepted rate with exact accuracy."
        ),
        "stats": {k: v for k, v in stats.items() if k != "details"},
        "details": stats["details"],
    }
    (out_dir / "param_gt_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
