"""Short Unicorn probes with synthetic input vectors near speed immediates.

Does not boot the VCU. For each openCap/legalCap site, run a tiny window with
several register presets that mimic "both levers high" vs idle — if execution
progress differs, emit a combo hypothesis. Investigative only.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from board_pinouts import resolve_board
from speed_extract import KNOWN_MAP

ENABLE = os.environ.get("ENABLE_INPUT_PROBE", "1").strip() not in ("0", "false", "False")
BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
SRAM_BASE = 0x20000000
SRAM_SIZE = 0x20000
EMU_INSNS = 48
WINDOW_BEFORE = 24
WINDOW_AFTER = 80
MAX_SITES = 12


def analyze(
    bin_path: Path,
    *,
    models: list[str] | None = None,
    controller_type: str | None = None,
    display_name: str | None = None,
    filename: str | None = None,
) -> dict[str, Any]:
    if not ENABLE:
        return {"ok": False, "notes": ["input_probe=disabled"], "probes": [], "combos": [], "transitions": []}
    try:
        from unicorn import UC_ARCH_ARM, UC_HOOK_CODE, UC_MODE_THUMB, Uc, UcError
        from unicorn.arm_const import (
            UC_ARM_REG_PC,
            UC_ARM_REG_R0,
            UC_ARM_REG_R1,
            UC_ARM_REG_R2,
            UC_ARM_REG_R3,
            UC_ARM_REG_SP,
        )
    except ImportError:
        return {"ok": False, "notes": ["input_probe=unicorn missing"], "probes": [], "combos": [], "transitions": []}

    data = bin_path.read_bytes()
    if len(data) < 64:
        return {"ok": False, "notes": ["input_probe=bin too small"], "probes": [], "combos": [], "transitions": []}

    board = resolve_board(
        models=models,
        controller_type=controller_type,
        display_name=display_name,
        filename=filename,
    )

    # Prefer openCap + legalCap sites
    sites: list[dict[str, Any]] = []
    for i in range(0, len(data) - 1):
        packed = data[i] | (data[i + 1] << 8)
        if packed not in KNOWN_MAP:
            continue
        kmh, role = KNOWN_MAP[packed]
        if role not in {"openCap", "legalCap"}:
            continue
        if i < 16:
            continue
        sites.append({"offset": i, "packed": packed, "kmh": kmh, "role": role})
    # Dedup by packed keep 2 offsets
    by_p: dict[int, list[dict[str, Any]]] = {}
    for s in sites:
        by_p.setdefault(s["packed"], []).append(s)
    selected: list[dict[str, Any]] = []
    for lst in by_p.values():
        selected.extend(lst[:2])
    selected = selected[:MAX_SITES]

    map_base = BASE & ~0xFFF
    map_size = max(((len(data) + 0xFFF) // 0x1000) * 0x1000, 0x1000)

    vectors = [
        ("idle", {UC_ARM_REG_R0: 0, UC_ARM_REG_R1: 0, UC_ARM_REG_R2: 0, UC_ARM_REG_R3: 0}),
        ("throttle_high", {UC_ARM_REG_R0: 0xFFF, UC_ARM_REG_R1: 0, UC_ARM_REG_R2: 0, UC_ARM_REG_R3: 0}),
        ("brake_high", {UC_ARM_REG_R0: 0, UC_ARM_REG_R1: 0xFFF, UC_ARM_REG_R2: 0, UC_ARM_REG_R3: 0}),
        (
            "both_levers_high",
            {UC_ARM_REG_R0: 0xFFF, UC_ARM_REG_R1: 0xFFF, UC_ARM_REG_R2: 1, UC_ARM_REG_R3: 0},
        ),
        (
            "both_plus_flag",
            {UC_ARM_REG_R0: 0xFFF, UC_ARM_REG_R1: 0xFFF, UC_ARM_REG_R2: 3, UC_ARM_REG_R3: 1},
        ),
    ]

    probes: list[dict[str, Any]] = []
    sensitive = 0

    for site in selected:
        off = site["offset"]
        start = max(0, off - WINDOW_BEFORE) & ~1
        end = min(len(data), off + WINDOW_AFTER)
        if end - start < 8:
            continue
        results: dict[str, int] = {}
        for name, regs in vectors:
            n = _run(
                data,
                start_off=start,
                end_off=end,
                regs=regs,
                map_base=map_base,
                map_size=map_size,
                Uc=Uc,
                UcError=UcError,
                UC_ARCH_ARM=UC_ARCH_ARM,
                UC_MODE_THUMB=UC_MODE_THUMB,
                UC_HOOK_CODE=UC_HOOK_CODE,
                UC_ARM_REG_PC=UC_ARM_REG_PC,
                UC_ARM_REG_SP=UC_ARM_REG_SP,
            )
            results[name] = n
        # Sensitivity: both_levers differs from idle
        idle_n = results.get("idle", 0)
        both_n = results.get("both_levers_high", 0)
        flag_n = results.get("both_plus_flag", 0)
        delta = max(abs(both_n - idle_n), abs(flag_n - idle_n))
        if delta >= 2 and (both_n > 0 or flag_n > 0):
            sensitive += 1
        probes.append(
            {
                "packed": site["packed"],
                "kmh": site["kmh"],
                "role": site["role"],
                "addr": f"{BASE + off:#x}",
                "vectors": results,
                "deltaVsIdle": delta,
                "sensitive": delta >= 2,
            }
        )

    combos: list[str] = []
    transitions: list[dict[str, Any]] = []
    if sensitive > 0:
        hyp = (
            board.get("defaultComboHypothesis")
            if board
            else "Gas + Bremse (+ Power/Flag) — Live-Test nötig"
        )
        combos.append(
            f"Input-Probe: {sensitive} Speed-Stelle(n) reagieren auf Dual-Hebel-Registerpreset "
            f"→ Hypothese: {hyp}"
        )
        transitions.append(
            {
                "id": "probe-tr-dual-input",
                "title": "Eingangs-Probe (Unicorn)",
                "trigger": hyp,
                "effect": "Ausführungsdifferenz idle vs. beide Hebel high an Limit-Fenster",
                "evidence": f"sensitiveSites={sensitive}/{len(probes)}",
                "source": "serverEmulation",
                "confidence": "low",
            }
        )
    else:
        combos.append(
            "Input-Probe: keine klare Dual-Hebel-Sensitivität in Kurzfenstern "
            "(Kombi nicht aus Emulation ableitbar)"
        )

    return {
        "ok": True,
        "notes": [
            f"input_probe=ok sites={len(probes)} sensitive={sensitive} "
            f"board={(board or {}).get('id') or 'none'}"
        ],
        "probes": probes[:24],
        "combos": combos,
        "transitions": transitions,
        "sensitiveSites": sensitive,
    }


def merge_into_result(result: dict[str, Any], probe: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(probe.get("notes") or [])
    result["notes"] = notes
    if not probe.get("ok"):
        return result
    if probe.get("probes"):
        result["inputProbes"] = probe["probes"]
    combos = list(result.get("comboSummaries") or [])
    for c in probe.get("combos") or []:
        if c not in combos:
            combos.append(c)
    result["comboSummaries"] = combos
    transitions = list(result.get("modeTransitions") or [])
    seen = {(t.get("id"), t.get("title")) for t in transitions if isinstance(t, dict)}
    for t in probe.get("transitions") or []:
        key = (t.get("id"), t.get("title"))
        if key in seen:
            continue
        seen.add(key)
        transitions.append(t)
    result["modeTransitions"] = transitions
    if probe.get("sensitiveSites"):
        sources = list(result.get("sources") or [])
        if "serverEmulation" not in sources:
            sources.append("serverEmulation")
            result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + Input-Probe.").strip()
        result["quality"] = quality
    return result


def _run(
    data: bytes,
    *,
    start_off: int,
    end_off: int,
    regs: dict[Any, int],
    map_base: int,
    map_size: int,
    Uc: Any,
    UcError: Any,
    UC_ARCH_ARM: Any,
    UC_MODE_THUMB: Any,
    UC_HOOK_CODE: Any,
    UC_ARM_REG_PC: Any,
    UC_ARM_REG_SP: Any,
) -> int:
    entry = BASE + start_off
    pc = entry | 1
    insn_count = {"n": 0}
    try:
        mu = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
        mu.mem_map(map_base, map_size)
        mu.mem_write(BASE, data)
        mu.mem_map(SRAM_BASE, SRAM_SIZE)
        mu.reg_write(UC_ARM_REG_SP, SRAM_BASE + SRAM_SIZE - 0x100)
        for reg, val in regs.items():
            mu.reg_write(reg, val)
        mu.reg_write(UC_ARM_REG_PC, pc)

        def _hook(uc: Any, address: int, size: int, user_data: Any) -> None:
            insn_count["n"] += 1
            if insn_count["n"] >= EMU_INSNS:
                uc.emu_stop()

        mu.hook_add(UC_HOOK_CODE, _hook)
        try:
            mu.emu_start(pc, BASE + end_off, count=EMU_INSNS)
        except UcError:
            pass
        return insn_count["n"]
    except Exception:
        return 0
