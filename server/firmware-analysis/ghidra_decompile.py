"""Run Ghidra analyzeHeadless on a plaintext firmware BIN and export decompiled C."""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def ghidra_configured() -> bool:
    return bool(_headless_bin())


def _headless_bin() -> str | None:
    direct = os.environ.get("GHIDRA_HEADLESS", "").strip()
    if direct and Path(direct).exists():
        return direct
    home = os.environ.get("GHIDRA_HOME", "").strip()
    if home:
        cand = Path(home) / "support" / "analyzeHeadless"
        if cand.exists():
            return str(cand)
    which = shutil.which("analyzeHeadless")
    return which


def run_ghidra_decompile(
    plaintext_bin: Path,
    output_c: Path,
    *,
    processor: str = "ARM:LE:32:Cortex",
    base_addr: str = "0x08000000",
    timeout_sec: int = 600,
) -> tuple[bool, str]:
    headless = _headless_bin()
    if not headless:
        return False, "Ghidra not configured (set GHIDRA_HOME or GHIDRA_HEADLESS)"

    script_dir = Path(__file__).resolve().parent / "ghidra_scripts"
    if not (script_dir / "ExportAllDecompiled.java").exists():
        return False, f"missing ExportAllDecompiled.java in {script_dir}"

    output_c.parent.mkdir(parents=True, exist_ok=True)
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
            "-deleteProject",
        ]
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
        return True, f"decompiled {output_c.stat().st_size} bytes"
