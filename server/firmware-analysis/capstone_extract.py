"""Capstone ARM disassembly pass — find CMP/MOV immediates matching packed speeds."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from speed_extract import KNOWN_MAP

ENABLE_CAPSTONE = os.environ.get("ENABLE_CAPSTONE", "1").strip() not in ("0", "false", "False")
BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)


def capstone_configured() -> bool:
    if not ENABLE_CAPSTONE:
        return False
    try:
        import capstone  # noqa: F401
        return True
    except ImportError:
        return False


def analyze_firmware(bin_path: Path) -> dict[str, Any]:
    if not capstone_configured():
        return {
            "ok": False,
            "speeds": [],
            "notes": ["capstone=skipped (not installed or ENABLE_CAPSTONE=0)"],
        }
    try:
        from capstone import CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB, Cs
    except ImportError:
        return {"ok": False, "speeds": [], "notes": ["capstone=import failed"]}

    data = bin_path.read_bytes()
    if not data:
        return {"ok": False, "speeds": [], "notes": ["capstone=empty"]}

    found: dict[int, dict[str, Any]] = {}
    notes: list[str] = []

    for mode_name, mode in (("arm", CS_MODE_ARM), ("thumb", CS_MODE_THUMB)):
        md = Cs(CS_ARCH_ARM, mode)
        md.detail = True
        try:
            for insn in md.disasm(data, BASE):
                imm = _imm_from_insn(insn)
                if imm is None or imm not in KNOWN_MAP:
                    continue
                if imm in found:
                    continue
                kmh, role = KNOWN_MAP[imm]
                found[imm] = {
                    "id": f"cs-{mode_name}-{imm:04x}",
                    "kmh": kmh,
                    "packedU16": imm,
                    "role": role,
                    "evidence": f"capstone {mode_name} {insn.mnemonic} {insn.op_str} @ {insn.address:#x}",
                    "source": "serverCapstone",
                    "confidence": "high",
                }
        except Exception as e:
            notes.append(f"capstone={mode_name} err:{e}")

    speeds = sorted(found.values(), key=lambda x: x["kmh"])
    notes.append(f"capstone=ok speeds={len(speeds)}")
    return {"ok": True, "speeds": speeds, "notes": notes}


def merge_capstone_into_result(result: dict[str, Any], cs: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(cs.get("notes") or [])
    result["notes"] = notes
    if not cs.get("ok"):
        return result

    by_packed: dict[Any, dict[str, Any]] = {
        s.get("packedU16"): s for s in (result.get("speedLimits") or []) if s.get("packedU16") is not None
    }
    added = 0
    for s in cs.get("speeds") or []:
        p = s.get("packedU16")
        if p not in by_packed:
            by_packed[p] = s
            added += 1
    result["speedLimits"] = sorted(by_packed.values(), key=lambda x: x["kmh"])
    if result["speedLimits"]:
        result["maxSpeedKmhInCode"] = max(s["kmh"] for s in result["speedLimits"])

    sources = list(result.get("sources") or [])
    if added and "serverCapstone" not in sources:
        sources.append("serverCapstone")
        result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["hasDeterministicBasis"] = True
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + Capstone.").strip()
        result["quality"] = quality
    return result


def _imm_from_insn(insn: Any) -> int | None:
    # Prefer Capstone operand detail when available
    try:
        for op in insn.operands:
            if getattr(op, "type", None) is None:
                continue
            # ARM_OP_IMM == 2 typically
            if int(op.type) == 2:
                val = int(op.imm) & 0xFFFF
                if val in KNOWN_MAP:
                    return val
    except Exception:
        pass
    # Fallback: parse immediates from op_str (#0x1600 / #5632)
    import re

    op = insn.op_str or ""
    for m in re.finditer(r"#(0x[0-9a-fA-F]+|\d+)", op):
        raw = m.group(1)
        try:
            val = int(raw, 0)  # handles 0x… and decimal
        except ValueError:
            continue
        val &= 0xFFFF
        if val in KNOWN_MAP:
            return val
    return None
