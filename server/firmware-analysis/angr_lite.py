"""Lightweight path / predecessor analysis around speed immediates.

Full angr is heavy for a 4 GB VPS. This module:
1. Tries optional `angr` CFGFast on a size-capped slice (ENABLE_ANGR=1).
2. Always falls back to Capstone backward-walk for branch predecessors.

Adds notes + optional modeTransitions when a compare to packed speed is
reached via conditional branches (investigative, not proof).
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from speed_extract import KNOWN_MAP

ENABLE_ANGR = os.environ.get("ENABLE_ANGR", "1").strip() not in ("0", "false", "False")
BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
ANGR_MAX_BYTES = int(os.environ.get("ANGR_MAX_BYTES", str(512 * 1024)) or str(512 * 1024))
MAX_PACKED = 8
BACKWALK_DEPTH = 12


def angr_configured() -> bool:
    """True if either Capstone fallback or real angr is available."""
    try:
        import capstone  # noqa: F401

        return True
    except ImportError:
        return False


def angr_engine_available() -> bool:
    if not ENABLE_ANGR:
        return False
    try:
        import angr  # noqa: F401

        return True
    except ImportError:
        return False


def analyze_firmware(bin_path: Path) -> dict[str, Any]:
    if not angr_configured():
        return {
            "ok": False,
            "notes": ["angr_lite=skipped (capstone missing)"],
            "transitions": [],
            "pathHints": [],
        }

    data = bin_path.read_bytes()
    if not data:
        return {"ok": False, "notes": ["angr_lite=empty"], "transitions": [], "pathHints": []}

    packed_offsets = _packed_offsets(data)
    if not packed_offsets:
        return {
            "ok": True,
            "notes": ["angr_lite=ok no packed sites"],
            "transitions": [],
            "pathHints": [],
        }

    hints: list[dict[str, Any]] = []
    transitions: list[dict[str, Any]] = []
    notes: list[str] = []

    # Capstone backward walk (always)
    for packed, offsets in list(packed_offsets.items())[:MAX_PACKED]:
        kmh, role = KNOWN_MAP[packed]
        for off in offsets[:2]:
            preds = _capstone_predecessors(data, off)
            hint = {
                "packed": packed,
                "kmh": kmh,
                "role": role,
                "offset": off,
                "addr": f"{BASE + off:#x}",
                "predecessors": preds[:8],
                "engine": "capstone",
            }
            hints.append(hint)
            if preds:
                transitions.append(
                    {
                        "id": f"path-{packed:04x}-{off}",
                        "title": f"Pfad zu {int(kmh)} km/h (0x{packed:04X})",
                        "trigger": "Bedingter Sprung/Compare in Nähe (Capstone-Rückwärts)",
                        "effect": f"Immediate 0x{packed:04X} erreichbar aus {len(preds)} Vorgänger-Insn",
                        "evidence": "; ".join(preds[:3]) or f"@{BASE + off:#x}",
                        "source": "serverAngr",
                        "confidence": "low",
                    }
                )

    # Optional real angr on truncated image
    if angr_engine_available() and len(data) <= ANGR_MAX_BYTES:
        try:
            angr_hints = _angr_cfg_hints(data, packed_offsets)
            hints.extend(angr_hints)
            notes.append(f"angr=CFGFast hints={len(angr_hints)}")
        except Exception as e:
            notes.append(f"angr=failed:{e}")
    elif angr_engine_available():
        notes.append(f"angr=skipped (bin {len(data)} > ANGR_MAX_BYTES={ANGR_MAX_BYTES})")
    else:
        notes.append("angr=engine not installed — Capstone-Pfadanalyse aktiv")

    notes.insert(0, f"angr_lite=ok hints={len(hints)} transitions={len(transitions)}")
    return {
        "ok": True,
        "notes": notes,
        "transitions": transitions[:20],
        "pathHints": hints[:40],
    }


def merge_angr_into_result(result: dict[str, Any], ang: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(ang.get("notes") or [])
    result["notes"] = notes
    if not ang.get("ok"):
        return result

    if ang.get("pathHints"):
        result["pathHints"] = ang["pathHints"]

    transitions = list(result.get("modeTransitions") or [])
    seen = {(t.get("title"), t.get("trigger")) for t in transitions if isinstance(t, dict)}
    added = 0
    for t in ang.get("transitions") or []:
        key = (t.get("title"), t.get("trigger"))
        if key in seen:
            continue
        seen.add(key)
        transitions.append(t)
        added += 1
    result["modeTransitions"] = transitions

    sources = list(result.get("sources") or [])
    if (added or ang.get("pathHints")) and "serverAngr" not in sources:
        sources.append("serverAngr")
        result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + Pfadanalyse.").strip()
        result["quality"] = quality
    return result


def _packed_offsets(data: bytes) -> dict[int, list[int]]:
    out: dict[int, list[int]] = {}
    for i in range(0, len(data) - 1):
        packed = data[i] | (data[i + 1] << 8)
        if packed in KNOWN_MAP:
            out.setdefault(packed, []).append(i)
    return out


def _capstone_predecessors(data: bytes, offset: int) -> list[str]:
    try:
        from capstone import CS_ARCH_ARM, CS_MODE_THUMB, Cs
    except ImportError:
        return []

    start = max(0, offset - 64)
    chunk = data[start:offset]
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    md.detail = True
    insns = list(md.disasm(chunk, BASE + start))
    preds: list[str] = []
    for insn in insns[-BACKWALK_DEPTH:]:
        mnem = (insn.mnemonic or "").lower()
        if mnem.startswith("b") or mnem in {"cmp", "cmn", "tst", "teq", "cbz", "cbnz", "it"}:
            preds.append(f"{insn.address:#x}: {insn.mnemonic} {insn.op_str}")
    return preds


def _angr_cfg_hints(data: bytes, packed_offsets: dict[int, list[int]]) -> list[dict[str, Any]]:
    import angr

    # Load as blob at BASE
    p = angr.Project(
        data,
        main_opts={"backend": "blob", "arch": "ARMEL", "base_addr": BASE, "entry_point": BASE},
        auto_load_libs=False,
    )
    cfg = p.analyses.CFGFast(data_references=True, normalize=True)
    hints: list[dict[str, Any]] = []
    for packed, offsets in list(packed_offsets.items())[:MAX_PACKED]:
        kmh, role = KNOWN_MAP[packed]
        for off in offsets[:1]:
            addr = BASE + off
            node = cfg.model.get_any_node(addr, anyaddr=True)
            preds = []
            if node is not None:
                for pred in cfg.model.get_predecessors(node)[:6]:
                    preds.append(f"{pred.addr:#x}")
            hints.append(
                {
                    "packed": packed,
                    "kmh": kmh,
                    "role": role,
                    "offset": off,
                    "addr": f"{addr:#x}",
                    "predecessors": preds,
                    "engine": "angr",
                }
            )
    return hints
