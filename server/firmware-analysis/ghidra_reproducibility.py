"""Normalize Ghidra exports and compare reproducibility (Phase 2.2G)."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def _canon(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: _canon(obj[k]) for k in sorted(obj.keys())}
    if isinstance(obj, list):
        return [_canon(x) for x in obj]
    return obj


def normalize_function_export(data: dict[str, Any]) -> dict[str, Any]:
    """Strip volatile fields; keep semantic function inventory."""
    fns = []
    for f in data.get("functions") or []:
        if not isinstance(f, dict):
            continue
        fns.append(
            {
                "address": f.get("address") or f.get("entry") or f.get("entryPoint"),
                "name": f.get("name"),
                "size": f.get("size"),
                "basicBlocks": f.get("basicBlocks") or f.get("blocks"),
                "cfgEdges": f.get("cfgEdges") or f.get("edges"),
                "fingerprint": f.get("fingerprint"),
            }
        )
    fns.sort(key=lambda x: str(x.get("address") or ""))
    return {
        "processor": data.get("processor"),
        "requestedLoaderBase": data.get("requestedLoaderBase"),
        "actualImageBase": data.get("actualImageBase") or data.get("imageBase"),
        "memoryBlockStart": data.get("memoryBlockStart"),
        "resetHandlerAddress": data.get("resetHandlerAddress"),
        "functionCount": len(fns),
        "functions": fns,
        "analysisProfileHash": (data.get("analysisProfile") or {}).get("analysisProfileHash")
        or data.get("analysisProfileHash"),
    }


def normalize_callgraph_export(data: dict[str, Any]) -> dict[str, Any]:
    edges = []
    for e in data.get("edges") or []:
        if not isinstance(e, dict):
            continue
        edges.append(
            {
                "from": e.get("from"),
                "to": e.get("to"),
                "kind": e.get("kind"),
                "evidence": e.get("evidence"),
                "classification": e.get("classification"),
            }
        )
    edges.sort(key=lambda x: (str(x.get("from")), str(x.get("to")), str(x.get("classification"))))
    q = data.get("callGraphQuality") or {}
    return {
        "edgeCount": len(edges),
        "edges": edges,
        "directCalls": q.get("directCalls"),
        "indirectCalls": q.get("indirectCalls"),
        "internalBranches": q.get("internalBranches"),
        "tailCalls": q.get("tailCalls"),
        "unresolvedCalls": q.get("unresolvedCalls")
        if q.get("unresolvedCalls") is not None
        else data.get("unresolvedCount"),
        "unknownControlFlow": q.get("unknownControlFlow"),
    }


def semantic_hash(obj: dict[str, Any]) -> str:
    blob = json.dumps(_canon(obj), sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def compare_runs(runs: list[dict[str, Any]]) -> dict[str, Any]:
    """Compare multiple analysis run summaries.

    Each run: {functions: dict, callgraph: dict, profileHash?: str}
    """
    if len(runs) < 2:
        return {"ok": False, "error": "need >=2 runs", "reproducible": False}

    norms_f = [normalize_function_export(r.get("functions") or {}) for r in runs]
    norms_c = [normalize_callgraph_export(r.get("callgraph") or {}) for r in runs]
    hf = [semantic_hash(x) for x in norms_f]
    hc = [semantic_hash(x) for x in norms_c]

    fn_counts = [x.get("functionCount") for x in norms_f]
    edge_counts = [x.get("edgeCount") for x in norms_c]
    unresolved = [x.get("unresolvedCalls") for x in norms_c]

    technical_diffs: list[str] = []
    semantic_diffs: list[str] = []
    if len(set(hf)) != 1:
        semantic_diffs.append(f"function inventory hashes differ: {hf}")
    if len(set(hc)) != 1:
        semantic_diffs.append(f"callgraph hashes differ: {hc}")
    if len(set(fn_counts)) != 1:
        semantic_diffs.append(f"functionCount={fn_counts}")
    if len(set(edge_counts)) != 1:
        semantic_diffs.append(f"edgeCount={edge_counts}")

    # Timestamp-only / export-order differences already stripped — remaining = semantic
    reproducible = not semantic_diffs
    return {
        "ok": True,
        "runCount": len(runs),
        "reproducible": reproducible,
        "functionCounts": fn_counts,
        "edgeCounts": edge_counts,
        "unresolvedCalls": unresolved,
        "functionSemanticHash": hf[0] if hf else None,
        "callgraphSemanticHash": hc[0] if hc else None,
        "allFunctionHashesEqual": len(set(hf)) == 1,
        "allCallgraphHashesEqual": len(set(hc)) == 1,
        "semanticDifferences": semantic_diffs,
        "technicalDifferences": technical_diffs,
        "notes": [
            "Normalized comparison ignores timestamps and export order.",
            "Identical input + identical analysisProfile should yield equal semantic hashes.",
        ],
    }


def load_run_pair(functions_path: Path, callgraph_path: Path) -> dict[str, Any]:
    fn = json.loads(Path(functions_path).read_text(encoding="utf-8")) if Path(functions_path).is_file() else {}
    cg = json.loads(Path(callgraph_path).read_text(encoding="utf-8")) if Path(callgraph_path).is_file() else {}
    return {"functions": fn, "callgraph": cg}
