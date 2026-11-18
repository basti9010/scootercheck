"""Run Ghidra analyzeHeadless on a plaintext firmware BIN and export decompiled C."""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any


def ghidra_configured() -> bool:
    return bool(_headless_bin())


def _headless_bin() -> str | None:
    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    if direct and Path(direct).exists():
        return direct
    home = os.environ.get("GHIDRA_HOME", "").strip()
    if home:
        home_path = Path(home)
        cand = home_path / "support" / "analyzeHeadless"
        if cand.exists():
            return str(cand)
        # Allow GHIDRA_HOME=/opt/ghidra when install lives in ghidra_*_PUBLIC/
        if home_path.is_dir():
            for child in sorted(home_path.glob("ghidra_*")):
                nested = child / "support" / "analyzeHeadless"
                if nested.exists():
                    return str(nested)
    which = shutil.which("analyzeHeadless")
    if which:
        return which
    # Common Hetzner layout
    for nested in sorted(Path("/opt/ghidra").glob("ghidra_*/support/analyzeHeadless")):
        if nested.exists():
            return str(nested)
    return None


def run_ghidra_decompile(
    plaintext_bin: Path,
    output_c: Path,
    *,
    processor: str = "ARM:LE:32:Cortex",
    base_addr: str = "0x08000000",
    timeout_sec: int = 600,
    speed_json: Path | None = None,
    limit_c: Path | None = None,
    functions_json: Path | None = None,
    callgraph_json: Path | None = None,
) -> tuple[bool, str]:
    headless = _headless_bin()
    if not headless:
        return False, "Ghidra not configured (set GHIDRA_HOME or GHIDRA_HEADLESS)"

    script_dir = Path(__file__).resolve().parent / "ghidra_scripts"
    if not (script_dir / "ExportAllDecompiled.java").exists():
        return False, f"missing ExportAllDecompiled.java in {script_dir}"

    output_c.parent.mkdir(parents=True, exist_ok=True)
    if speed_json is None:
        speed_json = output_c.with_suffix(".speeds.json")
    speed_json.parent.mkdir(parents=True, exist_ok=True)
    if limit_c is None:
        limit_c = output_c.with_suffix(".limits.c")
    limit_c.parent.mkdir(parents=True, exist_ok=True)
    if functions_json is None:
        functions_json = output_c.with_suffix(".functions.json")
    functions_json.parent.mkdir(parents=True, exist_ok=True)
    if callgraph_json is None:
        callgraph_json = output_c.with_suffix(".callgraph.json")
    callgraph_json.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ghidra-proj-") as proj:
        proj_dir = Path(proj)
        # analyzeHeadless <project_location> <project_name> [options]
        cmd = [
            headless,
            str(proj_dir),
            "ScooterCheckFW",
            "-import",
            str(plaintext_bin),
            "-processor",
            processor,
            "-cspec",
            "default",
            "-loader",
            "BinaryLoader",
            "-loader-baseAddr",
            base_addr,
            "-scriptPath",
            str(script_dir),
            "-postScript",
            "ExportAllDecompiled.java",
            str(output_c),
            "-postScript",
            "ExportSpeedXrefs.java",
            str(speed_json),
            "-postScript",
            "ExportLimitFunctions.java",
            str(limit_c),
            "-postScript",
            "ExportFunctionAnalysis.java",
            str(functions_json),
            "-postScript",
            "ExportCallGraph.java",
            str(callgraph_json),
            "-deleteProject",
        ]
        # Extra headless timeout buffer for Phase-2 exports (still capped by caller).
        timeout_sec = max(timeout_sec, int(os.environ.get("GHIDRA_TIMEOUT_SEC", str(timeout_sec)) or timeout_sec))
        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return False, "ghidra timed out"
        except OSError as e:
            return False, f"ghidra spawn failed: {e}"

        log_tail = ((proc.stderr or "") + "\n" + (proc.stdout or ""))[-2000:]
        if proc.returncode != 0:
            return False, f"ghidra exit {proc.returncode}: {log_tail}"
        if not output_c.exists() or output_c.stat().st_size == 0:
            return False, f"ghidra produced empty decompile: {log_tail}"
        notes = [f"decompiled {output_c.stat().st_size} bytes"]
        if speed_json.exists() and speed_json.stat().st_size > 0:
            notes.append(f"speedXrefs {speed_json.stat().st_size}B")
        if limit_c.exists() and limit_c.stat().st_size > 0:
            notes.append(f"limits.c {limit_c.stat().st_size}B")
        # Phase-2 exports are best-effort: missing files must not fail the whole decompile.
        if functions_json.exists() and functions_json.stat().st_size > 0:
            notes.append(f"functions.json {functions_json.stat().st_size}B")
        else:
            notes.append("functions.json=missing-or-empty")
        if callgraph_json.exists() and callgraph_json.stat().st_size > 0:
            notes.append(f"callgraph.json {callgraph_json.stat().st_size}B")
        else:
            notes.append("callgraph.json=missing-or-empty")
        return True, ", ".join(notes)


def load_speed_xrefs(speed_json: Path) -> dict[str, Any]:
    """Parse ExportSpeedXrefs JSON into deep-analysis speed findings."""
    import json

    from speed_extract import KNOWN_MAP

    if not speed_json.is_file():
        return {"ok": False, "speeds": [], "notes": ["ghidraXrefs=missing"]}
    try:
        data = json.loads(speed_json.read_text(encoding="utf-8"))
    except Exception as e:
        return {"ok": False, "speeds": [], "notes": [f"ghidraXrefs=badjson:{e}"]}

    packed = data.get("packed") or {}
    speeds: list[dict[str, Any]] = []
    for key, hits in packed.items():
        try:
            val = int(str(key).replace("0x", "").replace("0X", ""), 16)
        except ValueError:
            continue
        if val not in KNOWN_MAP:
            continue
        kmh, role = KNOWN_MAP[val]
        hit0 = hits[0] if isinstance(hits, list) and hits else {}
        addr = hit0.get("addr") if isinstance(hit0, dict) else None
        fn = hit0.get("fn") if isinstance(hit0, dict) else None
        evidence = f"Ghidra xref 0x{val:04X}"
        if fn:
            evidence += f" in {fn}"
        if addr:
            evidence += f" @ {addr}"
        if isinstance(hits, list) and len(hits) > 1:
            evidence += f" (+{len(hits) - 1} more)"
        speeds.append(
            {
                "id": f"ghidra-xref-{val:04x}",
                "kmh": kmh,
                "packedU16": val,
                "role": role,
                "evidence": evidence,
                "source": "serverDecompile",
                "confidence": "high",
            }
        )
    return {
        "ok": True,
        "speeds": sorted(speeds, key=lambda x: x["kmh"]),
        "notes": [f"ghidraXrefs=ok packed={len(speeds)} hits={data.get('hits')}"],
    }
