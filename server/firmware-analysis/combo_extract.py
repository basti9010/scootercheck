"""Deterministic mode / input hints from speed pairs + Ghidra C text.

Does NOT invent physical unlock button sequences. Dual legal/open caps become
a mode-transition with an unbelegt trigger; token hits become low/medium
inputHints only.
"""
from __future__ import annotations

import re
from typing import Any

from combo_policy import sanitize_transition_trigger


def xref_notes_for_speeds(decompiled_text: str | None, speeds: list[dict[str, Any]]) -> list[str]:
    """Collect short C context lines around known packed immediates (Ghidra export)."""
    if not decompiled_text or not speeds:
        return []
    lines = decompiled_text.splitlines()
    notes: list[str] = []
    packed = {int(s["packedU16"]) for s in speeds if s.get("packedU16") is not None}
    for p in sorted(packed):
        needle = f"0x{p:x}"
        needle2 = f"0x{p:04x}"
        needle3 = f"0x{p:04X}"
        hits = 0
        for idx, line in enumerate(lines):
            low = line.lower()
            if needle.lower() not in low and needle2.lower() not in low and needle3 not in line:
                continue
            start = max(0, idx - 1)
            end = min(len(lines), idx + 2)
            ctx = " | ".join(l.strip() for l in lines[start:end] if l.strip())
            notes.append(f"xref 0x{p:04X}: {ctx[:180]}")
            hits += 1
            if hits >= 2:
                break
    return notes[:8]


def extract_combos(
    *,
    speeds: list[dict[str, Any]],
    decompiled_text: str | None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    """Return (modeTransitions, inputHints, comboSummaries).

    comboSummaries stays empty here — only Live-/Validiert-/Belegt-lines may
    populate it elsewhere (see combo_policy).
    """
    transitions: list[dict[str, Any]] = []
    inputs: list[dict[str, Any]] = []
    combos: list[str] = []

    legal = [s for s in speeds if s.get("role") == "legalCap"]
    open_caps = [s for s in speeds if s.get("role") == "openCap"]
    region = [s for s in speeds if s.get("role") == "regionOrMode"]

    if legal and open_caps:
        legal_kmh = min(s["kmh"] for s in legal)
        open_kmh = max(s["kmh"] for s in open_caps)
        transitions.append(
            {
                "id": "srv-tr-dual-mode",
                "title": "Zwei Limit-Welten im Code",
                "trigger": sanitize_transition_trigger(None),
                "effect": f"Umschalten zwischen ~{int(legal_kmh)} km/h (legal-nah) und ~{int(open_kmh)} km/h (offen)",
                "evidence": "Speed-Paar legalCap + openCap im Klartext/Decompile",
                "source": "serverDecompile",
                "confidence": "medium",
            }
        )

    if legal and region and not open_caps:
        # Factual note only — not a button recipe
        pass

    text = (decompiled_text or "").lower()
    if not text:
        return transitions, inputs, combos

    def has(*needles: str) -> bool:
        return any(n in text for n in needles)

    dual = bool(
        re.search(r"\bmask\b.{0,40}\b3\b", text)
        or re.search(r"&\s*3\b", text)
        or ("beide" in text and "kanal" in text)
        or has("dual", "two channel", "both channels")
    )
    throttleish = has("throttle", "gas", "accel", "adc") and (
        has("400") or has("brake", "bremse", "lever")
    )
    brakeish = has("brake", "bremse", "lever")
    powerish = has("power", "boot", "startup", "ignition", "einschalt")
    panicish = has("panic", "softunlock", "soft_unlock", "custom button", "custombutton")

    if dual or (throttleish and brakeish):
        inputs.append(
            {
                "id": "srv-in-dual",
                "kind": "dualAnalog",
                "detail": "Decompile: zwei Analog-/Eingangskanäle (Token-Muster)",
                "evidence": "Textmuster dual/mask&3 / throttle+brake",
                "source": "serverDecompile",
                "confidence": "low",
            }
        )
        if throttleish:
            inputs.append(
                {
                    "id": "srv-in-throttle",
                    "kind": "throttle",
                    "detail": "Gas-/Throttle-Token im Decompile",
                    "evidence": "Decompile-Token",
                    "source": "serverDecompile",
                    "confidence": "low",
                }
            )
        if brakeish:
            inputs.append(
                {
                    "id": "srv-in-brake",
                    "kind": "brake",
                    "detail": "Brems-/Hebel-Token im Decompile",
                    "evidence": "Decompile-Token",
                    "source": "serverDecompile",
                    "confidence": "low",
                }
            )
        if powerish:
            inputs.append(
                {
                    "id": "srv-in-power",
                    "kind": "power",
                    "detail": "Power/Boot-Token im Decompile",
                    "evidence": "Decompile-Token power/boot/startup",
                    "source": "serverDecompile",
                    "confidence": "low",
                }
            )

    if panicish:
        inputs.append(
            {
                "id": "srv-in-custom",
                "kind": "customButton",
                "detail": "Panic/Custom-Token im Decompile/String",
                "evidence": "Token panic/softunlock/custom",
                "source": "serverDecompile",
                "confidence": "low",
            }
        )
        transitions.append(
            {
                "id": "srv-tr-panic",
                "title": "Panic-/Legal-Pfad (Token)",
                "trigger": sanitize_transition_trigger(None),
                "effect": "Hinweis auf Legal-Rückfall-Pfad — Tastenfolge nicht belegt",
                "evidence": "Panic/SoftUnlock-Token im Decompile",
                "source": "serverDecompile",
                "confidence": "low",
            }
        )

    return transitions, inputs, combos
