"""OEM/community reference function catalogs (Phase 2.1).

Stores Ghidra ExportFunctionAnalysis / CallGraph JSON beside stock firmware
under STOCK_FW_DIR/catalogs/<sha256>/ without modifying original bins or trust.
"""
from __future__ import annotations

import json
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from function_analysis import load_call_graph, load_function_analysis
from ghidra_decompile import ghidra_configured, run_ghidra_decompile
from stock_diff import (
    STOCK_FW_DIR,
    _load_refs,
    _public_ref,
    _trust_fields_for_ref,
    ensure_stock_dir,
    stock_dir,
)

CATALOG_SCHEMA = 1
ANALYZER_ID = "ghidra-export-function-analysis"
ANALYZER_COMPAT = "1"  # bump when fingerprint/CFG semantics change incompatibly


def catalogs_root() -> Path:
    root = Path(os.environ.get("STOCK_CATALOG_DIR") or (STOCK_FW_DIR / "catalogs"))
    root.mkdir(parents=True, exist_ok=True)
    return root


def catalog_dir_for_sha(sha256: str) -> Path:
    sha = (sha256 or "").lower().strip()
    if len(sha) < 16 or any(c not in "0123456789abcdef" for c in sha):
        raise ValueError("invalid sha256")
    d = catalogs_root() / sha
    d.mkdir(parents=True, exist_ok=True)
    return d


def catalog_paths(sha256: str) -> dict[str, Path]:
    d = catalog_dir_for_sha(sha256)
    return {
        "dir": d,
        "meta": d / "meta.json",
        "functions": d / "functions.json",
        "callgraph": d / "callgraph.json",
        "failed": d / "failed.json",
    }


def load_catalog_meta(sha256: str) -> dict[str, Any] | None:
    p = catalog_paths(sha256)["meta"]
    if not p.is_file():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def load_catalog_functions(sha256: str) -> dict[str, Any] | None:
    paths = catalog_paths(sha256)
    if not paths["functions"].is_file():
        return None
    meta = load_catalog_meta(sha256) or {}
    if meta.get("status") == "failed":
        return None
    if str(meta.get("analyzerCompat") or "") != ANALYZER_COMPAT:
        return None
    if meta.get("firmwareSHA256") and str(meta["firmwareSHA256"]).lower() != sha256.lower():
        return None
    loaded = load_function_analysis(paths["functions"])
    if not loaded.get("ok"):
        return None
    loaded["catalogMeta"] = meta
    return loaded


def find_catalog_for_stock(stock: dict[str, Any] | None) -> dict[str, Any] | None:
    """Return function analysis blob if a compatible catalog exists for the stock match."""
    if not stock or stock.get("outcome") not in {"identical", "different"}:
        return None
    sha = str(stock.get("referenceSHA256") or "").lower()
    if not sha:
        return None
    return load_catalog_functions(sha)


def catalog_compatible_with_subject(
    meta: dict[str, Any],
    *,
    models: list[str] | None = None,
    controller_type: str | None = None,
    processor: str | None = None,
) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    if str(meta.get("analyzerCompat") or "") != ANALYZER_COMPAT:
        reasons.append("analyzerCompat mismatch")
    if meta.get("status") != "ok":
        reasons.append("catalog status not ok")
    ctype = (controller_type or "").strip().lower()
    mctype = str(meta.get("controllerType") or "").strip().lower()
    if ctype and mctype and ctype != mctype:
        reasons.append("controllerType mismatch")
    model_set = {m.lower() for m in (models or []) if m}
    if model_set:
        candidates = {
            str(meta.get("model") or "").lower(),
            *[str(a).lower() for a in (meta.get("modelAliases") or [])],
        }
        if not any(m in candidates or any(m in c for c in candidates if c) for m in model_set):
            # Soft: allow if stockDiff already matched; caller may skip this check.
            reasons.append("model mismatch")
    proc = (processor or "").strip()
    mproc = str(meta.get("processor") or "").strip()
    if proc and mproc and proc != mproc:
        reasons.append("processor mismatch")
    return (len(reasons) == 0), reasons


def list_catalogs() -> list[dict[str, Any]]:
    root = catalogs_root()
    out: list[dict[str, Any]] = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        meta_path = child / "meta.json"
        if not meta_path.is_file():
            continue
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        if isinstance(meta, dict):
            out.append(meta)
    return out


