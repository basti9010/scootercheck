"""Path analysis around speed immediates — Capstone always, angr CFG optionally.

angr runs in an isolated subprocess with:
  - RLIMIT_AS (ANGR_MEM_MB, default 1800)
  - wall-clock timeout (ANGR_TIMEOUT_SEC, default 150)
  - deep CFGFast (multi-hop preds, callers, xrefs) — optional local symbolic
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
ANGR_TIMEOUT_SEC = int(os.environ.get("ANGR_TIMEOUT_SEC", "150") or "150")
ANGR_MEM_MB = int(os.environ.get("ANGR_MEM_MB", "1800") or "1800")
ANGR_CFG_DEPTH = int(os.environ.get("ANGR_CFG_DEPTH", "6") or "6")
ANGR_SYMBOLIC = os.environ.get("ANGR_SYMBOLIC", "0").strip() in ("1", "true", "True", "yes")
MAX_PACKED = int(os.environ.get("ANGR_MAX_PACKED", "12") or "12")
BACKWALK_DEPTH = int(os.environ.get("ANGR_CAPSTONE_DEPTH", "28") or "28")
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
        for off in offsets[:3]:
            if off < 16:
                continue
            preds = _capstone_predecessors(data, off)
            hint = {
                "packed": packed,
                "kmh": kmh,
                "role": role,
                "offset": off,
                "addr": f"{BASE + off:#x}",
                "predecessors": preds[:12],
                "engine": "capstone",
                "cfgDepth": BACKWALK_DEPTH,
            }
            hints.append(hint)
            if preds:
                transitions.append(
                    {
                        "id": f"path-{packed:04x}-{off}",
                        "title": f"Pfad zu {int(kmh)} km/h (0x{packed:04X})",
                        "trigger": "Bedingter Sprung/Compare in Nähe (Capstone-Rückwärts)",
                        "effect": f"Immediate 0x{packed:04X} erreichbar aus {len(preds)} Vorgänger-Insn",
                        "evidence": "; ".join(preds[:4]) or f"@{BASE + off:#x}",
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
                f"angr=CFGFast-deep subprocess hints={len(ang_hints)} "
                f"nodes={ang.get('nodes')} edges={ang.get('edges')} "
                f"funcs={ang.get('functions')} depth={ang.get('cfgDepth', ANGR_CFG_DEPTH)} "
                f"symbolic={bool(ang.get('symbolic'))} "
                f"timeout={ANGR_TIMEOUT_SEC}s mem={ANGR_MEM_MB}MB"
            )
            for h in ang_hints:
                chain = h.get("predecessorChain") or []
                callers = h.get("callers") or []
                xrefs = h.get("xrefs") or []
                snippet = h.get("snippet") or []
                preds = h.get("predecessors") or []
                if preds or callers or xrefs or h.get("function"):
                    effect_parts = []
                    if preds:
                        effect_parts.append(f"CFG-Vorgänger×{len(preds)} (depth≤{h.get('cfgDepth', ANGR_CFG_DEPTH)})")
                    if callers:
                        effect_parts.append(f"Caller: {', '.join(callers[:4])}")
                    if xrefs:
                        effect_parts.append(f"XRefs: {', '.join(xrefs[:4])}")
                    if chain:
                        hops = ", ".join(f"{c.get('addr')}@h{c.get('hop')}" for c in chain[:5])
                        effect_parts.append(f"Kette: {hops}")
                    evidence = "; ".join(snippet[:3]) if snippet else str(h.get("addr") or "")
                    conf = "high" if (len(preds) >= 3 or callers or xrefs) else "medium"
                    transitions.append(
                        {
                            "id": f"angr-{h.get('packed', 0):04x}-{h.get('offset', 0)}",
                            "title": f"angr-CFG-deep: {int(h.get('kmh') or 0)} km/h",
                            "trigger": f"Function {h.get('function') or '—'}",
                            "effect": " · ".join(effect_parts) or "CFG-Kontext",
                            "evidence": evidence,
                            "source": "serverAngr",
                            "confidence": conf,
                        }
                    )
                sym = h.get("symbolic") or {}
                if isinstance(sym, dict) and sym.get("ok") and int(sym.get("found") or 0) > 0:
                    transitions.append(
                        {
                            "id": f"angr-sym-{h.get('packed', 0):04x}-{h.get('offset', 0)}",
                            "title": f"angr-symbolic: {int(h.get('kmh') or 0)} km/h erreichbar",
                            "trigger": f"Local explore from {h.get('function') or 'fn'}",
                            "effect": f"found={sym.get('found')} steps≤{sym.get('steps')}",
                            "evidence": str(h.get("addr") or ""),
                            "source": "serverAngr",
                            "confidence": "high",
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
        "transitions": transitions[:40],
        "pathHints": hints[:60],
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
        env["ANGR_CFG_DEPTH"] = str(ANGR_CFG_DEPTH)
        env["ANGR_MAX_PACKED"] = str(MAX_PACKED)
        env["ANGR_SYMBOLIC"] = "1" if ANGR_SYMBOLIC else "0"
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
        from capstone import CS_ARCH_ARM, CS_MODE_ARM, CS_MODE_THUMB, Cs
    except ImportError:
        return []

    window = max(96, BACKWALK_DEPTH * 4)
    start = max(0, offset - window)
    chunk = data[start:offset]
    preds: list[str] = []
    for mode in (CS_MODE_THUMB, CS_MODE_ARM):
        md = Cs(CS_ARCH_ARM, mode)
        md.detail = True
        insns = list(md.disasm(chunk, BASE + start))
        for insn in insns[-BACKWALK_DEPTH:]:
            mnem = (insn.mnemonic or "").lower()
            if mnem.startswith("b") or mnem in {
                "cmp",
                "cmn",
                "tst",
                "teq",
                "cbz",
                "cbnz",
                "it",
                "ldr",
                "ldrh",
                "mov",
                "movw",
                "movt",
                "adds",
                "subs",
            }:
                line = f"{insn.address:#x}: {insn.mnemonic} {insn.op_str}"
                if line not in preds:
                    preds.append(line)
        if preds:
            break
    return preds
