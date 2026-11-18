"""Byte-level stock firmware comparison against a local reference library.

STOCK_FW_DIR layout (either):
  - flat:  zt3_vcu_1.2.1.bin  /  G3_VCU_stock.dec.bin
  - with manifest.json entries:
      {"id","label","model","controllerType","version","source","region","file","sha256"?}

`source` should be oem | serial | unknown | case.
Default compare uses only oem/serial — case uploads must not become references.

Does not prove installation — only that decrypted upload matches/differs from a known stock image.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any

STOCK_FW_DIR = Path(
    os.environ.get("STOCK_FW_DIR", "/var/lib/scootercheck/stock-fw")
)
MAX_SEGMENTS = 12
MAX_SEGMENT_SCAN = 2_000_000  # bytes scanned for segment list
# Beyond this, the "best" OEM candidate is not a useful baseline (e.g. ZT3 48KMH
# vs unrelated zt3 VCU stock) — report honest noReference instead of different.
MAX_USEFUL_PERCENT_DIFFERENT = float(os.environ.get("STOCK_MAX_USEFUL_PCT", "25") or "25")
TRUSTED_SOURCES = frozenset({"oem", "serial"})
ALLOWED_SOURCES = frozenset({"oem", "serial", "unknown", "case"})


def stock_dir() -> Path:
    return STOCK_FW_DIR


def ensure_stock_dir() -> Path:
    STOCK_FW_DIR.mkdir(parents=True, exist_ok=True)
    return STOCK_FW_DIR


def list_stock_refs() -> list[dict[str, Any]]:
    ensure_stock_dir()
    return [_public_ref(r) for r in _load_refs()]


def compare_to_stock(
    plaintext: bytes,
    *,
    models: list[str] | None = None,
    controller_type: str | None = None,
    include_untrusted: bool = False,
    region_hints: list[dict[str, Any]] | None = None,
    strict_model_match: bool = True,
) -> dict[str, Any]:
    if not plaintext:
        return _result(
            outcome="skipped",
            note="Kein Klartext für Stock-Diff.",
        )

    refs_all = _load_refs()
    refs = refs_all if include_untrusted else [r for r in refs_all if _is_trusted(r)]
    if not refs:
        if refs_all and not include_untrusted:
            return _result(
                outcome="noReference",
                note=(
                    f"{len(refs_all)} Stock-Datei(en) vorhanden, aber keine mit source=oem/serial. "
                    "Fall-Uploads (source=case) werden für den Vergleich ignoriert."
                ),
                subjectBytes=len(plaintext),
                trustedRefCount=0,
                totalRefCount=len(refs_all),
            )
        return _result(
            outcome="noReference",
            note=f"Keine OEM-/Serien-Stock-Images in {STOCK_FW_DIR} — Admin kann Referenzen hochladen.",
            subjectBytes=len(plaintext),
            trustedRefCount=0,
            totalRefCount=0,
        )

    model_list = [m for m in (models or []) if m]
    ctype = (controller_type or "").strip() or None
    filtered = _filter_refs(refs, models=model_list, controller_type=ctype)
    # When the caller names model and/or controller, never fall back to unrelated OEM
    # images (e.g. ZT3 must not silently diff against G3 stock).
    scoped = bool(model_list or ctype)
    if scoped and strict_model_match:
        candidates = filtered
        if not candidates:
            want = "/".join(model_list) if model_list else "?"
            want_t = ctype or "?"
            return _result(
                outcome="noReference",
                note=(
                    f"Keine passende OEM-/Serien-Referenz für Modell={want} Typ={want_t} "
                    f"({len(refs)} trusted overall). Kein Cross-Model-Fallback."
                ),
                subjectBytes=len(plaintext),
                trustedRefCount=len(refs),
                totalRefCount=len(refs_all),
                candidateRefCount=0,
                matchedModels=model_list,
            )
    else:
        candidates = filtered or refs

    subject_sha = hashlib.sha256(plaintext).hexdigest()
    exact = next((r for r in candidates if r.get("sha256") == subject_sha), None)
    if exact:
        return _result(
            outcome="identical",
            referenceId=exact["id"],
            referenceLabel=exact["label"],
            referenceSHA256=exact["sha256"],
            referenceSource=exact.get("source") or "unknown",
            differingBytes=0,
            firstDiffOffset=None,
            subjectBytes=len(plaintext),
            referenceBytes=exact["byteCount"],
            segments=[],
            note=f"SHA-256 identisch mit Stock „{exact['label']}“ (source={exact.get('source') or 'unknown'}).",
            trustedRefCount=len(refs),
            totalRefCount=len(refs_all),
            candidateRefCount=len(candidates),
            matchedModels=_ref_models(exact),
            limitRegionAffected=False,
            panicRegionAffected=False,
            regionNotes=[],
            _ref=exact,
        )

    best: dict[str, Any] | None = None
    best_diff: dict[str, Any] | None = None
    best_data: bytes | None = None
    for ref in candidates:
        path = Path(ref["path"])
        if not path.is_file():
            continue
        ref_data = path.read_bytes()
        diff = _byte_diff(plaintext, ref_data)
        if best_diff is None or diff["differingBytes"] < best_diff["differingBytes"]:
            best = ref
            best_diff = diff
            best_data = ref_data

    if best is None or best_diff is None or best_data is None:
        return _result(
            outcome="noReference",
            note="Stock-Einträge ohne lesbare Datei.",
            subjectBytes=len(plaintext),
            trustedRefCount=len(refs),
            totalRefCount=len(refs_all),
            candidateRefCount=len(candidates),
            matchedModels=model_list,
        )

    pct = None
    denom = max(len(plaintext), best["byteCount"], 1)
    pct = round(100.0 * best_diff["differingBytes"] / denom, 3)

    if pct is not None and pct > MAX_USEFUL_PERCENT_DIFFERENT:
        return _result(
            outcome="noReference",
            note=(
                f"Nächster Treffer „{best['label']}“ weicht zu stark ab "
                f"({best_diff['differingBytes']} Bytes / {pct}% > {MAX_USEFUL_PERCENT_DIFFERENT}% Schwelle) "
                "— kein brauchbarer OEM-Baseline-Match."
            ),
            subjectBytes=len(plaintext),
            referenceBytes=best["byteCount"],
            differingBytes=best_diff["differingBytes"],
            percentDifferent=pct,
            firstDiffOffset=best_diff["firstDiffOffset"],
            referenceId=best["id"],
            referenceLabel=best["label"],
            referenceSHA256=best["sha256"],
            referenceSource=best.get("source") or "unknown",
            trustedRefCount=len(refs),
            totalRefCount=len(refs_all),
            candidateRefCount=len(candidates),
            matchedModels=_ref_models(best),
            _ref=best,
        )

    regions = _region_impact(
        plaintext,
        best_data,
        best_diff.get("segments") or [],
        best_diff.get("firstDiffOffset"),
        region_hints=region_hints or [],
    )
    segments = _annotate_segments(best_diff.get("segments") or [], regions)

    region_bits = []
    if regions.get("limitRegionAffected"):
        region_bits.append("Limit-Region betroffen")
    if regions.get("panicRegionAffected"):
        region_bits.append("Panic-/CFW-Region betroffen")
    region_suffix = f" — {', '.join(region_bits)}." if region_bits else "."

    return _result(
        outcome="different",
        referenceId=best["id"],
        referenceLabel=best["label"],
        referenceSHA256=best["sha256"],
        referenceSource=best.get("source") or "unknown",
        differingBytes=best_diff["differingBytes"],
        firstDiffOffset=best_diff["firstDiffOffset"],
        subjectBytes=len(plaintext),
        referenceBytes=best["byteCount"],
        segments=segments,
        percentDifferent=pct,
        note=(
            f"Byte-Diff gegen Stock „{best['label']}“ (source={best.get('source') or 'unknown'}): "
            f"{best_diff['differingBytes']} abweichende Bytes ({pct}%)"
            f"{region_suffix}"
        ),
        trustedRefCount=len(refs),
        totalRefCount=len(refs_all),
        candidateRefCount=len(candidates),
        matchedModels=_ref_models(best),
        limitRegionAffected=bool(regions.get("limitRegionAffected")),
        panicRegionAffected=bool(regions.get("panicRegionAffected")),
        regionNotes=list(regions.get("regionNotes") or []),
        _ref=best,
    )


def register_stock_file(
    data: bytes,
    *,
    label: str,
    model: str,
    controller_type: str,
    version: str,
    filename: str | None = None,
    source: str = "oem",
    region: str = "",
    notes: str = "",
) -> dict[str, Any]:
    ensure_stock_dir()
    src = _normalize_source(source)
    sha = hashlib.sha256(data).hexdigest()
    safe_model = _slug(model or "unknown")
    safe_type = _slug(controller_type or "VCU")
    safe_ver = _slug(version or "unk")
    name = filename or f"{safe_model}_{safe_type}_{safe_ver}_{src}_{sha[:12]}.bin"
    name = Path(name).name.replace("/", "_")
    dest = STOCK_FW_DIR / name
    dest.write_bytes(data)

    manifest_path = STOCK_FW_DIR / "manifest.json"
    entries = []
    if manifest_path.is_file():
        try:
            entries = json.loads(manifest_path.read_text(encoding="utf-8"))
            if not isinstance(entries, list):
                entries = []
        except json.JSONDecodeError:
            entries = []

    entry = {
        "id": sha[:16],
        "label": label or f"{model} {controller_type} {version}",
        "model": model,
        "controllerType": controller_type,
        "version": version,
        "source": src,
        "region": (region or "").strip(),
        "notes": (notes or "").strip(),
        "file": name,
        "sha256": sha,
        "byteCount": len(data),
    }
    entries = [e for e in entries if e.get("sha256") != sha and e.get("file") != name]
    entries.append(entry)
    manifest_path.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return _public_ref({**entry, "path": str(dest)})


def delete_stock_ref(ref_id: str) -> bool:
    ensure_stock_dir()
    refs = _load_refs()
    target = next((r for r in refs if r["id"] == ref_id or r["sha256"].startswith(ref_id)), None)
    if not target:
        return False
    path = Path(target["path"])
    if path.is_file() and path.resolve().is_relative_to(STOCK_FW_DIR.resolve()):
        path.unlink(missing_ok=True)
    manifest_path = STOCK_FW_DIR / "manifest.json"
    if manifest_path.is_file():
        try:
            entries = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            entries = []
        if isinstance(entries, list):
            entries = [e for e in entries if e.get("sha256") != target["sha256"] and e.get("id") != target["id"]]
            manifest_path.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return True


# --- internals ---


def _load_refs() -> list[dict[str, Any]]:
    ensure_stock_dir()
    by_sha: dict[str, dict[str, Any]] = {}

    manifest_path = STOCK_FW_DIR / "manifest.json"
    if manifest_path.is_file():
        try:
            entries = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            entries = []
        if isinstance(entries, list):
            for e in entries:
                if not isinstance(e, dict):
                    continue
                rel = e.get("file")
                if not rel:
                    continue
                path = STOCK_FW_DIR / Path(str(rel)).name
                if not path.is_file():
                    continue
                data_sha = e.get("sha256") or hashlib.sha256(path.read_bytes()).hexdigest()
                models_raw = e.get("models")
                models_list: list[str] = []
                if isinstance(models_raw, list):
                    models_list = [str(x) for x in models_raw if x]
                model_primary = str(e.get("model") or (models_list[0] if models_list else ""))
                if model_primary and model_primary not in models_list:
                    models_list = [model_primary, *models_list]
                by_sha[data_sha] = {
                    "id": str(e.get("id") or data_sha[:16]),
                    "label": str(e.get("label") or path.name),
                    "model": model_primary,
                    "models": models_list,
                    "controllerType": str(e.get("controllerType") or e.get("type") or ""),
                    "version": str(e.get("version") or ""),
                    "source": _normalize_source(str(e.get("source") or "unknown")),
                    "region": str(e.get("region") or ""),
                    "notes": str(e.get("notes") or ""),
                    "sha256": data_sha,
                    "byteCount": int(e.get("byteCount") or path.stat().st_size),
                    "path": str(path),
                }

    for path in sorted(STOCK_FW_DIR.iterdir()):
        if not path.is_file():
            continue
        if path.name in {"manifest.json", ".gitkeep"}:
            continue
        if path.suffix.lower() not in {".bin", ".dec", ".img", ".fw"} and ".bin." not in path.name.lower():
            # allow *.dec.bin
            if not path.name.lower().endswith(".bin"):
                continue
        data = path.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        if sha in by_sha:
            continue
        model, ctype, version = _parse_name(path.name)
        # Flat files without manifest: treat as unknown (not auto-trusted).
        by_sha[sha] = {
            "id": sha[:16],
            "label": path.name,
            "model": model,
            "models": [model] if model else [],
            "controllerType": ctype,
            "version": version,
            "source": "unknown",
            "region": "",
            "notes": "",
            "sha256": sha,
            "byteCount": len(data),
            "path": str(path),
        }

    return list(by_sha.values())


def _filter_refs(
    refs: list[dict[str, Any]],
    *,
    models: list[str],
    controller_type: str | None,
) -> list[dict[str, Any]]:
    model_set = {m.lower() for m in models if m}
    ctype = (controller_type or "").lower()
    out = []
    for r in refs:
        rm = (r.get("model") or "").lower()
        rmodels = {(x or "").lower() for x in (r.get("models") or []) if x}
        rt = (r.get("controllerType") or "").lower()
        label = (r.get("label") or "").lower()
        notes = (r.get("notes") or "").lower()
        model_ok = (not model_set) or any(
            m in rm or m in label or m in notes or m in rmodels or rm in m for m in model_set
        )
        type_ok = (not ctype) or ctype in rt or ctype in label
        if model_ok and type_ok:
            out.append(r)
    return out


def _byte_diff(a: bytes, b: bytes) -> dict[str, Any]:
    n = min(len(a), len(b))
    differing = abs(len(a) - len(b))
    first: int | None = None
    segments: list[dict[str, Any]] = []
    run_start: int | None = None
    scan = min(n, MAX_SEGMENT_SCAN)
    for i in range(scan):
        if a[i] != b[i]:
            differing += 1
            if first is None:
                first = i
            if run_start is None:
                run_start = i
        elif run_start is not None:
            if len(segments) < MAX_SEGMENTS:
                segments.append(
                    {
                        "offset": run_start,
                        "length": i - run_start,
                        "note": f"Diff @{run_start:#x}",
                    }
                )
            run_start = None
    if run_start is not None and len(segments) < MAX_SEGMENTS:
        segments.append(
            {
                "offset": run_start,
                "length": scan - run_start,
                "note": f"Diff @{run_start:#x}",
            }
        )
    # Approximate remaining mismatches beyond scan window
    if n > scan:
        # cheap sample: count mismatch every 16th byte
        extra = 0
        for i in range(scan, n, 16):
            if a[i] != b[i]:
                extra += 16
        differing += extra
        if first is None and extra:
            first = scan
    return {
        "differingBytes": differing,
        "firstDiffOffset": first,
        "segments": segments,
    }


def _parse_name(name: str) -> tuple[str, str, str]:
    stem = Path(name).stem
    # strip .dec etc
    stem = re.sub(r"\.dec$", "", stem, flags=re.I)
    parts = re.split(r"[_\-\s]+", stem)
    model = parts[0] if parts else ""
    ctype = ""
    version = ""
    for p in parts[1:]:
        up = p.upper()
        if up in {"VCU", "MCU", "BLE", "BMS", "ESC"} and not ctype:
            ctype = up
        elif re.match(r"^\d+(\.\d+)+$", p) and not version:
            version = p
    return model, ctype, version


def _slug(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s.strip())
    return s[:64] or "x"


def _public_ref(r: dict[str, Any]) -> dict[str, Any]:
    trust = _trust_fields_for_ref(r)
    return {
        "id": r["id"],
        "label": r["label"],
        "model": r.get("model") or "",
        "models": list(r.get("models") or ([r.get("model")] if r.get("model") else [])),
        "controllerType": r.get("controllerType") or "",
        "version": r.get("version") or "",
        "source": _normalize_source(str(r.get("source") or "unknown")),
        "region": r.get("region") or "",
        "notes": r.get("notes") or "",
        "trusted": _is_trusted(r),
        "sha256": r["sha256"],
        "byteCount": r["byteCount"],
        "referenceTrust": trust["referenceTrust"],
        "provenanceVerified": bool(trust["referenceProvenanceVerified"]),
    }


def _ref_models(r: dict[str, Any]) -> list[str]:
    models = [str(x) for x in (r.get("models") or []) if x]
    primary = str(r.get("model") or "")
    if primary and primary not in models:
        models = [primary, *models]
    return models


def _region_impact(
    subject: bytes,
    reference: bytes,
    segments: list[dict[str, Any]],
    first_diff: int | None,
    *,
    region_hints: list[dict[str, Any]],
) -> dict[str, Any]:
    """Mark whether byte-diff overlaps limit/speed or panic/CFW-ish regions."""
    panic_needles = (
        b"panic",
        b"Panic",
        b"PANIC",
        b"softunlock",
        b"SoftUnlock",
        b"SOFTUNLOCK",
        b"panicsystem",
        b"panicbutton",
    )
    limit_needles = (
        b"speed",
        b"Speed",
        b"SPEED",
        b"limit",
        b"Limit",
        b"km/h",
        b"kmh",
        b"KMH",
    )

    def _find_hits(blob: bytes, needles: tuple[bytes, ...]) -> list[int]:
        hits: list[int] = []
        for n in needles:
            start = 0
            while True:
                i = blob.find(n, start)
                if i < 0:
                    break
                hits.append(i)
                start = i + 1
                if len(hits) >= 32:
                    return hits
        return hits

    panic_hits = _find_hits(subject, panic_needles) + _find_hits(reference, panic_needles)
    limit_hits = _find_hits(subject, limit_needles) + _find_hits(reference, limit_needles)

    # Immediate values often used as km/h caps in VCU images (centi-km/h or raw)
    for imm in (20, 22, 25, 32, 35, 45, 48, 50, 55, 60, 65, 70, 80, 99):
        pat = bytes([imm, 0, 0, 0])
        for blob in (subject, reference):
            start = 0
            while True:
                i = blob.find(pat, start)
                if i < 0:
                    break
                limit_hits.append(i)
                start = i + 1
                if len(limit_hits) >= 64:
                    break

    for h in region_hints:
        kind = str(h.get("kind") or h.get("role") or "").lower()
        off = h.get("offset")
        if off is None:
            continue
        try:
            oi = int(off)
        except (TypeError, ValueError):
            continue
        if any(k in kind for k in ("panic", "cfw", "unlock", "soft")):
            panic_hits.append(oi)
        if any(k in kind for k in ("limit", "speed", "legal", "open", "cap")):
            limit_hits.append(oi)

    window = 512
    points: list[int] = []
    if first_diff is not None:
        points.append(int(first_diff))
    for seg in segments:
        try:
            o = int(seg.get("offset") or 0)
            ln = int(seg.get("length") or 0)
        except (TypeError, ValueError):
            continue
        points.append(o)
        if ln > 0:
            points.append(o + ln // 2)
            # Sample along the run — short CFW patches often sit inside larger blobs
            step = max(1, ln // 8)
            for x in range(o, o + ln, step):
                points.append(x)

    speed_immediates = {20, 22, 25, 32, 35, 45, 48, 50, 55, 60, 65, 70, 80, 99}
    # Diff bytes that flip a plausible km/h immediate count as limit-region
    for seg in segments:
        try:
            o = int(seg.get("offset") or 0)
            ln = int(seg.get("length") or 0)
        except (TypeError, ValueError):
            continue
        for i in range(o, min(o + max(ln, 4), min(len(subject), len(reference)))):
            if subject[i] != reference[i] and (
                subject[i] in speed_immediates or reference[i] in speed_immediates
            ):
                limit_hits.append(i)

    def _near(hits: list[int]) -> bool:
        for p in points:
            for h in hits:
                if abs(p - h) <= window:
                    return True
        return False

    limit_hit = _near(limit_hits)
    panic_hit = _near(panic_hits)

    # Filename / hint driven: CFW family names imply panic-region relevance when any diff exists
    hint_blob = " ".join(
        str(h.get("label") or "") + " " + str(h.get("kind") or "") for h in region_hints
    ).lower()
    if segments and any(k in hint_blob for k in ("panic", "softunlock", "cfw")):
        panic_hit = True

    notes: list[str] = []
    if limit_hit:
        notes.append("Diff nahe Speed-/Limit-Marker oder -Immediates")
    if panic_hit:
        notes.append("Diff nahe Panic-/SoftUnlock-Marker")
    for h in region_hints[:6]:
        label = h.get("label") or h.get("kind") or h.get("role")
        if label:
            notes.append(f"Hinweis: {label}")

    return {
        "limitRegionAffected": limit_hit,
        "panicRegionAffected": panic_hit,
        "regionNotes": notes,
    }


def _annotate_segments(
    segments: list[dict[str, Any]],
    regions: dict[str, Any],
) -> list[dict[str, Any]]:
    tags: list[str] = []
    if regions.get("limitRegionAffected"):
        tags.append("limit")
    if regions.get("panicRegionAffected"):
        tags.append("panic")
    if not tags:
        return segments
    tag_note = "/".join(tags)
    out = []
    for seg in segments:
        s = dict(seg)
        note = str(s.get("note") or "")
        if tag_note not in note:
            s["note"] = f"{note} [{tag_note}]".strip()
        out.append(s)
    return out


def _normalize_source(source: str) -> str:
    s = (source or "unknown").strip().lower()
    if s in {"oem", "factory", "stock"}:
        return "oem"
    if s in {"serial", "serie", "production"}:
        return "serial"
    if s in {"case", "upload", "incident"}:
        return "case"
    if s in ALLOWED_SOURCES:
        return s
    return "unknown"


def _is_trusted(r: dict[str, Any]) -> bool:
    return _normalize_source(str(r.get("source") or "")) in TRUSTED_SOURCES


def _trust_fields_for_ref(ref: dict[str, Any] | None) -> dict[str, Any]:
    """Map stock source/provenance → client referenceTrust fields.

    Important: `source=oem` in the community library must NOT auto-mean
    manufacturer-verified provenance. Only an explicit `provenanceVerified`
    (or notes marker) elevates trust to manufacturerVerified.
    """
    if not ref:
        return {
            "referenceTrust": "unknown",
            "referenceProvenanceVerified": False,
        }
    src = _normalize_source(str(ref.get("source") or "unknown"))
    notes = str(ref.get("notes") or "").lower()
    label = str(ref.get("label") or "").lower()
    explicit = bool(ref.get("provenanceVerified")) or "provenance=verified" in notes
    if explicit:
        return {
            "referenceTrust": "manufacturerVerified",
            "referenceProvenanceVerified": True,
        }
    if src == "serial" or "serial" in notes or "serie" in notes:
        return {
            "referenceTrust": "serialProduction",
            "referenceProvenanceVerified": False,
        }
    # oem/stock/factory without explicit provenance → community library
    if src in TRUSTED_SOURCES or "community" in notes or "rexzy" in label or "x3-firmware" in notes:
        return {
            "referenceTrust": "communityLibrary",
            "referenceProvenanceVerified": False,
        }
    return {
        "referenceTrust": "unknown",
        "referenceProvenanceVerified": False,
    }


def _result(**kwargs: Any) -> dict[str, Any]:
    base = {
        "outcome": "skipped",
        "referenceId": None,
        "referenceLabel": None,
        "referenceSHA256": None,
        "referenceSource": None,
        "differingBytes": None,
        "firstDiffOffset": None,
        "subjectBytes": None,
        "referenceBytes": None,
        "percentDifferent": None,
        "segments": [],
        "note": "",
        "trustedRefCount": None,
        "totalRefCount": None,
        "candidateRefCount": None,
        "matchedModels": None,
        "limitRegionAffected": None,
        "panicRegionAffected": None,
        "regionNotes": [],
        "referenceTrust": "unknown",
        "referenceProvenanceVerified": False,
    }
    # Auto-fill trust from an optional `_ref` helper key, then drop it.
    ref = kwargs.pop("_ref", None)
    if ref is not None and "referenceTrust" not in kwargs:
        base.update(_trust_fields_for_ref(ref))
    base.update(kwargs)
    return base
