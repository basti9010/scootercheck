"""Isolated reference-catalog batch builder (Phase 2.2F).

Writes catalogs ONLY to a separate test directory — never into productive
STOCK_FW_DIR/catalogs. Does not elevate trust. Sequential Ghidra under caller lock.
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
from reference_catalog import ANALYZER_COMPAT, ANALYZER_ID, CATALOG_SCHEMA
from reference_inventory import READY_FOR_ANALYSIS, assess_analyzability, select_calibration_candidates
from stock_diff import _load_refs, _public_ref, _trust_fields_for_ref

try:
    from callgraph_quality import enrich_call_graph
except Exception:  # pragma: no cover
    def enrich_call_graph(x: dict[str, Any]) -> dict[str, Any]:
        return x


def default_batch_root() -> Path:
    return Path(
        os.environ.get("STOCK_CATALOG_BATCH_DIR")
        or "/tmp/scootercheck-catalog-batch"
    )


def run_catalog_batch(
    *,
    limit: int = 4,
    controllers: tuple[str, ...] = ("VCU", "MCU"),
    batch_root: Path | None = None,
    processor: str = "ARM:LE:32:Cortex",
    base_addr: str = "0x08000000",
    timeout_sec: int = 600,
    force: bool = False,
) -> dict[str, Any]:
    """Build catalogs for READY_FOR_ANALYSIS refs into an isolated directory."""
    root = Path(batch_root) if batch_root else default_batch_root()
    root.mkdir(parents=True, exist_ok=True)
    state_path = root / "batch_state.json"
    state = _load_state(state_path)

    if not ghidra_configured():
        return {
            "ok": False,
            "error": "ghidra not configured",
            "batchRoot": str(root),
            "results": [],
            "productiveCatalogsModified": False,
            "note": "No productive catalogs written.",
        }

    candidates = select_calibration_candidates(limit=limit, controllers=controllers)
    # Enrich with full ref path from stock
    refs_by_sha = {str(r.get("sha256") or "").lower(): r for r in _load_refs()}
    results: list[dict[str, Any]] = []

    for cand in candidates:
        sha = str(cand.get("sha256") or "").lower()
        if not sha:
            continue
        if sha in state.get("completed", {}) and not force:
            results.append({"ok": True, "skipped": True, "sha256": sha, "meta": state["completed"][sha]})
            continue
        ref = refs_by_sha.get(sha)
        if not ref:
            results.append({"ok": False, "sha256": sha, "error": "ref not in stock"})
            continue
        path = Path(ref.get("path") or "")
        assess = assess_analyzability(path, ref=ref)
        if assess.get("status") != READY_FOR_ANALYSIS:
            results.append(
                {
                    "ok": False,
                    "sha256": sha,
                    "error": f"not ready: {assess.get('status')}",
                    "analyzability": assess.get("status"),
                }
            )
            continue

        # Copy to isolated workspace — never write next to productive catalogs
        out_dir = root / "catalogs" / sha
        out_dir.mkdir(parents=True, exist_ok=True)
        try:
            one = _build_one(
                ref,
                out_dir=out_dir,
                processor=processor,
                base_addr=base_addr,
                timeout_sec=timeout_sec,
            )
        except Exception as e:
            one = {"ok": False, "sha256": sha, "error": f"{type(e).__name__}:{e}"}
        results.append(one)
        if one.get("ok") and one.get("meta"):
            state.setdefault("completed", {})[sha] = one["meta"]
            _save_state(state_path, state)
        else:
            state.setdefault("failed", {})[sha] = {
                "error": one.get("error") or (one.get("meta") or {}).get("error"),
                "at": datetime.now(timezone.utc).isoformat(),
            }
            _save_state(state_path, state)

    ok_n = sum(1 for r in results if r.get("ok"))
    summary_path = root / "batch_summary.json"
    summary = {
        "ok": True,
        "schemaVersion": 1,
        "batchRoot": str(root),
        "attempted": len(results),
        "built": ok_n,
        "analyzerCompat": ANALYZER_COMPAT,
        "ghidraVersion": os.environ.get("GHIDRA_VERSION") or "12.2_PUBLIC",
        "productiveCatalogsModified": False,
        "results": results,
        "analyzedAt": datetime.now(timezone.utc).isoformat(),
        "note": "Isolated test batch — productive STOCK_FW_DIR/catalogs untouched; trust unchanged.",
    }
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return summary


def _build_one(
    ref: dict[str, Any],
    *,
    out_dir: Path,
    processor: str,
    base_addr: str,
    timeout_sec: int,
) -> dict[str, Any]:
    path = Path(ref["path"])
    sha = str(ref["sha256"])
    pub = _public_ref(ref)
    trust = _trust_fields_for_ref(ref)

    with tempfile.TemporaryDirectory(prefix="sc-batch-") as td:
        td_path = Path(td)
        # Isolated copy of the bin
        local_bin = td_path / path.name
        shutil.copy2(path, local_bin)
        out_c = td_path / "ref.dec.c"
        functions_json = td_path / "ref.functions.json"
        callgraph_json = td_path / "ref.callgraph.json"
        ok, msg = run_ghidra_decompile(
            local_bin,
            out_c,
            processor=processor,
            base_addr=base_addr,
            timeout_sec=timeout_sec,
            functions_json=functions_json,
            callgraph_json=callgraph_json,
        )
        if not ok or not functions_json.is_file() or functions_json.stat().st_size == 0:
            meta = {
                "schemaVersion": CATALOG_SCHEMA,
                "status": "failed",
                "completenessStatus": "FAILED",
                "firmwareSHA256": sha,
                "error": f"ghidra failed: {msg}",
                "referenceTrust": trust.get("referenceTrust"),
                "referenceProvenanceVerified": bool(trust.get("referenceProvenanceVerified")),
                "analyzerCompat": ANALYZER_COMPAT,
                "isolatedBatch": True,
            }
            (out_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
            (out_dir / "failed.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
            return {"ok": False, "meta": meta, "ghidra": msg}

        shutil.copy2(functions_json, out_dir / "functions.json")
        if callgraph_json.is_file():
            shutil.copy2(callgraph_json, out_dir / "callgraph.json")

        fa = load_function_analysis(out_dir / "functions.json")
        cg = load_call_graph(out_dir / "callgraph.json" if (out_dir / "callgraph.json").is_file() else None)
        cg = enrich_call_graph(cg) if cg.get("ok") else cg
        if cg.get("ok"):
            (out_dir / "callgraph.json").write_text(
                json.dumps({**json.loads((out_dir / "callgraph.json").read_text()), "callGraphQuality": cg.get("callGraphQuality")}, ensure_ascii=False),
                encoding="utf-8",
            )

        fn_count = int(fa.get("functionCount") or 0)
        truncated = bool(fa.get("truncated") or cg.get("truncated"))
        completeness = "TRUNCATED" if truncated else ("FULL_ANALYSIS" if fa.get("ok") and fn_count else "FAILED")
        quality = cg.get("callGraphQuality") or {}
        meta = {
            "schemaVersion": CATALOG_SCHEMA,
            "status": "ok" if fa.get("ok") else "failed",
            "completenessStatus": completeness,
            "analysisCompleteness": completeness,
            "referenceId": pub.get("id") or ref.get("id"),
            "firmwareSHA256": sha,
            "model": pub.get("model") or "",
            "modelAliases": pub.get("modelAliases") or [],
            "controllerType": pub.get("controllerType") or "",
            "firmwareVersion": pub.get("firmwareVersion") or pub.get("version") or "",
            "processor": fa.get("processor") or processor,
            "baseAddr": base_addr,
            "analyzer": ANALYZER_ID,
            "analyzerCompat": ANALYZER_COMPAT,
            "ghidraVersion": os.environ.get("GHIDRA_VERSION") or "12.2_PUBLIC",
            "ghidraMessage": msg,
            "functionCount": fn_count,
            "edgeCount": cg.get("edgeCount") or 0,
            "callGraphQuality": {
                "directCalls": quality.get("directCalls"),
                "indirectCalls": quality.get("indirectCalls"),
                "internalBranches": quality.get("internalBranches"),
                "tailCalls": quality.get("tailCalls"),
                "unresolvedCalls": quality.get("unresolvedCalls"),
                "unknownControlFlow": quality.get("unknownControlFlow"),
            },
            "truncated": truncated,
            "analyzedAt": datetime.now(timezone.utc).isoformat(),
            "referenceTrust": trust.get("referenceTrust"),
            "referenceProvenanceVerified": bool(trust.get("referenceProvenanceVerified")),
            "isolatedBatch": True,
            "productiveCatalogsModified": False,
            "byteCount": pub.get("byteCount") or ref.get("byteCount"),
            "sourceFile": path.name,
            "analysisLimitations": list(fa.get("analysisLimitations") or [])
            + [
                "Isolierter Testkatalog — nicht in produktivem catalogs/-Pfad.",
                "Katalog ändert nicht den Referenz-Vertrauensstatus.",
                "Vollständiger Funktionskatalog ≠ Nachweis vollständiger Firmwareabdeckung.",
            ],
        }
        (out_dir / "meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        return {"ok": meta["status"] == "ok", "meta": meta, "ghidra": msg, "catalogDir": str(out_dir)}


def _load_state(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"completed": {}, "failed": {}}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {"completed": {}, "failed": {}}
    except Exception:
        return {"completed": {}, "failed": {}}


def _save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
