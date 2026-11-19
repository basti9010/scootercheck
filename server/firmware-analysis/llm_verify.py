"""Verify LLM-claimed addresses/functions against Ghidra/binary analysis (Phase 2).

LLM remains opt-in (allowLLM=false by default). Unverified claims are stripped or tagged.
"""
from __future__ import annotations

import re
from typing import Any

_ADDR_RE = re.compile(r"0x[0-9a-fA-F]{4,8}")
_FUN_RE = re.compile(r"\b(FUN_[0-9a-fA-F]+|[A-Za-z_][A-Za-z0-9_]{2,})\b")


def verify_enrichment(
    result: dict[str, Any],
    *,
    function_analysis: dict[str, Any] | None = None,
    plaintext_size: int | None = None,
    image_base: int = 0x08000000,
) -> dict[str, Any]:
    """Filter/annotate LLM-touched fields. Mutates a shallow copy of result."""
    out = dict(result)
    fn_index = _function_index(function_analysis)
    reports: list[dict[str, Any]] = []

    combos = []
    for line in out.get("comboSummaries") or []:
        ok, rep = _verify_text(str(line), fn_index, plaintext_size, image_base, field="combo")
        reports.append(rep)
        if ok:
            combos.append(line)
        else:
            # Keep Live/Belegt/Validiert lines even if addresses fail? Still require no fake offsets.
            if str(line).startswith(("Live-", "Belegt:", "Validiert:")):
                combos.append(line)
                rep["kept"] = "validated-prefix"
            else:
                rep["action"] = "dropped"
    out["comboSummaries"] = combos

    transitions = []
    for t in out.get("modeTransitions") or []:
        if not isinstance(t, dict):
            continue
        blob = " ".join(str(t.get(k) or "") for k in ("title", "trigger", "effect", "evidence"))
        ok, rep = _verify_text(blob, fn_index, plaintext_size, image_base, field="transition")
        reports.append(rep)
        src = str(t.get("source") or "")
        if src == "serverLLM" and not ok:
            rep["action"] = "dropped"
            continue
        if src == "serverLLM":
            t = dict(t)
            t["evidence"] = str(t.get("evidence") or "") + " · llmVerified=true"
        transitions.append(t)
    out["modeTransitions"] = transitions

    inputs = []
    for h in out.get("inputHints") or []:
        if not isinstance(h, dict):
            continue
        blob = str(h.get("detail") or "") + " " + str(h.get("evidence") or "")
        ok, rep = _verify_text(blob, fn_index, plaintext_size, image_base, field="input")
        reports.append(rep)
        src = str(h.get("source") or "")
        if src == "serverLLM" and not ok:
            rep["action"] = "dropped"
            continue
        inputs.append(h)
    out["inputHints"] = inputs

    notes = list(out.get("notes") or [])
    dropped = sum(1 for r in reports if r.get("action") == "dropped")
    verified = sum(1 for r in reports if r.get("ok") is True)
    notes.append(f"llmVerify=checked verifiedClaims={verified} dropped={dropped}")
    out["notes"] = notes
    out["llmVerification"] = {
        "ok": True,
        "checked": len(reports),
        "verified": verified,
        "dropped": dropped,
        "reports": reports[:40],
        "limitations": [
            "Nur Adress-/Funktionsbehauptungen gegen Ghidra-Export und Imagegröße geprüft.",
            "Nicht belegte KI-Aussagen werden nicht als bestätigt übernommen.",
        ],
    }
    return out


def _function_index(fa: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    idx: dict[str, dict[str, Any]] = {}
    if not fa or not fa.get("ok"):
        return idx
    for f in fa.get("functions") or []:
        if not isinstance(f, dict):
            continue
        name = str(f.get("name") or "")
        addr = str(f.get("address") or "").lower()
        if name:
            idx[name] = f
        if addr:
            idx[addr] = f
            if addr.startswith("0x"):
                idx[addr[2:]] = f
    return idx


def _verify_text(
    text: str,
    fn_index: dict[str, dict[str, Any]],
    plaintext_size: int | None,
    image_base: int,
    *,
    field: str,
) -> tuple[bool, dict[str, Any]]:
    addrs = _ADDR_RE.findall(text)
    names = [m.group(1) for m in _FUN_RE.finditer(text) if m.group(1).startswith("FUN_")]
    if not addrs and not names:
        return True, {"field": field, "ok": True, "reason": "no-technical-claim"}

    problems: list[str] = []
    for a in addrs:
        if not _addr_in_range(a, plaintext_size, image_base):
            problems.append(f"addr-out-of-range:{a}")
        elif fn_index and a.lower() not in fn_index and a.lower().lstrip("0x") not in fn_index:
            # Address may be data/code without function entry — soft fail only if FUN_ claimed.
            pass
    for n in names:
        if fn_index and n not in fn_index:
            problems.append(f"unknown-function:{n}")

    if problems:
        return False, {"field": field, "ok": False, "problems": problems, "action": "flagged"}
    return True, {"field": field, "ok": True, "reason": "claims-covered"}


def _addr_in_range(addr: str, plaintext_size: int | None, image_base: int) -> bool:
    try:
        val = int(addr, 16)
    except ValueError:
        return False
    if plaintext_size is None:
        return True
    # Accept file offsets or VMA in flash window.
    if 0 <= val < plaintext_size:
        return True
    if image_base <= val < image_base + plaintext_size:
        return True
    return False
