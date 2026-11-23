#!/usr/bin/env python3
"""Cycle 9 Agent B — preflight for Ghidra headless validation.

Improvements over Cycle 8:
  - Explicit environmentProbe for every resolution path (exact SKIP cause)
  - Cross-check server/firmware-analysis/ghidra_decompile.ghidra_configured()
  - Record Java presence separately (does NOT imply Ghidra)
  - Assert no fabricated export artifacts when tools missing
  - Cycle-9 proof-point vocabulary (Import / Architecture / …)

Checks (without inventing Ghidra exports):
  1. Synthetic firmware blob present + Cortex-M IVT plausible
  2. analyzeHeadless / GHIDRA_HOME resolution (same rules as ghidra_decompile.py)
  3. Export scripts present under server/firmware-analysis/ghidra_scripts

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
import subprocess
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

FAKE_EXPORT_SUFFIXES = (
    ".functions.json",
    ".callgraph.json",
    ".dec.c",
    ".speeds.json",
    ".limits.c",
)


def _resolve_headless_detail() -> tuple[str | None, list[dict[str, Any]]]:
    """Mirror ghidra_decompile._headless_bin with per-path probe records."""
    probes: list[dict[str, Any]] = []

    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    probes.append({
        "path": "env:GHIDRA_HEADLESS",
        "value": direct or None,
        "status": "hit" if direct and Path(direct).exists() else (
            "set_but_missing" if direct else "unset"
        ),
    })
    if direct and Path(direct).exists():
        return direct, probes

    home = os.environ.get("GHIDRA_HOME", "").strip()
    home_path = Path(home) if home else None
    support = (home_path / "support" / "analyzeHeadless") if home_path else None
    probes.append({
        "path": "env:GHIDRA_HOME/support/analyzeHeadless",
        "value": str(support) if support else None,
        "ghidraHome": home or None,
        "status": (
            "hit" if support and support.exists() else (
                "set_but_missing" if home else "unset"
            )
        ),
    })
    if support and support.exists():
        return str(support), probes

    nested_hits: list[str] = []
    if home_path and home_path.is_dir():
        for child in sorted(home_path.glob("ghidra_*")):
            nested = child / "support" / "analyzeHeadless"
            if nested.exists():
                nested_hits.append(str(nested))
    probes.append({
        "path": "env:GHIDRA_HOME/ghidra_*/support/analyzeHeadless",
        "value": nested_hits[0] if nested_hits else None,
        "candidates": nested_hits,
        "status": "hit" if nested_hits else ("set_but_missing" if home else "unset"),
    })
    if nested_hits:
        return nested_hits[0], probes

    which = shutil.which("analyzeHeadless")
    probes.append({
        "path": "PATH:analyzeHeadless",
        "value": which,
        "status": "hit" if which else "absent",
    })
    if which:
        return which, probes

    opt = Path("/opt/ghidra")
    opt_hits = (
        [str(p) for p in sorted(opt.glob("ghidra_*/support/analyzeHeadless")) if p.exists()]
        if opt.is_dir()
        else []
    )
    probes.append({
        "path": "/opt/ghidra/ghidra_*/support/analyzeHeadless",
        "value": opt_hits[0] if opt_hits else None,
        "optGhidraDirExists": opt.is_dir(),
        "candidates": opt_hits,
        "status": "hit" if opt_hits else ("dir_missing" if not opt.is_dir() else "absent"),
    })
    if opt_hits:
        return opt_hits[0], probes

    return None, probes


def _java_probe() -> dict[str, Any]:
    java = shutil.which("java")
    version = None
    if java:
        try:
            proc = subprocess.run(
                [java, "-version"],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            # java -version writes to stderr
            version = (proc.stderr or proc.stdout or "").strip().splitlines()[:3]
        except Exception as exc:  # noqa: BLE001
            version = [f"probe_error:{type(exc).__name__}"]
    return {
        "javaOnPath": java,
        "versionLines": version,
        "impliesGhidra": False,
        "note": "OpenJDK/JRE alone is not a Ghidra install",
    }


def _driver_configured(repo: Path) -> dict[str, Any]:
    """Import ghidra_decompile.ghidra_configured if importable."""
    analysis = repo / "server" / "firmware-analysis"
    result: dict[str, Any] = {
        "modulePath": str(analysis),
        "importOk": False,
        "ghidraConfigured": None,
        "error": None,
    }
    if not analysis.is_dir():
        result["error"] = "firmware-analysis dir missing"
        return result
    sys_path_inserted = False
    if str(analysis) not in sys.path:
        sys.path.insert(0, str(analysis))
        sys_path_inserted = True
    try:
        from ghidra_decompile import ghidra_configured  # type: ignore

        result["importOk"] = True
        result["ghidraConfigured"] = bool(ghidra_configured())
    except Exception as exc:  # noqa: BLE001
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        if sys_path_inserted and sys.path and sys.path[0] == str(analysis):
            sys.path.pop(0)
    return result


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


def _scan_fake_exports(out_dir: Path | None) -> dict[str, Any]:
    """Refuse to treat leftover/fake exports as success when Ghidra is absent."""
    if out_dir is None or not out_dir.is_dir():
        return {"scanned": False, "suspectFiles": []}
    suspects: list[str] = []
    for p in sorted(out_dir.rglob("*")):
        if not p.is_file():
            continue
        name = p.name
        if name in ("proof_points.json", "proof_points.pretty.json", "prereqs.json", "env_probe.json"):
            continue
        if any(name.endswith(suf) or name == suf.lstrip(".") for suf in FAKE_EXPORT_SUFFIXES):
            # Allow only empty? No — any such file under out_dir when tools missing is suspect.
            suspects.append(str(p))
        if name in (
            "synthetic.functions.json",
            "synthetic.callgraph.json",
            "synthetic.dec.c",
        ):
            if str(p) not in suspects:
                suspects.append(str(p))
    return {"scanned": True, "outDir": str(out_dir), "suspectFiles": suspects}


def main() -> int:
    here = Path(__file__).resolve().parent
    repo = here.parents[2]
    default_bin = here / "synthetic_cortex_m_thumb.bin"
    # Prefer Cycle-9 copy; fall back to Cycle-8 asset path for operators
    cycle8_bin = repo / "research" / "cycle8" / "fixtures" / "synthetic_cortex_m_thumb.bin"
    default_scripts = repo / "server" / "firmware-analysis" / "ghidra_scripts"
    default_out = here / "out_validation" / "prereqs.json"

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bin", type=Path, default=default_bin)
    ap.add_argument("--script-dir", type=Path, default=default_scripts)
    ap.add_argument("--out", type=Path, default=default_out)
    ap.add_argument(
        "--scan-out-dir",
        type=Path,
        default=None,
        help="Optional out_synthetic dir to assert no fabricated Ghidra exports",
    )
    args = ap.parse_args()

    errors: list[str] = []
    notes: list[str] = []

    bin_path = args.bin
    if not bin_path.is_file() and cycle8_bin.is_file():
        notes.append(f"cycle9 bin missing; falling back to cycle8 fixture {cycle8_bin}")
        bin_path = cycle8_bin

    if not bin_path.is_file():
        errors.append(f"missing synthetic blob: {args.bin}")
        blob_meta: dict[str, Any] = {"present": False}
        ivt: dict[str, Any] = {"ok": False}
    else:
        raw = bin_path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        blob_meta = {
            "present": True,
            "path": str(bin_path),
            "size": len(raw),
            "sha256": digest,
            "sha256MatchesCycle7": digest == EXPECTED_SHA256,
            "readableSyntheticOnly": True,
            "notRealScooterFirmware": True,
        }
        if digest != EXPECTED_SHA256:
            notes.append(
                f"sha256={digest} differs from cycle7 expected {EXPECTED_SHA256} "
                "(still usable if IVT ok)"
            )
        ivt = _parse_ivt_lite(raw)
        if not ivt.get("ok"):
            errors.append("synthetic blob IVT is not Cortex-M plausible")
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

    headless, probes = _resolve_headless_detail()
    java = _java_probe()
    driver = _driver_configured(repo)
    fake_scan = _scan_fake_exports(args.scan_out_dir)

    ghidra_home = os.environ.get("GHIDRA_HOME", "").strip() or None
    ghidra_headless_env = os.environ.get("GHIDRA_HEADLESS", "").strip() or None

    if headless is None:
        cause_parts = [
            "GHIDRA_HOME unset" if not ghidra_home else f"GHIDRA_HOME={ghidra_home} but analyzeHeadless missing",
            "GHIDRA_HEADLESS unset" if not ghidra_headless_env else f"GHIDRA_HEADLESS={ghidra_headless_env} missing/not executable",
            "analyzeHeadless not on PATH",
            "/opt/ghidra absent or empty" if not Path("/opt/ghidra").is_dir() else "/opt/ghidra has no ghidra_*/support/analyzeHeadless",
        ]
        exact_cause = (
            "MISSING_PREREQUISITE: "
            + "; ".join(cause_parts)
            + ". Java present does not imply Ghidra."
        )
        notes.append(exact_cause)
        notes.append("Do NOT fabricate .functions.json / .callgraph.json / .dec.c.")
    else:
        exact_cause = None
        notes.append(f"headless={headless}")

    if fake_scan.get("suspectFiles"):
        # Soft note only during preflight when Ghidra unavailable — runner treats as error on SKIP path
        notes.append(
            "suspect_export_artifacts=" + ",".join(fake_scan["suspectFiles"])
        )

    if (
        driver.get("importOk")
        and driver.get("ghidraConfigured") is False
        and headless is None
    ):
        notes.append("ghidra_decompile.ghidra_configured()=False (matches probe)")
    elif (
        driver.get("importOk")
        and bool(driver.get("ghidraConfigured")) != (headless is not None)
    ):
        errors.append(
            "probe/driver mismatch: "
            f"headless={headless!r} vs ghidra_configured={driver.get('ghidraConfigured')!r}"
        )

    result = {
        "schemaVersion": 1,
        "kind": "ghidraPrereqValidation",
        "cycle": 9,
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
        "exactMissingCause": exact_cause,
        "environmentProbe": {
            "resolutionPaths": probes,
            "java": java,
            "driver": driver,
            "fakeExportScan": fake_scan,
        },
        "cycle9ProofPointMap": [
            {"id": 1, "name": "Import"},
            {"id": 2, "name": "Architecture"},
            {"id": 3, "name": "Static analysis"},
            {"id": 4, "name": "Function detection"},
            {"id": 5, "name": "Control-flow"},
            {"id": 6, "name": "JSON export"},
            {"id": 7, "name": "Error handling"},
        ],
        "errors": errors,
        "notes": notes,
        "hardBans": [
            "no real encrypted ZT3 plaintext reconstruction",
            "no Cycle-6 FIRM.bin.enc decrypt",
            "no fake Ghidra export artifacts when tools missing",
            "never claim successful Ghidra run without analyzeHeadless",
        ],
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    # Also write a focused env probe sibling for the report
    env_probe_path = args.out.parent / "env_probe.json"
    env_probe_path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "kind": "ghidraEnvironmentProbe",
                "cycle": 9,
                "agent": "B",
                "generatedAt": result["generatedAt"],
                "ghidraAvailable": result["ghidraAvailable"],
                "exactMissingCause": exact_cause,
                "analyzeHeadless": headless,
                "ghidraHomeEnv": ghidra_home,
                "ghidraHeadlessEnv": ghidra_headless_env,
                "resolutionPaths": probes,
                "java": java,
                "driver": driver,
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps(result, indent=2, ensure_ascii=False))
    print(f"Wrote {args.out}", file=sys.stderr)
    print(f"Wrote {env_probe_path}", file=sys.stderr)

    if errors:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
