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

    subject_sha = hashlib.sha256(plaintext).hexdigest()
    exact = next((r for r in refs if r.get("sha256") == subject_sha), None)
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
        )

    candidates = _filter_refs(refs, models=models or [], controller_type=controller_type)
    if not candidates:
        candidates = refs

    best: dict[str, Any] | None = None
    best_diff: dict[str, Any] | None = None
    for ref in candidates:
        path = Path(ref["path"])
        if not path.is_file():
            continue
        ref_data = path.read_bytes()
        diff = _byte_diff(plaintext, ref_data)
        if best_diff is None or diff["differingBytes"] < best_diff["differingBytes"]:
            best = ref
            best_diff = diff

    if best is None or best_diff is None:
        return _result(
            outcome="noReference",
            note="Stock-Einträge ohne lesbare Datei.",
            subjectBytes=len(plaintext),
        )

    pct = None
    denom = max(len(plaintext), best["byteCount"], 1)
    pct = round(100.0 * best_diff["differingBytes"] / denom, 3)

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
        segments=best_diff["segments"],
        percentDifferent=pct,
        note=(
            f"Byte-Diff gegen Stock „{best['label']}“ (source={best.get('source') or 'unknown'}): "
            f"{best_diff['differingBytes']} abweichende Bytes ({pct}%)."
        ),
        trustedRefCount=len(refs),
        totalRefCount=len(refs_all),
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
                by_sha[data_sha] = {
                    "id": str(e.get("id") or data_sha[:16]),
                    "label": str(e.get("label") or path.name),
                    "model": str(e.get("model") or ""),
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
    return {
        "id": r["id"],
        "label": r["label"],
        "model": r.get("model") or "",
        "controllerType": r.get("controllerType") or "",
        "version": r.get("version") or "",
        "source": _normalize_source(str(r.get("source") or "unknown")),
        "region": r.get("region") or "",
        "notes": r.get("notes") or "",
        "trusted": _is_trusted(r),
        "sha256": r["sha256"],
        "byteCount": r["byteCount"],
    }


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
    }
    base.update(kwargs)
    return base
