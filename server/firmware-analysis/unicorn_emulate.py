"""Lightweight Unicorn emulation around packed speed immediates.

Does NOT boot the full VCU — only short windows around sites that contain
known packed speeds (0x1600, 0x6300, …). Shows the constant sits in code that
can start executing, not that it is the live vehicle limit.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from speed_extract import KNOWN_MAP

ENABLE_UNICORN = os.environ.get("ENABLE_UNICORN", "1").strip() not in ("0", "false", "False")
BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
SRAM_BASE = 0x20000000
SRAM_SIZE = 0x20000
MAX_SITES = 24
EMU_INSNS = 64
WINDOW_BEFORE = 32
WINDOW_AFTER = 96


def unicorn_configured() -> bool:
    if not ENABLE_UNICORN:
        return False
    try:
        import unicorn  # noqa: F401

        return True
    except ImportError:
        return False


def analyze_firmware(bin_path: Path) -> dict[str, Any]:
    if not unicorn_configured():
        return {
            "ok": False,
            "speeds": [],
            "notes": ["unicorn=skipped (not installed or ENABLE_UNICORN=0)"],
            "sites": [],
        }
    try:
        from unicorn import UC_ARCH_ARM, UC_HOOK_CODE, UC_MODE_ARM, UC_MODE_THUMB, Uc, UcError
        from unicorn.arm_const import UC_ARM_REG_PC, UC_ARM_REG_SP
    except ImportError:
        return {"ok": False, "speeds": [], "notes": ["unicorn=import failed"], "sites": []}

    data = bin_path.read_bytes()
    if len(data) < 64:
        return {"ok": False, "speeds": [], "notes": ["unicorn=bin too small"], "sites": []}

    sites = _find_imm_sites(data)
    if not sites:
        return {
            "ok": True,
            "speeds": [],
            "notes": ["unicorn=ok sites=0 (no packed immediates)"],
            "sites": [],
        }

    executed: dict[int, dict[str, Any]] = {}
    site_reports: list[dict[str, Any]] = []
    errors = 0

    map_base = BASE & ~0xFFF
    map_size = ((len(data) + 0xFFF) // 0x1000) * 0x1000
    map_size = max(map_size, 0x1000)

    for site in sites[:MAX_SITES]:
        packed = site["packed"]
        off = site["offset"]
        mode = site["mode"]
        start = max(0, off - WINDOW_BEFORE)
        start = start & (~1 if mode == "thumb" else ~3)
        end = min(len(data), off + WINDOW_AFTER)
        if end - start < 8:
            continue

        entry = BASE + start
        pc = entry | (1 if mode == "thumb" else 0)
        uc_mode = UC_MODE_THUMB if mode == "thumb" else UC_MODE_ARM
        insn_count = {"n": 0}
        hit = False
        try:
            mu = Uc(UC_ARCH_ARM, uc_mode)
            mu.mem_map(map_base, map_size)
            mu.mem_write(BASE, data)
            mu.mem_map(SRAM_BASE, SRAM_SIZE)
            mu.reg_write(UC_ARM_REG_SP, SRAM_BASE + SRAM_SIZE - 0x100)
            mu.reg_write(UC_ARM_REG_PC, pc)

            def _hook(uc: Any, address: int, size: int, user_data: Any) -> None:
                insn_count["n"] += 1
                if insn_count["n"] >= EMU_INSNS:
                    uc.emu_stop()

            mu.hook_add(UC_HOOK_CODE, _hook)
            try:
                mu.emu_start(pc, BASE + end, count=EMU_INSNS)
            except UcError:
                pass
            hit = insn_count["n"] > 0
        except Exception:
            errors += 1
            continue

        kmh, role = KNOWN_MAP[packed]
        site_reports.append(
            {
                "packed": packed,
                "kmh": kmh,
                "offset": off,
                "mode": mode,
                "executed": hit,
                "insns": insn_count["n"],
                "addr": f"{BASE + off:#x}",
            }
        )
        if hit and packed not in executed:
            executed[packed] = {
                "id": f"emu-{packed:04x}",
                "kmh": kmh,
                "packedU16": packed,
                "role": role,
                "evidence": (
                    f"Unicorn short-window @{BASE + off:#x} "
                    f"({mode}, {insn_count['n']} insn)"
                ),
                "source": "serverEmulation",
                "confidence": "medium",
            }

    speeds = sorted(executed.values(), key=lambda x: x["kmh"])
    notes = [
        f"unicorn=ok sites={len(site_reports)} executed={len(speeds)} errors={errors}",
        "Emulation = kurzes Fenster um Speed-Immediate, kein vollständiger Firmware-Boot.",
    ]
    return {"ok": True, "speeds": speeds, "notes": notes, "sites": site_reports[:40]}


def merge_unicorn_into_result(result: dict[str, Any], uni: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(uni.get("notes") or [])
    result["notes"] = notes
    if not uni.get("ok"):
        return result

    by_packed: dict[Any, dict[str, Any]] = {
        s.get("packedU16"): s
        for s in (result.get("speedLimits") or [])
        if s.get("packedU16") is not None
    }
    added = 0
    for s in uni.get("speeds") or []:
        p = s.get("packedU16")
        if p not in by_packed:
            by_packed[p] = s
            added += 1
        else:
            ev = str(by_packed[p].get("evidence") or "")
            if "Unicorn" not in ev:
                by_packed[p]["evidence"] = (ev + " · " + str(s.get("evidence") or "")).strip(" ·")
    result["speedLimits"] = sorted(by_packed.values(), key=lambda x: x["kmh"])
    if uni.get("sites"):
        result["emulationSites"] = uni["sites"]

    sources = list(result.get("sources") or [])
    if (added or uni.get("speeds")) and "serverEmulation" not in sources:
        sources.append("serverEmulation")
        result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["hasDeterministicBasis"] = True
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + Unicorn.").strip()
        result["quality"] = quality
    return result


def _find_imm_sites(data: bytes) -> list[dict[str, Any]]:
    raw: list[dict[str, Any]] = []
    for i in range(0, len(data) - 1):
        packed = data[i] | (data[i + 1] << 8)
        if packed in KNOWN_MAP:
            raw.append({"offset": i, "packed": packed})

    by_p: dict[int, list[dict[str, Any]]] = {}
    for s in raw:
        by_p.setdefault(s["packed"], []).append(s)

    out: list[dict[str, Any]] = []
    for packed, lst in by_p.items():
        for s in lst[:3]:
            out.append({**s, "mode": _guess_mode(data, s["offset"])})
    return out


def _guess_mode(data: bytes, offset: int) -> str:
    try:
        from capstone import CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB, Cs
    except ImportError:
        return "thumb"

    start = max(0, offset - 4)
    chunk = data[start : offset + 8]
    t_ok = sum(1 for _ in Cs(CS_ARCH_ARM, CS_MODE_THUMB).disasm(chunk, BASE + start))
    a_ok = sum(1 for _ in Cs(CS_ARCH_ARM, CS_MODE_ARM).disasm(chunk, BASE + start))
    return "thumb" if t_ok >= a_ok else "arm"
