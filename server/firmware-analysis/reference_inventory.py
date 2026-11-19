"""Reference firmware inventory + analyzability assessment (Phase 2.2E).

Read-only evaluation of stock-fw references. Never mutates bins or trust.
`source=oem` alone is NOT manufacturer-verified provenance.
"""
from __future__ import annotations

import hashlib
import math
import os
from collections import Counter
from pathlib import Path
from typing import Any

from cortex_m_ivt import parse_ivt
from plaintext_detect import looks_like_plaintext_firmware, shannon_entropy
from stock_diff import (
    STOCK_FW_DIR,
    _load_refs,
    _public_ref,
    _trust_fields_for_ref,
    ensure_stock_dir,
)

try:
    from reference_catalog import ANALYZER_COMPAT, load_catalog_meta
except Exception:  # pragma: no cover
    ANALYZER_COMPAT = "2"

    def load_catalog_meta(sha256: str) -> dict[str, Any] | None:  # type: ignore
        return None

# Analyzability statuses (Modul B)
READY_FOR_ANALYSIS = "READY_FOR_ANALYSIS"
ARCHITECTURE_UNKNOWN = "ARCHITECTURE_UNKNOWN"
ENCRYPTED_UNSUPPORTED = "ENCRYPTED_UNSUPPORTED"
INVALID_FIRMWARE_LAYOUT = "INVALID_FIRMWARE_LAYOUT"
INCOMPLETE_FILE = "INCOMPLETE_FILE"
ANALYSIS_FAILED = "ANALYSIS_FAILED"
ANALYSIS_PARTIAL = "ANALYSIS_PARTIAL"
ANALYSIS_COMPLETED = "ANALYSIS_COMPLETED"

_MIN_BYTES = 256
_MAX_BYTES_DEFAULT = int(os.environ.get("FW_REF_MAX_BYTES", str(8 * 1024 * 1024)) or (8 * 1024 * 1024))
# Soft size preference for sequential Ghidra on 4 GB VPS
_PREFERRED_GHIDRA_MAX = int(os.environ.get("FW_REF_GHIDRA_PREFERRED_MAX", str(256 * 1024)) or (256 * 1024))


def inventory_references(
    *,
    root: Path | None = None,
    include_file_probe: bool = True,
) -> dict[str, Any]:
    """Structured inventory of stock references (read-only)."""
    stock_root = Path(root) if root is not None else STOCK_FW_DIR
    ensure_stock_dir() if root is None else None
    refs = _load_refs() if root is None else _load_refs_from(stock_root)

    items: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    for ref in refs:
        entry = _inventory_one(ref, include_file_probe=include_file_probe)
        items.append(entry)
        status_counts[str(entry.get("analyzabilityStatus") or "UNKNOWN")] += 1

    models = Counter(str(i.get("model") or "") for i in items)
    controllers = Counter(str(i.get("controllerType") or "") for i in items)
    sources = Counter(str(i.get("source") or "") for i in items)
    trusts = Counter(str(i.get("referenceTrust") or "") for i in items)
    formats = Counter(str(i.get("format") or "") for i in items)

    catalogs_compat2 = sum(
        1
        for i in items
        if i.get("catalogPresent") and str(i.get("catalogAnalyzerCompat") or "") == ANALYZER_COMPAT
    )
    catalogs_any = sum(1 for i in items if i.get("catalogPresent"))

    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "reference-inventory",
        "stockDir": str(stock_root),
        "referenceCount": len(items),
        "statusCounts": dict(status_counts),
        "modelCounts": dict(models),
        "controllerCounts": dict(controllers),
        "sourceCounts": dict(sources),
        "trustCounts": dict(trusts),
        "formatCounts": dict(formats),
        "catalogsPresent": catalogs_any,
        "catalogsAnalyzerCompat2": catalogs_compat2,
        "notes": [
            "source=oem is NOT manufacturer-verified provenance.",
            "Community references are never auto-elevated to manufacturerVerified.",
            "Inventory is read-only; bins and trust are unchanged.",
        ],
        "references": items,
        "analysisLimitations": [
            "Analyzability is a technical readiness estimate, not a quality verdict.",
            "Failed Ghidra import must be diagnosed separately (ANALYSIS_FAILED).",
        ],
    }


