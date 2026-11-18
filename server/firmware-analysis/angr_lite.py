"""Path analysis around speed immediates — Capstone always, angr CFGFast optionally.

angr runs in an isolated subprocess with:
  - RLIMIT_AS (ANGR_MEM_MB, default 1800)
  - wall-clock timeout (ANGR_TIMEOUT_SEC, default 90)
  - no symbolic execution (CFGFast only)
  - caller should hold the shared heavy-analysis lock (not parallel to Ghidra)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from speed_extract import KNOWN_MAP

ENABLE_ANGR = os.environ.get("ENABLE_ANGR", "1").strip() not in ("0", "false", "False")
BASE = int(os.environ.get("GHIDRA_BASE_ADDR", "0x08000000"), 0)
ANGR_MAX_BYTES = int(os.environ.get("ANGR_MAX_BYTES", str(256 * 1024)) or str(256 * 1024))
ANGR_TIMEOUT_SEC = int(os.environ.get("ANGR_TIMEOUT_SEC", "90") or "90")
ANGR_MEM_MB = int(os.environ.get("ANGR_MEM_MB", "1800") or "1800")
MAX_PACKED = 8
BACKWALK_DEPTH = 12
WORKER = Path(__file__).resolve().parent / "angr_cfg_worker.py"


def angr_configured() -> bool:
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

    if angr_engine_available() and len(data) <= ANGR_MAX_BYTES:
        ang = _run_angr_subprocess(bin_path)
        if ang.get("ok"):
            ang_hints = ang.get("hints") or []
            hints.extend(ang_hints)
            notes.append(
                f"angr=CFGFast subprocess hints={len(ang_hints)} "
                f"nodes={ang.get('nodes')} timeout={ANGR_TIMEOUT_SEC}s mem={ANGR_MEM_MB}MB"
            )
            for h in ang_hints:
                if h.get("predecessors") or h.get("function"):
                    transitions.append(
                        {
                            "id": f"angr-{h.get('packed', 0):04x}-{h.get('offset', 0)}",
                            "title": f"angr-CFG: {int(h.get('kmh') or 0)} km/h",
                            "trigger": f"Function {h.get('function') or '—'}",
                            "effect": f"Vorgänger: {', '.join(h.get('predecessors') or []) or 'keine'}",
                            "evidence": str(h.get("addr") or ""),
                            "source": "serverAngr",
                            "confidence": "medium",
                        }
                    )
        else:
            notes.append(f"angr=failed:{ang.get('error') or ang.get('notes')}")
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


def _run_angr_subprocess(bin_path: Path) -> dict[str, Any]:
    if not WORKER.is_file():
        return {"ok": False, "error": "worker missing"}

    with tempfile.TemporaryDirectory(prefix="angr-cfg-") as td:
        out = Path(td) / "out.json"
        env = os.environ.copy()
        env["ANGR_MEM_MB"] = str(ANGR_MEM_MB)
        env["OMP_NUM_THREADS"] = "1"
        env["OPENBLAS_NUM_THREADS"] = "1"
        env["MKL_NUM_THREADS"] = "1"
        env["GHIDRA_BASE_ADDR"] = hex(BASE)
        try:
            proc = subprocess.run(
                [sys.executable, str(WORKER), str(bin_path), str(out)],
                capture_output=True,
                text=True,
                timeout=ANGR_TIMEOUT_SEC,
                env=env,
                check=False,
            )
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": f"timeout>{ANGR_TIMEOUT_SEC}s"}
        except Exception as e:
            return {"ok": False, "error": f"spawn:{e}"}

        if out.is_file():
            try:
                return json.loads(out.read_text(encoding="utf-8"))
            except json.JSONDecodeError as e:
                return {"ok": False, "error": f"badjson:{e}"}
        err = (proc.stderr or proc.stdout or "")[-400:]
        return {"ok": False, "error": f"exit={proc.returncode} {err}"}


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
