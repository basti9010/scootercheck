"""Deterministic Ninebot packed-speed scan — mirrors iOS FirmwareSpeedSignatureExtractor."""
from __future__ import annotations

import struct
from typing import Any

KNOWN = [
    (0x1400, 20.0, "legalCap"),
    (0x1600, 22.0, "legalCap"),
    (0x1700, 23.0, "regionOrMode"),
    (0x1900, 25.0, "regionOrMode"),
    (0x1E00, 30.0, "intermediate"),
    (0x2000, 32.0, "intermediate"),
    (0x2300, 35.0, "openCap"),
    (0x2319, 35.0, "openCap"),
    (0x2800, 40.0, "openCap"),
    (0x2D00, 45.0, "openCap"),
    (0x3200, 50.0, "openCap"),
    (0x6300, 99.0, "openCap"),
]
KNOWN_MAP = {p: (kmh, role) for p, kmh, role in KNOWN}


def scan_decompiled_text(text: str) -> list[dict[str, Any]]:
    """Find known packed immediates like 0x1600 / 0x6300 in Ghidra C export."""
    import re

    found: dict[int, dict[str, Any]] = {}
    for m in re.finditer(r"0x([0-9a-fA-F]{3,4})\b", text):
        try:
            packed = int(m.group(1), 16)
        except ValueError:
            continue
        if packed not in KNOWN_MAP or packed in found:
            continue
        kmh, role = KNOWN_MAP[packed]
        found[packed] = {
            "id": f"srv-c-{packed:04x}",
            "kmh": kmh,
            "packedU16": packed,
            "role": role,
            "evidence": f"Decompile-Immediate 0x{packed:04X}",
            "source": "serverDecompile",
            "confidence": "high",
        }
    return sorted(found.values(), key=lambda x: x["kmh"])


def scan_binary(data: bytes) -> list[dict[str, Any]]:
    found: dict[int, dict[str, Any]] = {}
    for i in range(0, max(0, len(data) - 1)):
        packed = struct.unpack_from("<H", data, i)[0]
        if packed not in KNOWN_MAP or packed in found:
            continue
        kmh, role = KNOWN_MAP[packed]
        found[packed] = {
            "id": f"srv-bin-{packed:04x}",
            "kmh": kmh,
            "packedU16": packed,
            "role": role,
            "evidence": f"LE u16 0x{packed:04X} @ offset {i}",
            "source": "serverDecompile",
            "confidence": "high",
        }
    return sorted(found.values(), key=lambda x: x["kmh"])


def deep_result(
    *,
    subject_sha256: str,
    display_name: str | None,
    models: list[str],
    controller_type: str | None,
    plaintext: bytes,
    decrypt_ok: bool,
    notes: list[str],
    decompiled_text: str | None = None,
) -> dict[str, Any]:
    from datetime import datetime, timezone

    speeds = scan_binary(plaintext) if decrypt_ok and plaintext else []
    if decompiled_text:
        # Prefer union of binary + decompile immediates
        by_packed = {s.get("packedU16"): s for s in speeds if s.get("packedU16") is not None}
        for s in scan_decompiled_text(decompiled_text):
            p = s.get("packedU16")
            if p not in by_packed:
                by_packed[p] = s
        speeds = sorted(by_packed.values(), key=lambda x: x["kmh"])

    from combo_extract import extract_combos, xref_notes_for_speeds

    transitions, inputs, combos = extract_combos(
        speeds=speeds,
        decompiled_text=decompiled_text,
    )
    xref = xref_notes_for_speeds(decompiled_text, speeds)

    max_k = max((s["kmh"] for s in speeds), default=None)
    legal = min((s["kmh"] for s in speeds if s["role"] == "legalCap"), default=None)
    sources = ["serverDecompile"] if decrypt_ok or decompiled_text else []
    has_det = bool(speeds) or bool(combos) or bool(transitions)
    summary = "Server-Decrypt + deterministischer Speed-/Combo-Scan."
    if decompiled_text:
        summary = "Server-Decrypt + Ghidra-Decompile + Speed-/Combo-Scan."
    notes = list(notes)
    if combos:
        notes.append(f"comboHints={len(combos)}")
    notes.extend(xref)
    return {
        "schemaVersion": 1,
        "producedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "sources": sources,
        "subjectSHA256": subject_sha256,
        "packageDisplayName": display_name,
        "models": models,
        "controllerType": controller_type,
        "speedLimits": speeds,
        "maxSpeedKmhInCode": max_k,
        "legalCapKmhInCode": legal,
        "modeTransitions": transitions,
        "inputHints": inputs,
        "comboSummaries": combos,
        "notes": notes,
        "caveats": [
            "Code-/Katalogbefunde beweisen nicht, dass dieses Image aktuell im Controller steckt.",
            "ENC ohne Entschlüsselung: nur Meta, Hash und bekannte Signaturen.",
            "Combo-Hinweise aus Decompile/Speed-Paaren sind modellabhängig — Live-Vergleichstest empfohlen.",
            "KI-Auswertung (falls) darf nur dieses Schema füllen.",
        ],
        "quality": {
            "hasDeterministicBasis": has_det,
            "llmSchemaValidated": False,
            "summary": (
                summary
                if has_det
                else "Decrypt/Decompile ohne Speed-/Combo-Treffer — Katalog in der App prüfen."
            ),
        },
    }
