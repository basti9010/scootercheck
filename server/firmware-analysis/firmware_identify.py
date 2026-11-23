"""Pre-Ghidra firmware identity heuristics (Phase 2.2B).

Uses Cortex-M IVT plausibility to suggest processor + load address.
Never invents precision: uncertain layouts are flagged explicitly.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from cortex_m_ivt import parse_ivt

DEFAULT_PROCESSOR = os.environ.get("GHIDRA_PROCESSOR", "ARM:LE:32:Cortex").strip() or "ARM:LE:32:Cortex"
DEFAULT_BASE = os.environ.get("GHIDRA_BASE_ADDR", "0x08000000").strip() or "0x08000000"

_CANDIDATE_BASES = (
    0x08000000,
    0x00000000,
)


def identify_firmware_image(path: Path | bytes, *, hint_base: int | None = None) -> dict[str, Any]:
    """Return architecture / load suggestions for headless import."""
    if isinstance(path, (bytes, bytearray)):
        data = bytes(path)
        source = "bytes"
    else:
        p = Path(path)
        if not p.is_file():
            return {
                "ok": False,
                "confidence": "none",
                "notes": ["identify=missing-file"],
                "processor": DEFAULT_PROCESSOR,
                "baseAddr": DEFAULT_BASE,
                "architectureUnknown": True,
            }
        data = p.read_bytes()
        source = str(p)

    notes: list[str] = [f"identify=source:{source}", f"byteCount={len(data)}"]
    trials: list[dict[str, Any]] = []
    bases = [hint_base] if hint_base is not None else list(_CANDIDATE_BASES)
    for b in bases:
        if b is None:
            continue
        ivt = parse_ivt(data, base=b)
        trials.append({"base": f"{b:#010x}", "ivt": ivt})
        notes.extend(ivt.get("notes") or [])

    best = None
    for t in trials:
        ivt = t["ivt"]
        if ivt.get("ok") and ivt.get("likely"):
            best = t
            break
    if best is None:
        for t in trials:
            if (t["ivt"].get("vectors") or []) and t["ivt"].get("likely"):
                best = t
                break

    if best is None:
        # Phase 2.2F: BLE/RAW4TFT container probe before giving up.
        try:
            from ble_container import identify_ble_container

            ble = identify_ble_container(data, original_name=source if source != "bytes" else None)
        except Exception:
            ble = None
        if ble and ble.get("containerRecognized"):
            return {
                "ok": bool(ble.get("imageExtractable")),
                "confidence": ble.get("confidence") or "medium",
                "architectureUnknown": bool(ble.get("architectureUnknown")),
                "processor": ble.get("architecture") or DEFAULT_PROCESSOR,
                "baseAddr": ble.get("baseAddr") or DEFAULT_BASE,
                "thumbLikely": bool((ble.get("ivt") or {}).get("likely")),
                "entryPoints": [],
                "containerAnalysis": ble,
                "trials": trials,
                "notes": notes + list(ble.get("notes") or []),
                "analysisLimitations": list(ble.get("analysisLimitations") or []),
            }
        return {
            "ok": False,
            "confidence": "low",
            "architectureUnknown": True,
            "processor": DEFAULT_PROCESSOR,
            "baseAddr": DEFAULT_BASE,
            "thumbLikely": None,
            "entryPoints": [],
            "trials": trials,
            "notes": notes + ["identify=no-plausible-ivt; using configured defaults"],
            "analysisLimitations": [
                "Keine plausible Cortex-M-Vektortabelle — Ladeadresse/Architektur unsicher.",
            ],
        }

    ivt = best["ivt"]
    reset = next((v for v in (ivt.get("vectors") or []) if v.get("role") == "reset"), None)
    entries: list[dict[str, Any]] = []
    for v in ivt.get("vectors") or []:
        if v.get("role") in {"reset"} or (
            isinstance(v.get("index"), int) and 1 <= int(v["index"]) < 16 and v.get("thumb")
        ):
            if v.get("handler"):
                entries.append(
                    {
                        "name": v.get("name"),
                        "address": v.get("handler"),
                        "thumb": bool(v.get("thumb")),
                        "role": v.get("role") or v.get("name"),
                        "confidence": "high" if v.get("role") == "reset" else "medium",
                    }
                )

    thumb = bool(reset.get("thumb")) if isinstance(reset, dict) else True
    confidence = "high" if ivt.get("ok") else "medium"
    return {
        "ok": True,
        "confidence": confidence,
        "architectureUnknown": False,
        "processor": DEFAULT_PROCESSOR if thumb else DEFAULT_PROCESSOR,
        "baseAddr": best["base"],
        "thumbLikely": thumb,
        "entryPoints": entries,
        "ivt": {
            "ok": ivt.get("ok"),
            "likely": ivt.get("likely"),
            "vectorCount": len(ivt.get("vectors") or []),
        },
        "trials": [{"base": t["base"], "ok": t["ivt"].get("ok"), "likely": t["ivt"].get("likely")} for t in trials],
        "notes": notes + [f"identify=selectedBase:{best['base']}", f"identify=confidence:{confidence}"],
        "analysisLimitations": [],
    }