def assess_analyzability(
    path: Path,
    *,
    ref: dict[str, Any] | None = None,
    catalog_meta: dict[str, Any] | None = None,
    data: bytes | None = None,
) -> dict[str, Any]:
    """Assess whether a firmware file is suitable for full Ghidra analysis."""
    limitations: list[str] = []
    reasons: list[str] = []
    blob = data if data is not None else (path.read_bytes() if path.is_file() else b"")
    size = len(blob)
    sha = hashlib.sha256(blob).hexdigest() if blob else str((ref or {}).get("sha256") or "")

    if size == 0 or not path.is_file():
        return _status(
            INCOMPLETE_FILE,
            sha=sha,
            size=size,
            reasons=["empty or missing file"],
            limitations=["Datei fehlt oder ist leer."],
        )
    if size < _MIN_BYTES:
        return _status(
            INCOMPLETE_FILE,
            sha=sha,
            size=size,
            reasons=[f"size<{_MIN_BYTES}"],
            limitations=["Datei zu klein für sinnvolle Firmwareanalyse."],
        )
    if size > _MAX_BYTES_DEFAULT:
        limitations.append(f"Datei größer als konfiguriertes Maximum ({_MAX_BYTES_DEFAULT} B).")

    plain, plain_reason = looks_like_plaintext_firmware(
        path, original_name=path.name, data=blob, ignore_filename=True
    )
    ent = shannon_entropy(blob[: min(len(blob), 65_536)])
    ivt = parse_ivt(blob)
    # `ok` can be true for a parseable vector table layout that is still unlikely Cortex-M.
    ivt_ok = bool(ivt.get("likely"))

    fmt = "bin"
    name_l = path.name.lower()
    if name_l.endswith(".enc") or name_l.endswith(".bin.enc"):
        fmt = "enc"
    elif name_l.endswith(".zip"):
        fmt = "zip"

    arch = "ARM:LE:32:Cortex" if ivt_ok else None
    base_addr = "0x08000000" if ivt_ok else None

    # Catalog outcomes override readiness when present
    if catalog_meta:
        st = str(catalog_meta.get("status") or "")
        completeness = str(catalog_meta.get("completenessStatus") or catalog_meta.get("analysisCompleteness") or "")
        if st == "failed":
            return _status(
                ANALYSIS_FAILED,
                sha=sha,
                size=size,
                format=fmt,
                architecture=arch or catalog_meta.get("processor"),
                base_addr=base_addr,
                ivt=ivt_ok,
                entropy=ent,
                plain=plain,
                plain_reason=plain_reason,
                reasons=[f"catalog failed: {catalog_meta.get('error') or 'unknown'}"],
                limitations=list(catalog_meta.get("analysisLimitations") or [])
                + ["Katalogstatus=failed — Importfehler ≠ defekte Firmware."],
                catalog=catalog_meta,
            )
        if completeness in {"PARTIAL_ANALYSIS", "TRUNCATED", ANALYSIS_PARTIAL} or catalog_meta.get("truncated"):
            return _status(
                ANALYSIS_PARTIAL,
                sha=sha,
                size=size,
                format=fmt,
                architecture=str(catalog_meta.get("processor") or arch or ""),
                base_addr=base_addr,
                ivt=ivt_ok,
                entropy=ent,
                plain=plain,
                plain_reason=plain_reason,
                reasons=["catalog partial/truncated"],
                limitations=list(catalog_meta.get("analysisLimitations") or []),
                catalog=catalog_meta,
            )
        if st == "ok" and str(catalog_meta.get("analyzerCompat") or "") == ANALYZER_COMPAT:
            return _status(
                ANALYSIS_COMPLETED,
                sha=sha,
                size=size,
                format=fmt,
                architecture=str(catalog_meta.get("processor") or arch or ""),
                base_addr=str(catalog_meta.get("baseAddr") or base_addr or ""),
                ivt=ivt_ok,
                entropy=ent,
                plain=plain,
                plain_reason=plain_reason,
                reasons=["compatible catalog present"],
                limitations=list(catalog_meta.get("analysisLimitations") or [])
                + [
                    "Vollständiger Funktionskatalog ≠ Nachweis, dass die gesamte Firmware analysiert wurde."
                ],
                catalog=catalog_meta,
            )

    if fmt == "enc" and not plain and ent >= 7.5:
        return _status(
            ENCRYPTED_UNSUPPORTED,
            sha=sha,
            size=size,
            format=fmt,
            entropy=ent,
            plain=False,
            plain_reason=plain_reason,
            reasons=["encrypted high-entropy payload"],
            limitations=["Verschlüsseltes Image ohne unterstützten Decoder-Pfad."],
        )

    if not ivt_ok:
        # Large BLE images often lack classic Cortex-M IVT at offset 0.
        ctl = str((ref or {}).get("controllerType") or "").upper()
        reasons.append("no_cortex_m_ivt_at_offset_0")
        if ctl == "BLE" or size > 200_000:
            limitations.append(
                "Kein Cortex-M-IVT am Dateianfang — Architektur unbekannt oder anderes Layout "
                "(häufig bei BLE-Images). Fehlschlag ≠ defekte Firmware."
            )
            return _status(
                ARCHITECTURE_UNKNOWN,
                sha=sha,
                size=size,
                format=fmt,
                entropy=ent,
                plain=plain,
                plain_reason=plain_reason,
                ivt=False,
                reasons=reasons,
                limitations=limitations,
            )
        return _status(
            INVALID_FIRMWARE_LAYOUT,
            sha=sha,
            size=size,
            format=fmt,
            entropy=ent,
            plain=plain,
            plain_reason=plain_reason,
            ivt=False,
            reasons=reasons + ["unexpected layout for assumed Cortex-M flash image"],
            limitations=[
                "Layout passt nicht zur erwarteten Cortex-M-Vektortabelle.",
                "Importfehler separat dokumentieren — nicht automatisch als defekt werten.",
            ],
        )

    preferred = size <= _PREFERRED_GHIDRA_MAX
    if not preferred:
        limitations.append(
            f"Größe {size} B über bevorzugtem Ghidra-Limit {_PREFERRED_GHIDRA_MAX} B "
            "für 4‑GB-VPS — sequentiell und mit Speichercap analysieren."
        )

    return _status(
        READY_FOR_ANALYSIS,
        sha=sha,
        size=size,
        format=fmt,
        architecture="ARM:LE:32:Cortex",
        base_addr="0x08000000",
        ivt=True,
        entropy=ent,
        plain=plain,
        plain_reason=plain_reason,
        reasons=["cortex_m_ivt"] + ([f"plaintext:{plain_reason}"] if plain else []),
        limitations=limitations
        + [
            "Ghidra ARM:LE:32:Cortex Headless vorausgesetzt.",
            "Decoder: Klartext-BIN; NinebotTEA nur bei ENC falls unterstützt.",
        ],
        preferred_ghidra=preferred,
    )


