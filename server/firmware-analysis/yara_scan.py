"""Optional YARA scan of decrypted firmware against bundled scooter_cfw rules."""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

ENABLE_YARA = os.environ.get("ENABLE_YARA", "1").strip() not in ("0", "false", "False")
RULES_PATH = Path(__file__).resolve().parent / "yara_rules" / "scooter_cfw.yar"


def yara_configured() -> bool:
    if not ENABLE_YARA or not RULES_PATH.is_file():
        return False
    try:
        import yara  # noqa: F401
        return True
    except ImportError:
        return False


def scan_firmware(bin_path: Path) -> dict[str, Any]:
    if not yara_configured():
        return {
            "ok": False,
            "matches": [],
            "notes": ["yara=skipped (not installed or ENABLE_YARA=0)"],
        }
    import yara

    try:
        rules = yara.compile(filepath=str(RULES_PATH))
        matches = rules.match(str(bin_path))
    except Exception as e:
        return {"ok": False, "matches": [], "notes": [f"yara=failed:{e}"]}

    out = []
    for m in matches:
        meta = dict(m.meta or {})
        str_ids: list[str] = []
        for s in (m.strings or [])[:8]:
            # yara-python 4.x: StringMatch with .identifier; older: (offset, id, data)
            ident = getattr(s, "identifier", None)
            if ident is None and isinstance(s, (tuple, list)) and len(s) >= 2:
                ident = s[1]
            if ident is not None:
                str_ids.append(str(ident))
        out.append(
            {
                "rule": m.rule,
                "description": str(meta.get("description") or m.rule),
                "confidence": str(meta.get("confidence") or "medium"),
                "family": str(meta.get("family") or ""),
                "tags": list(m.tags or []),
                "strings": str_ids,
            }
        )
    return {
        "ok": True,
        "matches": out,
        "notes": [f"yara=ok matches={len(out)}"],
    }


def merge_yara_into_result(result: dict[str, Any], yr: dict[str, Any]) -> dict[str, Any]:
    notes = list(result.get("notes") or [])
    notes.extend(yr.get("notes") or [])
    result["notes"] = notes
    if not yr.get("ok"):
        return result

    matches = yr.get("matches") or []
    result["yaraMatches"] = matches
    for m in matches:
        notes.append(f"yara:{m.get('rule')}: {m.get('description')}")
    result["notes"] = notes

    sources = list(result.get("sources") or [])
    if matches and "serverYara" not in sources:
        sources.append("serverYara")
        result["sources"] = sources
        quality = dict(result.get("quality") or {})
        quality["summary"] = ((quality.get("summary") or "").rstrip() + " + YARA.").strip()
        result["quality"] = quality

    # Promote soft combo note when legal+open together / known CFW families
    combos = list(result.get("comboSummaries") or [])
    for m in matches:
        rule = m.get("rule")
        fam = str(m.get("family") or "")
        if rule == "Ninebot_Legal_And_Open_Together":
            line = "YARA: Legal-Kappe und hohe Open-Cap im selben Image (Soft-Unlock-typisch)"
            if line not in combos:
                combos.insert(0, line)
        elif fam == "panicsystem" or rule == "CFW_PanicSystem_Artifact":
            line = "YARA: PanicSystem-Artefakt im Klartext"
            if line not in combos:
                combos.insert(0, line)
        elif fam == "scooterhacking" or rule == "CFW_ScooterHacking_Artifact":
            line = "YARA: ScooterHacking-/SHFW-Marker im Klartext"
            if line not in combos:
                combos.insert(0, line)
        elif rule == "CFW_Wide_Open_Caps_Cluster":
            line = "YARA: Dichte hoher Open-Caps (40/45/50/99) — CFW-typisch"
            if line not in combos:
                combos.insert(0, line)
    result["comboSummaries"] = combos
    return result
