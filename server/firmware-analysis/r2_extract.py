"""Optional radare2 pass on decrypted firmware (parallel insight to Ghidra).

Finds packed speed immediates via byte search + short disasm windows, plus
interesting strings. Requires `r2` on PATH (apt: radare2).
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from speed_extract import KNOWN_MAP

R2_TIMEOUT_SEC = int(os.environ.get("R2_TIMEOUT_SEC", "90") or "90")
GHIDRA_BASE_ADDR = os.environ.get("GHIDRA_BASE_ADDR", "0x08000000").strip() or "0x08000000"
ENABLE_R2 = os.environ.get("ENABLE_R2", "1").strip() not in ("0", "false", "False")


def r2_configured() -> bool:
    return ENABLE_R2 and shutil.which("r2") is not None


def analyze_firmware(bin_path: Path) -> dict[str, Any]:
    """Return {speeds, notes, stringsSample, ok}."""
    if not r2_configured():
        return {"ok": False, "speeds": [], "notes": ["r2=skipped (not installed or ENABLE_R2=0)"], "stringsSample": []}
    if not bin_path.is_file():
        return {"ok": False, "speeds": [], "notes": ["r2=skipped (missing bin)"], "stringsSample": []}

    base = GHIDRA_BASE_ADDR
    # Build search commands for each known packed LE u16
    search_cmds: list[str] = [
        "e scr.color=0",
        "e bin.cache=true",
        "e asm.arch=arm",
        "e asm.bits=32",
        "e asm.cpu=cortex",
        f"omb. {base}",
    ]
    for packed in sorted(KNOWN_MAP.keys()):
        lo = packed & 0xFF
        hi = (packed >> 8) & 0xFF
        search_cmds.append(f"/x {lo:02x}{hi:02x}")

    search_cmds.append("izz")
    script = ";".join(search_cmds)

    try:
        proc = subprocess.run(
            ["r2", "-2", "-q", "-c", script, str(bin_path)],
            capture_output=True,
            text=True,
            timeout=R2_TIMEOUT_SEC,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {"ok": False, "speeds": [], "notes": ["r2=timeout"], "stringsSample": []}
    except FileNotFoundError:
        return {"ok": False, "speeds": [], "notes": ["r2=not found"], "stringsSample": []}

    out = (proc.stdout or "") + "\n" + (proc.stderr or "")
    speeds = _parse_speed_hits(out)
    strings = _parse_interesting_strings(out)
    notes = [f"r2=ok hits={len(speeds)} strings={len(strings)} exit={proc.returncode}"]
    if proc.returncode != 0 and not speeds:
        notes.append(f"r2=warn exit {proc.returncode}")
    return {"ok": True, "speeds": speeds, "notes": notes, "stringsSample": strings[:40]}


def _parse_speed_hits(output: str) -> list[dict[str, Any]]:
    """Parse r2 `/x` hit lines like: 0x08001234 hit0_0 0016"""
    found: dict[int, dict[str, Any]] = {}
    # Examples: "0x08001abc hit0_0 0016" or "0x08001abc 00 16"
    hit_re = re.compile(
        r"(0x[0-9a-fA-F]+)\s+hit\d+_\d+\s+([0-9a-fA-F]{4})",
        re.IGNORECASE,
    )
    for m in hit_re.finditer(output):
        addr = m.group(1)
        hx = m.group(2)
        try:
            # r2 prints bytes in search order; for /x 0016 → "0016" = LE 0x1600
            b0 = int(hx[0:2], 16)
            b1 = int(hx[2:4], 16)
            packed = b0 | (b1 << 8)
        except ValueError:
            continue
        if packed not in KNOWN_MAP or packed in found:
            continue
        kmh, role = KNOWN_MAP[packed]
        found[packed] = {
            "id": f"r2-{packed:04x}",
            "kmh": kmh,
            "packedU16": packed,
            "role": role,
            "evidence": f"r2 /x @{addr} → 0x{packed:04X}",
            "source": "serverR2",
            "confidence": "high",
        }
    return sorted(found.values(), key=lambda x: x["kmh"])


def _parse_interesting_strings(output: str) -> list[str]:
    keys = re.compile(
        r"(speed|limit|throttle|brake|mode|region|unlock|soft|km/h|kmh|vcu|mcu)",
        re.I,
    )
    out: list[str] = []
    seen: set[str] = set()
    for line in output.splitlines():
        # izz lines often: "0x........ 12 13 ascii some_string"
        if "ascii" not in line.lower() and "wide" not in line.lower():
            # also accept plain quoted leftovers
            if not keys.search(line):
                continue
        if not keys.search(line):
            continue
        s = line.strip()
        if len(s) < 8 or s in seen:
            continue
        seen.add(s)
        out.append(s[:160])
        if len(out) >= 40:
            break
    return out


def merge_r2_into_result(result: dict[str, Any], r2: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(r2.get("notes") or [])
    result["notes"] = notes

    if not r2.get("ok"):
        return result

    by_packed: dict[Any, dict[str, Any]] = {
        s.get("packedU16"): s for s in (result.get("speedLimits") or []) if s.get("packedU16") is not None
    }
    added = 0
    for s in r2.get("speeds") or []:
        p = s.get("packedU16")
        if p not in by_packed:
            by_packed[p] = s
            added += 1
    result["speedLimits"] = sorted(by_packed.values(), key=lambda x: x["kmh"])
    if result["speedLimits"]:
        result["maxSpeedKmhInCode"] = max(s["kmh"] for s in result["speedLimits"])
        legals = [s["kmh"] for s in result["speedLimits"] if s.get("role") == "legalCap"]
        result["legalCapKmhInCode"] = min(legals) if legals else result.get("legalCapKmhInCode")

    sources = list(result.get("sources") or [])
    if "serverR2" not in sources and (r2.get("speeds") or r2.get("stringsSample")):
        sources.append("serverR2")
    result["sources"] = sources

    if r2.get("stringsSample"):
        result["r2StringsSample"] = r2["stringsSample"]
        notes.append(f"r2Strings={len(r2['stringsSample'])}")
        result["notes"] = notes

    quality = dict(result.get("quality") or {})
    if added or r2.get("speeds"):
        quality["hasDeterministicBasis"] = True
        summary = (quality.get("summary") or "").rstrip()
        quality["summary"] = (summary + " + radare2.").strip()
    result["quality"] = quality
    return result