def select_calibration_candidates(
    inventory: dict[str, Any] | None = None,
    *,
    limit: int = 3,
    controllers: tuple[str, ...] = ("VCU", "MCU"),
) -> list[dict[str, Any]]:
    """Pick small READY_FOR_ANALYSIS refs for sequential isolated Ghidra runs."""
    inv = inventory or inventory_references()
    ready = [
        r
        for r in (inv.get("references") or [])
        if r.get("analyzabilityStatus") == READY_FOR_ANALYSIS
        and str(r.get("controllerType") or "").upper() in {c.upper() for c in controllers}
    ]
    ready.sort(key=lambda r: int(r.get("byteCount") or 10**12))
    return ready[: max(0, int(limit))]


def _inventory_one(ref: dict[str, Any], *, include_file_probe: bool) -> dict[str, Any]:
    pub = _public_ref(ref)
    trust = _trust_fields_for_ref(ref)
    path = Path(ref.get("path") or "")
    sha = str(ref.get("sha256") or "")
    catalog = load_catalog_meta(sha) if sha else None
    assess: dict[str, Any]
    if include_file_probe and path.is_file():
        assess = assess_analyzability(path, ref=ref, catalog_meta=catalog)
    else:
        assess = _status(
            INCOMPLETE_FILE if not path.is_file() else ARCHITECTURE_UNKNOWN,
            sha=sha,
            size=int(ref.get("byteCount") or 0),
            reasons=["file probe skipped or missing"],
            limitations=["Datei-Probe übersprungen."],
            catalog=catalog,
        )

    return {
        "id": pub.get("id") or ref.get("id"),
        "label": pub.get("label") or ref.get("label"),
        "manufacturer": pub.get("manufacturer") or ref.get("manufacturer") or "Segway-Ninebot (community archive)",
        "model": pub.get("model") or ref.get("model"),
        "modelAliases": pub.get("modelAliases") or ref.get("models") or [],
        "controllerType": pub.get("controllerType") or ref.get("controllerType"),
        "firmwareVersion": pub.get("firmwareVersion") or pub.get("version") or ref.get("version"),
        "hardwareVersion": pub.get("hardwareVersion") or "",
        "region": pub.get("region") or ref.get("region") or "",
        "source": ref.get("source") or "unknown",
        "sourceNote": "source=oem means archive tag only — not verified manufacturer provenance.",
        "referenceTrust": trust.get("referenceTrust"),
        "referenceProvenanceVerified": bool(trust.get("referenceProvenanceVerified")),
        "verificationStatus": pub.get("verificationStatus"),
        "byteCount": pub.get("byteCount") or ref.get("byteCount"),
        "sha256": sha,
        "file": Path(ref.get("file") or path.name).name,
        "format": assess.get("format") or "bin",
        "architecture": assess.get("architecture"),
        "baseAddr": assess.get("baseAddr"),
        "ivtLikely": assess.get("ivtLikely"),
        "entropy": assess.get("entropy"),
        "plaintextLikely": assess.get("plaintextLikely"),
        "analyzabilityStatus": assess.get("status"),
        "analyzabilityReasons": assess.get("reasons"),
        "preferredForGhidra": assess.get("preferredForGhidra"),
        "catalogPresent": bool(catalog),
        "catalogStatus": (catalog or {}).get("status"),
        "catalogAnalyzerCompat": (catalog or {}).get("analyzerCompat"),
        "catalogCompleteness": (catalog or {}).get("completenessStatus")
        or (catalog or {}).get("analysisCompleteness"),
        "catalogFunctionCount": (catalog or {}).get("functionCount"),
        "analysisLimitations": assess.get("analysisLimitations"),
    }


