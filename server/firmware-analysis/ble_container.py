"""BLE / RAW4TFT firmware container identification (Phase 2.2F).

Identifies Ninebot-style RAW4TFT containers and extracts the payload region.
Does NOT force ARM architecture from filename alone.
Does NOT bypass encryption or protection mechanisms.
"""
from __future__ import annotations

import hashlib
import struct
from pathlib import Path
from typing import Any

from cortex_m_ivt import parse_ivt
from plaintext_detect import shannon_entropy

RAW4TFT_MAGIC = b"RAW4TFT\x00"
DEFAULT_HEADER_SIZE = 0x400

CONTAINER_RECOGNIZED = "CONTAINER_RECOGNIZED"
PROCESSOR_RECOGNIZED = "PROCESSOR_RECOGNIZED"
IMAGE_EXTRACTABLE = "IMAGE_EXTRACTABLE"
ARCHITECTURE_UNKNOWN = "ARCHITECTURE_UNKNOWN"
FORMAT_UNSUPPORTED = "FORMAT_UNSUPPORTED"
ANALYSIS_NOT_POSSIBLE = "ANALYSIS_NOT_POSSIBLE"


def identify_ble_container(
    path: Path | bytes,
    *,
    original_name: str | None = None,
) -> dict[str, Any]:
    """Identify container format and optionally extractable payload."""
    if isinstance(path, (bytes, bytearray)):
        data = bytes(path)
        name = original_name or "bytes"
        source = "bytes"
    else:
        p = Path(path)
        if not p.is_file():
            return {
                "ok": False,
                "status": ANALYSIS_NOT_POSSIBLE,
                "notes": ["bleContainer=missing-file"],
                "components": [],
                "analysisLimitations": ["Datei fehlt."],
            }
        data = p.read_bytes()
        name = original_name or p.name
        source = str(p)

    notes: list[str] = [f"bleContainer=source:{source}", f"byteCount={len(data)}"]
    limitations: list[str] = [
        "Keine Architektur allein aus dem Dateinamen.",
        "Keine Umgehung unbekannter Schutzmechanismen.",
    ]

    if len(data) < 32:
        return {
            "ok": False,
            "status": ANALYSIS_NOT_POSSIBLE,
            "format": None,
            "notes": notes + ["too_small"],
            "components": [],
            "analysisLimitations": limitations + ["Datei zu klein."],
        }

    if data[:8] != RAW4TFT_MAGIC:
        # Not this container — report unsupported for BLE-specific path
        return {
            "ok": False,
            "status": FORMAT_UNSUPPORTED,
            "format": None,
            "containerRecognized": False,
            "notes": notes + ["magic_not_RAW4TFT"],
            "components": [],
            "analysisLimitations": limitations
            + ["Kein RAW4TFT-Container — BLE-Adapter nicht anwendbar."],
        }

    payload_size = struct.unpack_from("<I", data, 12)[0]
    header_hint = struct.unpack_from("<I", data, 0x18)[0] if len(data) >= 0x1C else DEFAULT_HEADER_SIZE
    header_size = header_hint if header_hint in {0x400, 0x200, 0x1000} else DEFAULT_HEADER_SIZE
    if header_size >= len(data):
        header_size = DEFAULT_HEADER_SIZE

    payload_off = header_size
    # Prefer header payload_size when it fits
    avail = len(data) - payload_off
    extract_len = min(payload_size, avail) if payload_size > 0 else avail
    if extract_len <= 0:
        return {
            "ok": True,
            "status": CONTAINER_RECOGNIZED,
            "format": "RAW4TFT",
            "containerRecognized": True,
            "processorRecognized": False,
            "imageExtractable": False,
            "architecture": None,
            "baseAddr": None,
            "headerSize": header_size,
            "payloadSizeField": payload_size,
            "notes": notes + ["payload_empty_or_invalid"],
            "components": [],
            "analysisLimitations": limitations + ["Payload-Länge ungültig."],
            "confidence": "medium",
        }

    payload = data[payload_off : payload_off + extract_len]
    payload_sha = hashlib.sha256(payload).hexdigest()
    header_ent = shannon_entropy(data[:header_size])
    payload_ent = shannon_entropy(payload[: min(len(payload), 65536)])

    # Probe Cortex-M IVT at payload start (common for these containers)
    ivt = parse_ivt(payload, base=0)
    arch = None
    base_addr = None
    proc_conf = "none"
    status = CONTAINER_RECOGNIZED
    if ivt.get("likely"):
        # SP in SRAM + thumb reset — Cortex-M family, but flash base may be 0x0 (Nordic-like)
        # rather than STM32 0x08000000. Do not force STM32 base.
        reset = int(ivt.get("resetHandlerInt") or 0)
        arch = "ARM:LE:32:Cortex"
        if 0x08000000 <= reset <= 0x08200000:
            base_addr = "0x08000000"
            proc_conf = "medium"
        else:
            base_addr = "0x00000000"
            proc_conf = "low"
            limitations.append(
                "Reset-Vektor zeigt nicht auf STM32-Flash (0x08000000) — "
                "mögliche Nordic-/SoftDevice-ähnliche Map; Basis 0x0 nur als Kandidat."
            )
        status = PROCESSOR_RECOGNIZED if proc_conf != "none" else CONTAINER_RECOGNIZED
    else:
        limitations.append(
            "Payload ohne plausible Cortex-M-IVT am Payload-Anfang — Architektur unbekannt."
        )
        status = ARCHITECTURE_UNKNOWN

    component = {
        "role": "firmware_payload",
        "origin": "RAW4TFT.payload",
        "offset": payload_off,
        "size": len(payload),
        "sha256": payload_sha,
        "format": "raw_bin",
        "architecture": arch,
        "baseAddrCandidate": base_addr,
        "detectionConfidence": proc_conf,
        "ivtLikely": bool(ivt.get("likely")),
        "entropy": round(payload_ent, 3),
        "notes": [
            f"headerEntropy={header_ent:.3f}",
            f"payloadSizeField={payload_size}",
            f"fileDelta={len(data) - payload_size}",
        ],
    }

    image_extractable = len(payload) >= 256 and payload_ent < 7.8
    if image_extractable and status in {CONTAINER_RECOGNIZED, PROCESSOR_RECOGNIZED, ARCHITECTURE_UNKNOWN}:
        # Keep stronger status if processor recognized
        if status == CONTAINER_RECOGNIZED:
            status = IMAGE_EXTRACTABLE

    return {
        "ok": True,
        "status": status,
        "format": "RAW4TFT",
        "containerRecognized": True,
        "processorRecognized": bool(arch),
        "imageExtractable": image_extractable,
        "architecture": arch,
        "architectureUnknown": arch is None,
        "baseAddr": base_addr,
        "headerSize": header_size,
        "payloadOffset": payload_off,
        "payloadSizeField": payload_size,
        "payloadSize": len(payload),
        "payloadSHA256": payload_sha,
        "containerSHA256": hashlib.sha256(data).hexdigest(),
        "confidence": "high" if image_extractable else "medium",
        "components": [component],
        "ivt": {
            "likely": ivt.get("likely"),
            "initialSP": ivt.get("initialSP"),
            "resetHandler": ivt.get("resetHandler"),
        },
        "notes": notes
        + [
            f"RAW4TFT header={header_size:#x} payload@{payload_off:#x} len={len(payload)}",
            f"status={status}",
        ],
        "analysisLimitations": limitations,
        "originalName": name,
    }


def extract_payload_bytes(data: bytes) -> tuple[bytes, dict[str, Any]] | tuple[None, dict[str, Any]]:
    """Return (payload_bytes, meta) or (None, meta)."""
    meta = identify_ble_container(data)
    if not meta.get("imageExtractable"):
        return None, meta
    off = int(meta.get("payloadOffset") or 0)
    size = int(meta.get("payloadSize") or 0)
    if off < 0 or size <= 0 or off + size > len(data):
        return None, meta
    return data[off : off + size], meta
