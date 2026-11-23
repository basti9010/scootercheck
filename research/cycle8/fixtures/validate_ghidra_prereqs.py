#!/usr/bin/env python3
"""Cycle 8 Agent B — preflight for Ghidra headless validation.

Checks (without inventing Ghidra exports):
  1. Synthetic firmware blob present + Cortex-M IVT plausible
  2. analyzeHeadless / GHIDRA_HOME resolution (same rules as ghidra_decompile.py)
  3. Export scripts present under server/firmware-analysis/ghidra_scripts

Writes a structured JSON summary to --out (default: stdout-friendly path).
Exit codes:
  0  — preflight OK (Ghidra may still be absent; see ghidraAvailable)
  2  — fixture / scripts missing or invalid (hard fail)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


EXPECTED_SHA256 = "3fa9802700f2ff9d8d2695b7655ee4f8093a93e747b6cb969df841e1940077ea"
PROCESSOR = "ARM:LE:32:Cortex"
BASE_ADDR = "0x08000000"

REQUIRED_SCRIPTS = (
    "SeedCortexMEntryPoints.java",
    "ExportAllDecompiled.java",
    "ExportFunctionAnalysis.java",
    "ExportCallGraph.java",
)


def _resolve_headless() -> str | None:
    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    if direct and Path(direct).exists():
        return direct
    home = os.environ.get("GHIDRA_HOME", "").strip()
    if home:
        home_path = Path(home)
        cand = home_path / "support" / "analyzeHeadless"
        if cand.exists():
            return str(cand)
        if home_path.is_dir():
            for child in sorted(home_path.glob("ghidra_*")):
                nested = child / "support" / "analyzeHeadless"
                if nested.exists():
                    return str(nested)
    which = shutil.which("analyzeHeadless")
    if which:
        return which
    opt = Path("/opt/ghidra")
    if opt.is_dir():
        for nested in sorted(opt.glob("ghidra_*/support/analyzeHeadless")):
            if nested.exists():
                return str(nested)
    return None


def _parse_ivt_lite(data: bytes, flash_base: int = 0x08000000) -> dict[str, Any]:
    """Minimal Cortex-M IVT check (no server import required)."""
    if len(data) < 8:
        return {"ok": False, "likely": False, "notes": ["ivt=too_small"]}
    sp = int.from_bytes(data[0:4], "little")
    reset = int.from_bytes(data[4:8], "little")
    thumb = (reset & 1) == 1
    handler = reset & ~1
    in_sram = 0x20000000 <= sp < 0x20100000 or 0x10000000 <= sp < 0x10080000
    in_flash = (
        0x08000000 <= handler < 0x08200000
        or flash_base <= handler < flash_base + max(len(data), 1)
    )
    ok = in_sram and in_flash and thumb
    return {
        "ok": ok,
        "likely": ok,
        "flashBase": f"0x{flash_base:08x}",
        "initialSP": f"0x{sp:08x}",
        "resetHandler": f"0x{handler:08x}",
        "resetThumb": thumb,
        "resetFileOffset": handler - flash_base if in_flash else None,
        "notes": [] if ok else ["ivt=not_cortex_m_like"],
    }


def main() -> int:
    here = Path(__file__).resolve().parent
    repo = here.parents[2]
    default_bin = here / "synthetic_cortex_m_thumb.bin"
    default_scripts = repo / "server" / "firmware-analysis" / "ghidra_scripts"
    default_out = here / "out_validation" / "prereqs.json"

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bin", type=Path, default=default_bin)
    ap.add_argument("--script-dir", type=Path, default=default_scripts)
    ap.add_argument("--out", type=Path, default=default_out)
    args = ap.parse_args()

    errors: list[str] = []
    notes: list[str] = []

    if not args.bin.is_file():
        errors.append(f"missing synthetic blob: {args.bin}")
        blob_meta: dict[str, Any] = {"present": False}
        ivt: dict[str, Any] = {"ok": False}
    else:
        raw = args.bin.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        blob_meta = {
            "present": True,
            "path": str(args.bin),
            "size": len(raw),
            "sha256": digest,
            "sha256MatchesCycle7": digest == EXPECTED_SHA256,
        }
        if digest != EXPECTED_SHA256:
            notes.append(
                f"sha256={digest} differs from cycle7 expected {EXPECTED_SHA256} "
                "(still usable if IVT ok)"
            )
        ivt = _parse_ivt_lite(raw)
        if not ivt.get("ok"):
            errors.append("synthetic blob IVT is not Cortex-M plausible")
        # ASCII marker from cycle7 layout
        if b"SYNTH_C7_NOT_SCOOTER_FW" in raw:
            notes.append("marker=SYNTH_C7_NOT_SCOOTER_FW")

    scripts_present: dict[str, bool] = {}
    if not args.script_dir.is_dir():
        errors.append(f"ghidra_scripts dir missing: {args.script_dir}")
    else:
        for name in REQUIRED_SCRIPTS:
            scripts_present[name] = (args.script_dir / name).is_file()
            if not scripts_present[name]:
                errors.append(f"missing script: {name}")

    headless = _resolve_headless()
    ghidra_home = os.environ.get("GHIDRA_HOME", "").strip() or None
    ghidra_headless_env = os.environ.get("GHIDRA_HEADLESS", "").strip() or None

    if headless is None:
        notes.append(
            "MISSING_PREREQUISITE: analyzeHeadless not found "
            "(set GHIDRA_HOME or GHIDRA_HEADLESS, or install on PATH / /opt/ghidra)."
        )
        notes.append("Do NOT fabricate .functions.json / .callgraph.json / .dec.c.")
    else:
        notes.append(f"headless={headless}")

    result = {
        "schemaVersion": 1,
        "kind": "ghidraPrereqValidation",
        "cycle": 8,
        "agent": "B",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "processorTarget": PROCESSOR,
        "loaderBaseTarget": BASE_ADDR,
        "syntheticFirmware": blob_meta,
        "ivt": ivt,
        "ghidraScriptsDir": str(args.script_dir),
        "ghidraScripts": scripts_present,
        "ghidraHomeEnv": ghidra_home,
        "ghidraHeadlessEnv": ghidra_headless_env,
        "analyzeHeadless": headless,
        "ghidraAvailable": headless is not None,
        "errors": errors,
        "notes": notes,
        "hardBans": [
            "no real encrypted ZT3 plaintext reconstruction",
            "no Cycle-6 FIRM.bin.enc decrypt",
            "no fake Ghidra export artifacts when tools missing",
        ],
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    print(f"Wrote {args.out}", file=sys.stderr)

    if errors:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