def _load_refs_from(root: Path) -> list[dict[str, Any]]:
    """Minimal flat loader for tests (manifest + bins under a temp root)."""
    import json

    man = root / "manifest.json"
    refs: list[dict[str, Any]] = []
    if man.is_file():
        data = json.loads(man.read_text(encoding="utf-8"))
        entries = data if isinstance(data, list) else (data.get("references") or [])
        for e in entries:
            if not isinstance(e, dict):
                continue
            p = root / Path(str(e.get("file") or "")).name
            refs.append({**e, "path": str(p) if p.is_file() else str(p)})
    return refs


def _status(
    status: str,
    *,
    sha: str = "",
    size: int = 0,
    format: str = "bin",
    architecture: str | None = None,
    base_addr: str | None = None,
    ivt: bool | None = None,
    entropy: float | None = None,
    plain: bool | None = None,
    plain_reason: str | None = None,
    reasons: list[str] | None = None,
    limitations: list[str] | None = None,
    catalog: dict[str, Any] | None = None,
    preferred_ghidra: bool | None = None,
) -> dict[str, Any]:
    return {
        "status": status,
        "sha256": sha,
        "byteCount": size,
        "format": format,
        "architecture": architecture,
        "baseAddr": base_addr,
        "ivtLikely": ivt,
        "entropy": round(entropy, 3) if isinstance(entropy, float) else entropy,
        "plaintextLikely": plain,
        "plaintextReason": plain_reason,
        "reasons": list(reasons or []),
        "analysisLimitations": list(limitations or []),
        "preferredForGhidra": preferred_ghidra,
        "catalogMeta": catalog,
        "ghidraSupported": architecture == "ARM:LE:32:Cortex",
        "decoderAvailable": True if plain or format == "bin" else False,
    }
