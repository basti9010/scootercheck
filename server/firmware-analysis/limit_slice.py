"""Backward-slice around packed speed immediates → input-check hypotheses.

Capstone-based (no angr required): from each speed immediate, walk
predecessors looking for cmp/tst/ldr against GPIO/ADC-ish literals, then
map hits through board_pinouts.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from board_pinouts import label_addr, resolve_board, string_roles
from speed_extract import KNOWN_MAP

BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
BACK_BYTES = int(os.environ.get("LIMIT_SLICE_BACK_BYTES", "160") or "160")
MAX_SITES = int(os.environ.get("LIMIT_SLICE_MAX_SITES", "24") or "24")
ENABLE = os.environ.get("ENABLE_LIMIT_SLICE", "1").strip() not in ("0", "false", "False")


def analyze(
    bin_path: Path,
    *,
    models: list[str] | None = None,
    controller_type: str | None = None,
    display_name: str | None = None,
    filename: str | None = None,
    decompiled_text: str | None = None,
    limit_c_text: str | None = None,
) -> dict[str, Any]:
    if not ENABLE:
        return {"ok": False, "notes": ["limit_slice=disabled"], "slices": [], "combos": [], "inputs": [], "transitions": []}

    try:
        from capstone import CS_ARCH_ARM, CS_MODE_THUMB, Cs
    except ImportError:
        return {"ok": False, "notes": ["limit_slice=capstone missing"], "slices": [], "combos": [], "inputs": [], "transitions": []}

    data = bin_path.read_bytes()
    if len(data) < 64:
        return {"ok": False, "notes": ["limit_slice=bin too small"], "slices": [], "combos": [], "inputs": [], "transitions": []}

    board = resolve_board(
        models=models,
        controller_type=controller_type,
        display_name=display_name,
        filename=filename,
    )
    sites = _speed_sites(data)
    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    md.detail = True

    slices: list[dict[str, Any]] = []
    role_hits: set[str] = set()
    cmp_near_speed = 0

    for site in sites[:MAX_SITES]:
        off = site["offset"]
        if off < 16:
            continue
        start = max(0, off - BACK_BYTES)
        chunk = data[start:off]
        preds: list[str] = []
        pin_labels: list[dict[str, Any]] = []
        for insn in md.disasm(chunk, BASE + start):
            mnem = (insn.mnemonic or "").lower()
            op = insn.op_str or ""
            line = f"{insn.address:#x}: {insn.mnemonic} {op}"
            interesting = mnem.startswith("b") or mnem in {
                "cmp", "cmn", "tst", "teq", "cbz", "cbnz", "it",
                "ldr", "ldrh", "ldrb", "mov", "movw", "movt",
            }
            if not interesting:
                continue
            preds.append(line)
            # Absolute addresses in operands (0x40xxxxxx peripheral window)
            for tok in op.replace(",", " ").split():
                tok = tok.strip("#")
                if tok.lower().startswith("0x"):
                    try:
                        addr = int(tok, 16)
                    except ValueError:
                        continue
                    if 0x40000000 <= addr <= 0x50000000:
                        pin_labels.extend(label_addr(board, addr))
            if mnem in {"cmp", "cmn", "tst"} and abs(insn.address - (BASE + off)) < 48:
                cmp_near_speed += 1

        # Keep last relevant preds
        preds = preds[-14:]
        pin_labels = _uniq_pins(pin_labels)
        for p in pin_labels:
            if p.get("role"):
                role_hits.add(str(p["role"]))

        kmh, role = KNOWN_MAP[site["packed"]]
        slices.append(
            {
                "packed": site["packed"],
                "kmh": kmh,
                "role": role,
                "offset": off,
                "addr": f"{BASE + off:#x}",
                "predecessors": preds,
                "pinLabels": pin_labels,
                "engine": "capstone-backslice",
            }
        )

    # Decompile/limit-window string roles
    text_blob = "\n".join(filter(None, [decompiled_text or "", limit_c_text or ""]))
    for r in string_roles(board, text_blob):
        role_hits.add(r)
    # Heuristic dual-analog in focused C
    low = text_blob.lower()
    if ("throttle" in low and "brake" in low) or ("gas" in low and "bremse" in low) or ("& 3" in low) or ("mask" in low and "3" in low):
        role_hits.update({"throttle", "brake"})
    if any(t in low for t in ("power", "boot", "startup", "key")):
        role_hits.add("power")
    if any(t in low for t in ("panic", "softunlock", "custom")):
        role_hits.add("customButton")

    # Never invent button recipes into comboSummaries — only validated lines elsewhere.
    combos: list[str] = []
    inputs: list[dict[str, Any]] = []
    transitions: list[dict[str, Any]] = []

    if {"throttle", "brake"}.issubset(role_hits):
        inputs.append(
            {
                "id": "slice-in-dual",
                "kind": "dualAnalog",
                "detail": "Back-Slice/Pinout: Gas-/Brems-Rollen am Limit-Pfad (Token/Addr-Heuristik)",
                "evidence": f"roles={sorted(role_hits)} cmpNear={cmp_near_speed}",
                "source": "serverDecompile",
                "confidence": "low",
            }
        )
        for kind, label in (("throttle", "Gas"), ("brake", "Bremse")):
            inputs.append(
                {
                    "id": f"slice-in-{kind}",
                    "kind": kind,
                    "detail": f"{label}-Rolle über Slice/Pinout/String am Limit-Kontext",
                    "evidence": "limit_slice",
                    "source": "serverDecompile",
                    "confidence": "low",
                }
            )
        if "power" in role_hits:
            inputs.append(
                {
                    "id": "slice-in-power",
                    "kind": "power",
                    "detail": "Power/Boot-Token im Limit-Kontext",
                    "evidence": "limit_slice",
                    "source": "serverDecompile",
                    "confidence": "low",
                }
            )

    if "customButton" in role_hits:
        inputs.append(
            {
                "id": "slice-in-custom",
                "kind": "customButton",
                "detail": "Panic/Custom-Token am Limit-/Unlock-Pfad",
                "evidence": "limit_slice",
                "source": "serverDecompile",
                "confidence": "low",
            }
        )

    notes = [
        f"limit_slice=ok sites={len(slices)} roles={sorted(role_hits)} "
        f"board={(board or {}).get('id') or 'none'} cmpNear={cmp_near_speed}"
    ]
    if cmp_near_speed:
        notes.append(
            f"limit_slice=cmpNear {cmp_near_speed} Compare/Test neben Speed-Immediates "
            "(Umschalt-Logik — keine Tastenfolge abgeleitet)"
        )
    if limit_c_text:
        notes.append(f"limit_slice=limit.c {len(limit_c_text)} chars")

    return {
        "ok": True,
        "notes": notes,
        "board": {
            "id": board.get("id"),
            "notes": board.get("notes"),
        }
        if board
        else None,
        "slices": slices[:40],
        "roleHits": sorted(role_hits),
        "combos": combos,
        "inputs": inputs,
        "transitions": transitions,
    }


def merge_into_result(result: dict[str, Any], slice_info: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(slice_info.get("notes") or [])
    result["notes"] = notes
    if not slice_info.get("ok"):
        return result

    if slice_info.get("board"):
        result["boardPinout"] = slice_info["board"]
    if slice_info.get("slices"):
        result["limitSlices"] = slice_info["slices"]

    combos = list(result.get("comboSummaries") or [])
    for c in slice_info.get("combos") or []:
        if c not in combos:
            combos.append(c)
    result["comboSummaries"] = combos

    transitions = list(result.get("modeTransitions") or [])
    seen = {(t.get("id"), t.get("title")) for t in transitions if isinstance(t, dict)}
    for t in slice_info.get("transitions") or []:
        key = (t.get("id"), t.get("title"))
        if key in seen:
            continue
        seen.add(key)
        transitions.append(t)
    result["modeTransitions"] = transitions

    inputs = list(result.get("inputHints") or [])
    seen_i = {i.get("id") for i in inputs if isinstance(i, dict)}
    for i in slice_info.get("inputs") or []:
        if i.get("id") in seen_i:
            continue
        seen_i.add(i.get("id"))
        inputs.append(i)
    result["inputHints"] = inputs

    quality = dict(result.get("quality") or {})
    quality["summary"] = ((quality.get("summary") or "").rstrip() + " + Limit-Slice.").strip()
    result["quality"] = quality
    return result


def _speed_sites(data: bytes) -> list[dict[str, Any]]:
    by_p: dict[int, list[int]] = {}
    for i in range(0, len(data) - 1):
        packed = data[i] | (data[i + 1] << 8)
        if packed in KNOWN_MAP:
            by_p.setdefault(packed, []).append(i)
    out: list[dict[str, Any]] = []
    for packed, offs in by_p.items():
        for off in offs[:3]:
            out.append({"packed": packed, "offset": off})
    return out


def _uniq_pins(pins: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    out: list[dict[str, Any]] = []
    for p in pins:
        key = str(p.get("pinId") or p.get("label"))
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def _uniq(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for i in items:
        if i in seen:
            continue
        seen.add(i)
        out.append(i)
    return out
