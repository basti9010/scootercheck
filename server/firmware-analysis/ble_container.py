"""BLE / RAW4TFT firmware container identification (Phase 2.2F/G).

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

# Phase 2.2G architecture confidence tiers
ARCHITECTURE_CONFIRMED = "ARCHITECTURE_CONFIRMED"
ARCHITECTURE_LIKELY = "ARCHITECTURE_LIKELY"
ARCHITECTURE_POSSIBLE = "ARCHITECTURE_POSSIBLE"

# Offsets (relative to payload start) scanned for plausible Cortex-M IVT
IVT_PROBE_OFFSETS = (
    0x0,
    0x100,
    0x200,
    0x400,
    0x1000,
    0x2000,
    0x3000,
    0x4000,
    0x10000,
    0x20000,
    0x30000,
)


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
                "architectureConfidence": ARCHITECTURE_UNKNOWN,
            }
        data = p.read_bytes()
        name = original_name or p.name
        source = str(p)

    notes: list[str] = [f"bleContainer=source:{source}", f"byteCount={len(data)}"]
    limitations: list[str] = [
        "Keine Architektur allein aus dem Dateinamen.",
        "Keine Umgehung unbekannter Schutzmechanismen.",
        "Keine Schlüssel-Extraktion.",
    ]

    if len(data) < 32:
        return {
            "ok": False,
            "status": ANALYSIS_NOT_POSSIBLE,
            "format": None,
            "notes": notes + ["too_small"],
            "components": [],
            "analysisLimitations": limitations + ["Datei zu klein."],
            "architectureConfidence": ARCHITECTURE_UNKNOWN,
        }

    if data[:8] != RAW4TFT_MAGIC:
        return {
            "ok": False,
            "status": FORMAT_UNSUPPORTED,
            "format": None,
            "containerRecognized": False,
            "notes": notes + ["magic_not_RAW4TFT"],
            "components": [],
            "analysisLimitations": limitations
            + ["Kein RAW4TFT-Container — BLE-Adapter nicht anwendbar."],
            "architectureConfidence": ARCHITECTURE_UNKNOWN,
        }

    payload_size = struct.unpack_from("<I", data, 12)[0]
    header_hint = struct.unpack_from("<I", data, 0x18)[0] if len(data) >= 0x1C else DEFAULT_HEADER_SIZE
    header_size = header_hint if header_hint in {0x400, 0x200, 0x1000} else DEFAULT_HEADER_SIZE
    if header_size >= len(data):
        header_size = DEFAULT_HEADER_SIZE

    payload_off = header_size
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
            "architectureConfidence": ARCHITECTURE_UNKNOWN,
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

    # Phase 2.2G: scan multiple offsets for plausible IVT / embedded images
    probes = _probe_payload_structures(payload)
    best = probes.get("bestIvt")
    arch = None
    base_addr = None
    arch_conf = ARCHITECTURE_UNKNOWN
    status = CONTAINER_RECOGNIZED
    arch_evidence: list[dict[str, Any]] = list(probes.get("evidence") or [])

    if best and best.get("likely"):
        reset = int(best.get("resetHandlerInt") or 0)
        arch = "ARM:LE:32:Cortex"
        off = int(best.get("payloadRelativeOffset") or 0)
        if 0x08000000 <= reset <= 0x08200000:
            base_addr = "0x08000000"
            arch_conf = ARCHITECTURE_CONFIRMED if off == 0 else ARCHITECTURE_LIKELY
        elif 0x00000000 <= reset <= 0x00200000:
            base_addr = "0x00000000"
            # Nordic-/SoftDevice-ähnliche Map — möglich, aber nicht bestätigt ohne weitere Signaturen
            arch_conf = ARCHITECTURE_POSSIBLE if off != 0 else ARCHITECTURE_LIKELY
            limitations.append(
                "Reset-Vektor zeigt nicht auf STM32-Flash (0x08000000) — "
                "mögliche Nordic-/SoftDevice-ähnliche Map; Basis 0x0 nur als Kandidat."
            )
        else:
            arch_conf = ARCHITECTURE_POSSIBLE
            limitations.append("Reset-Handler-Adresse außerhalb bekannter Flash-Fenster.")
        status = PROCESSOR_RECOGNIZED
        notes.append(
            f"ivtProbe@payload+{off:#x} conf={arch_conf} reset={best.get('resetHandler')}"
        )
    else:
        limitations.append(
            "Keine plausible Cortex-M-IVT an bekannten Payload-Offsets — Architektur unbekannt."
        )
        status = ARCHITECTURE_UNKNOWN
        # SoftDevice-ish string hints never force architecture
        if probes.get("stringHints"):
            notes.append("stringHints=" + ",".join(probes["stringHints"][:6]))
            limitations.append(
                "String-Hinweise (z. B. SoftDevice) sind keine Architektur-Bestätigung."
            )

    component = {
        "role": "firmware_payload",
        "origin": "RAW4TFT.payload",
        "offset": payload_off,
        "size": len(payload),
        "sha256": payload_sha,
        "format": "raw_bin",
        "architecture": arch,
        "baseAddrCandidate": base_addr,
        "detectionConfidence": {
            ARCHITECTURE_CONFIRMED: "high",
            ARCHITECTURE_LIKELY: "medium",
            ARCHITECTURE_POSSIBLE: "low",
            ARCHITECTURE_UNKNOWN: "none",
        }.get(arch_conf, "none"),
        "architectureConfidence": arch_conf,
        "ivtLikely": bool(best and best.get("likely")),
        "ivtPayloadOffset": (best or {}).get("payloadRelativeOffset"),
        "entropy": round(payload_ent, 3),
        "notes": [
            f"headerEntropy={header_ent:.3f}",
            f"payloadSizeField={payload_size}",
            f"fileDelta={len(data) - payload_size}",
            f"ivtProbes={len(probes.get('candidates') or [])}",
        ],
    }

    # Additional embedded component candidates (non-destructive documentation only)
    extra_components: list[dict[str, Any]] = []
    for cand in (probes.get("candidates") or [])[:4]:
        if best and cand.get("payloadRelativeOffset") == best.get("payloadRelativeOffset"):
            continue
        if not cand.get("likely"):
            continue
        abs_off = payload_off + int(cand["payloadRelativeOffset"])
        extra_components.append(
            {
                "role": "embedded_ivt_candidate",
                "origin": f"RAW4TFT.payload+{cand['payloadRelativeOffset']:#x}",
                "offset": abs_off,
                "size": None,
                "sha256": None,
                "format": "ivt_candidate",
                "architecture": "ARM:LE:32:Cortex",
                "architectureConfidence": ARCHITECTURE_POSSIBLE,
                "detectionConfidence": "low",
                "notes": [
                    f"reset={cand.get('resetHandler')}",
                    f"sp={cand.get('initialSP')}",
                ],
            }
        )

    image_extractable = len(payload) >= 256 and payload_ent < 7.8
    if image_extractable and status in {CONTAINER_RECOGNIZED, PROCESSOR_RECOGNIZED, ARCHITECTURE_UNKNOWN}:
        if status == CONTAINER_RECOGNIZED:
            status = IMAGE_EXTRACTABLE

    # Never auto-hand unknown BLE arch to Cortex-M Ghidra importer
    ghidra_import_allowed = arch_conf in {ARCHITECTURE_CONFIRMED, ARCHITECTURE_LIKELY}
    if not ghidra_import_allowed:
        limitations.append(
            "Ghidra Cortex-M-Import für diese BLE-Payload nicht freigegeben "
            f"(architectureConfidence={arch_conf})."
        )

    return {
        "ok": True,
        "status": status,
        "format": "RAW4TFT",
        "containerRecognized": True,
        "processorRecognized": bool(arch),
        "imageExtractable": image_extractable,
        "architecture": arch,
        "architectureUnknown": arch is None or arch_conf == ARCHITECTURE_UNKNOWN,
        "architectureConfidence": arch_conf,
        "architectureEvidence": arch_evidence[:8],
        "baseAddr": base_addr,
        "headerSize": header_size,
        "payloadOffset": payload_off,
        "payloadSizeField": payload_size,
        "payloadSize": len(payload),
        "payloadSHA256": payload_sha,
        "containerSHA256": hashlib.sha256(data).hexdigest(),
        "confidence": "high" if image_extractable else "medium",
        "ghidraImportAllowed": ghidra_import_allowed,
        "components": [component] + extra_components,
        "payloadStructure": {
            "ivtProbeOffsets": list(IVT_PROBE_OFFSETS),
            "candidateCount": len(probes.get("candidates") or []),
            "bestIvtOffset": (best or {}).get("payloadRelativeOffset"),
            "stringHints": probes.get("stringHints") or [],
            "headerFields": {
                "magic": "RAW4TFT",
                "payloadSizeField": payload_size,
                "headerSizeHint": header_hint,
            },
        },
        "ivt": {
            "likely": bool(best and best.get("likely")),
            "initialSP": (best or {}).get("initialSP"),
            "resetHandler": (best or {}).get("resetHandler"),
            "payloadRelativeOffset": (best or {}).get("payloadRelativeOffset"),
        },
        "notes": notes
        + [
            f"RAW4TFT header={header_size:#x} payload@{payload_off:#x} len={len(payload)}",
            f"status={status}",
            f"architectureConfidence={arch_conf}",
        ],
        "analysisLimitations": limitations,
        "originalName": name,
    }


def _probe_payload_structures(payload: bytes) -> dict[str, Any]:
    """Scan payload for IVT-like structures and harmless string hints."""
    candidates: list[dict[str, Any]] = []
    evidence: list[dict[str, Any]] = []
    for off in IVT_PROBE_OFFSETS:
        if off + 8 > len(payload):
            continue
        # Try both STM32-style and low-flash base interpretation
        for base_guess in (0x08000000, 0x00000000):
            ivt = parse_ivt(payload[off:], base=base_guess)
            if not ivt.get("likely"):
                continue
            entry = {
                "payloadRelativeOffset": off,
                "baseGuess": f"{base_guess:#x}",
                "likely": True,
                "initialSP": ivt.get("initialSP"),
                "resetHandler": ivt.get("resetHandler"),
                "resetHandlerInt": ivt.get("resetHandlerInt"),
                "method": "cortex_m_ivt_probe",
            }
            candidates.append(entry)
            evidence.append(
                {
                    "kind": "vector_table",
                    "fileOffsetInPayload": off,
                    "method": "parse_ivt",
                    "baseGuess": f"{base_guess:#x}",
                    "initialSP": ivt.get("initialSP"),
                    "resetHandler": ivt.get("resetHandler"),
                    "confidence": ARCHITECTURE_LIKELY if off == 0 else ARCHITECTURE_POSSIBLE,
                }
            )
            break  # one hit per offset is enough

    # Prefer offset 0, then lowest offset with STM32 reset window
    def _rank(c: dict[str, Any]) -> tuple[int, int]:
        reset = int(c.get("resetHandlerInt") or 0)
        stm = 0 if 0x08000000 <= reset <= 0x08200000 else 1
        return (stm, int(c.get("payloadRelativeOffset") or 0))

    candidates.sort(key=_rank)
    best = candidates[0] if candidates else None

    hints: list[str] = []
    sample = payload[: min(len(payload), 256 * 1024)]
    for needle in (b"SoftDevice", b"s132", b"s140", b"NRF52", b"nRF5", b"Nordic"):
        if needle.lower() in sample.lower():
            hints.append(needle.decode("ascii", errors="ignore"))

    # Embedded ASCII version-ish tokens (documentation only)
    if b"RAW4TFT" in payload[:64]:
        hints.append("nested_RAW4TFT_magic")

    return {"candidates": candidates, "bestIvt": best, "evidence": evidence, "stringHints": hints}


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