def build_catalog_for_ref(
    ref: dict[str, Any],
    *,
    processor: str = "ARM:LE:32:Cortex",
    base_addr: str = "0x08000000",
    timeout_sec: int = 600,
    force: bool = False,
) -> dict[str, Any]:
    """Run Ghidra function/callgraph export for one stock reference. Never mutates trust."""
    ensure_stock_dir()
    path = Path(ref.get("path") or "")
    sha = str(ref.get("sha256") or "")
    if not path.is_file() or not sha:
        return {"ok": False, "error": "ref missing path/sha256", "referenceId": ref.get("id")}

    paths = catalog_paths(sha)
    existing = load_catalog_meta(sha)
    if existing and existing.get("status") == "ok" and not force:
        if str(existing.get("analyzerCompat")) == ANALYZER_COMPAT:
            return {"ok": True, "skipped": True, "meta": existing}

    if not ghidra_configured():
        fail = _fail_meta(ref, sha, processor, "ghidra not configured")
        paths["failed"].write_text(json.dumps(fail, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        paths["meta"].write_text(json.dumps(fail, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return {"ok": False, "meta": fail}

    pub = _public_ref(ref)
    trust = _trust_fields_for_ref(ref)

    with tempfile.TemporaryDirectory(prefix="stock-catalog-") as td:
        td_path = Path(td)
        out_c = td_path / "ref.dec.c"
        functions_json = td_path / "ref.functions.json"
        callgraph_json = td_path / "ref.callgraph.json"
        ok, msg = run_ghidra_decompile(
            path,
            out_c,
            processor=processor,
            base_addr=base_addr,
            timeout_sec=timeout_sec,
            functions_json=functions_json,
            callgraph_json=callgraph_json,
        )
        if not ok or not functions_json.is_file() or functions_json.stat().st_size == 0:
            fail = _fail_meta(ref, sha, processor, f"ghidra failed: {msg}")
            paths["meta"].write_text(json.dumps(fail, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            paths["failed"].write_text(json.dumps(fail, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            return {"ok": False, "meta": fail, "ghidra": msg}

        shutil.copy2(functions_json, paths["functions"])
        if callgraph_json.is_file() and callgraph_json.stat().st_size > 0:
            shutil.copy2(callgraph_json, paths["callgraph"])
            dot = Path(str(callgraph_json).replace(".json", ".dot"))
            if dot.is_file():
                shutil.copy2(dot, paths["dir"] / "callgraph.dot")

        fa = load_function_analysis(paths["functions"])
        cg = load_call_graph(paths["callgraph"] if paths["callgraph"].is_file() else None)
        meta = {
            "schemaVersion": CATALOG_SCHEMA,
            "status": "ok" if fa.get("ok") else "failed",
            "referenceId": pub.get("id") or ref.get("id"),
            "firmwareSHA256": sha,
            "manufacturer": pub.get("manufacturer") or "",
            "model": pub.get("model") or "",
            "modelAliases": pub.get("modelAliases") or [],
            "controllerType": pub.get("controllerType") or "",
            "firmwareVersion": pub.get("firmwareVersion") or pub.get("version") or "",
            "hardwareVersion": pub.get("hardwareVersion") or "",
            "processor": fa.get("processor") or processor,
            "analyzer": ANALYZER_ID,
            "analyzerCompat": ANALYZER_COMPAT,
            "analyzerNote": "Uses existing Ghidra ExportFunctionAnalysis/ExportCallGraph — no second engine.",
            "ghidraMessage": msg,
            "functionCount": fa.get("functionCount") or len(fa.get("functions") or []),
            "edgeCount": cg.get("edgeCount") or 0,
            "analyzedAt": datetime.now(timezone.utc).isoformat(),
            "analysisQuality": "medium" if fa.get("ok") and (fa.get("functionCount") or 0) > 0 else "low",
            "analysisLimitations": list(fa.get("analysisLimitations") or [])
            + [
                "Katalog ändert nicht den Referenz-Vertrauensstatus.",
                f"referenceTrust={trust.get('referenceTrust')}",
            ],
            "referenceTrust": trust.get("referenceTrust"),
            "referenceProvenanceVerified": bool(trust.get("referenceProvenanceVerified")),
            "verificationStatus": pub.get("verificationStatus"),
            "byteCount": pub.get("byteCount") or ref.get("byteCount"),
            "sourceFile": Path(path).name,
        }
        if not fa.get("ok"):
            meta["status"] = "failed"
            meta["error"] = "function export empty/invalid"
        paths["meta"].write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return {"ok": meta["status"] == "ok", "meta": meta, "ghidra": msg}


def build_catalogs(
    *,
    limit: int | None = None,
    force: bool = False,
    only_sha: str | None = None,
    processor: str = "ARM:LE:32:Cortex",
    timeout_sec: int = 600,
) -> dict[str, Any]:
    """Batch-build catalogs for trusted stock refs (oem/serial). Never elevates trust."""
    ensure_stock_dir()
    refs = _load_refs()
    results: list[dict[str, Any]] = []
    selected = []
    for r in refs:
        sha = str(r.get("sha256") or "")
        if only_sha and sha.lower() != only_sha.lower():
            continue
        selected.append(r)
    if limit is not None:
        selected = selected[: max(0, int(limit))]

    for r in selected:
        try:
            results.append(build_catalog_for_ref(r, processor=processor, timeout_sec=timeout_sec, force=force))
        except Exception as e:
            results.append(
                {
                    "ok": False,
                    "referenceId": r.get("id"),
                    "error": f"{type(e).__name__}:{e}",
                }
            )
    ok_n = sum(1 for x in results if x.get("ok"))
    return {
        "ok": True,
        "built": ok_n,
        "attempted": len(results),
        "results": results,
        "catalogRoot": str(catalogs_root()),
        "note": "Catalog build does not change referenceTrust / provenanceVerified.",
    }


def _fail_meta(ref: dict[str, Any], sha: str, processor: str, error: str) -> dict[str, Any]:
    pub = _public_ref(ref)
    trust = _trust_fields_for_ref(ref)
    return {
        "schemaVersion": CATALOG_SCHEMA,
        "status": "failed",
        "referenceId": pub.get("id") or ref.get("id"),
        "firmwareSHA256": sha,
        "manufacturer": pub.get("manufacturer") or "",
        "model": pub.get("model") or "",
        "controllerType": pub.get("controllerType") or "",
        "firmwareVersion": pub.get("firmwareVersion") or "",
        "processor": processor,
        "analyzer": ANALYZER_ID,
        "analyzerCompat": ANALYZER_COMPAT,
        "analyzedAt": datetime.now(timezone.utc).isoformat(),
        "error": error,
        "referenceTrust": trust.get("referenceTrust"),
        "referenceProvenanceVerified": bool(trust.get("referenceProvenanceVerified")),
        "analysisLimitations": ["Katalogerstellung fehlgeschlagen — Trust unverändert."],
    }
