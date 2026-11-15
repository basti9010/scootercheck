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
) -> dict[str, Any]:
    from datetime import datetime, timezone

    speeds = scan_binary(plaintext) if decrypt_ok and plaintext else []
    max_k = max((s["kmh"] for s in speeds), default=None)
    legal = min((s["kmh"] for s in speeds if s["role"] == "legalCap"), default=None)
    sources = ["serverDecompile"] if decrypt_ok else []
    has_det = bool(speeds)
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
        "modeTransitions": [],
        "inputHints": [],
        "comboSummaries": [],
        "notes": notes,
        "caveats": [
            "Code-/Katalogbefunde beweisen nicht, dass dieses Image aktuell im Controller steckt.",
            "ENC ohne Entschlüsselung: nur Meta, Hash und bekannte Signaturen.",
            "KI-Auswertung (falls) darf nur dieses Schema füllen.",
        ],
        "quality": {
            "hasDeterministicBasis": has_det,
            "llmSchemaValidated": False,
            "summary": (
                "Server-Decrypt + deterministischer Speed-Scan."
                if has_det
                else "Decrypt/Scan ohne Speed-Treffer — Katalog in der App prüfen."
            ),
        },
    }
