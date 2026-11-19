"""Load/summarize Ghidra ExportFunctionAnalysis JSON (Phase 2)."""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

# Soft caps for poll payload summaries (full JSON via dedicated endpoint).
MAX_SUMMARY_FUNCTIONS = int(os.environ.get("FW_FUNC_SUMMARY_MAX", "40") or "40")
MAX_POLL_FUNCTIONS = int(os.environ.get("FW_FUNC_POLL_MAX", "0") or "0")  # 0 = summary only


def load_function_analysis(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {
            "ok": False,
            "schemaVersion": 1,
            "functions": [],
            "functionCount": 0,
            "notes": ["functionAnalysis=missing"],
            "analysisLimitations": ["Kein Ghidra-Funktionsexport vorhanden."],
        }
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return {
            "ok": False,
            "schemaVersion": 1,
            "functions": [],
            "functionCount": 0,
            "notes": [f"functionAnalysis=badjson:{e}"],
            "analysisLimitations": ["Funktionsexport JSON ungültig."],
        }
    if not isinstance(data, dict):
        return {
            "ok": False,
            "schemaVersion": 1,
            "functions": [],
            "functionCount": 0,
            "notes": ["functionAnalysis=not-object"],
            "analysisLimitations": ["Unerwartetes Exportformat."],
        }
    fns = data.get("functions") or []
    if not isinstance(fns, list):
        fns = []
    limitations = []
    if data.get("truncated"):
        limitations.append(
            f"Export gekürzt (maxFunctions={data.get('maxFunctions')}, "
            f"skipped={data.get('truncatedSkipped')})."
        )
    if not fns:
        limitations.append("Leere Funktionsliste — Analyse ggf. fehlgeschlagen oder Image ohne Funktionen.")
    return {
        "ok": True,
        "schemaVersion": int(data.get("schemaVersion") or 1),
        "program": data.get("program"),
        "processor": data.get("processor"),
        "imageBase": data.get("imageBase"),
        "actualImageBase": data.get("actualImageBase") or data.get("imageBase"),
        "requestedLoaderBase": data.get("requestedLoaderBase"),
        "memoryBlockStart": data.get("memoryBlockStart"),
        "resetHandlerAddress": data.get("resetHandlerAddress"),
        "firmwareFileOffset": data.get("firmwareFileOffset"),
        "analysisProfile": data.get("analysisProfile"),
        "functions": fns,
        "functionCount": int(data.get("functionCount") or len(fns)),
        "truncated": bool(data.get("truncated")),
        "notes": [f"functionAnalysis=ok count={len(fns)}"],
        "analysisLimitations": limitations,
    }


def summarize_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    """Compact summary safe for job polling — no uncontrolled large arrays."""
    fns = full.get("functions") or []
    sample = fns[:MAX_SUMMARY_FUNCTIONS] if isinstance(fns, list) else []
    out = {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "functionCount": full.get("functionCount", len(sample)),
        "truncated": bool(full.get("truncated")),
        "processor": full.get("processor"),
        "program": full.get("program"),
        "imageBase": full.get("imageBase"),
        "actualImageBase": full.get("actualImageBase"),
        "requestedLoaderBase": full.get("requestedLoaderBase"),
        "memoryBlockStart": full.get("memoryBlockStart"),
        "resetHandlerAddress": full.get("resetHandlerAddress"),
        "analysisProfile": full.get("analysisProfile"),
        "notes": list(full.get("notes") or []),
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "sampleFunctions": [
            {
                "address": f.get("address"),
                "name": f.get("name"),
                "size": f.get("size"),
                "basicBlocks": f.get("basicBlocks"),
                "fingerprint": f.get("fingerprint"),
                "confidence": f.get("confidence"),
            }
            for f in sample
            if isinstance(f, dict)
        ],
    }
    if MAX_POLL_FUNCTIONS > 0 and isinstance(fns, list):
        out["functions"] = fns[:MAX_POLL_FUNCTIONS]
    return out


def load_call_graph(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {
            "ok": False,
            "schemaVersion": 1,
            "edges": [],
            "edgeCount": 0,
            "notes": ["callGraph=missing"],
            "analysisLimitations": ["Kein Callgraph-Export vorhanden."],
        }
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return {
            "ok": False,
            "schemaVersion": 1,
            "edges": [],
            "edgeCount": 0,
            "notes": [f"callGraph=badjson:{e}"],
            "analysisLimitations": ["Callgraph JSON ungültig."],
        }
    edges = data.get("edges") or []
    if not isinstance(edges, list):
        edges = []
    limitations = []
    if data.get("truncated"):
        limitations.append("Callgraph Export gekürzt (Limits).")
    static_n = sum(1 for e in edges if isinstance(e, dict) and e.get("evidence") == "static")
    heur_n = int(data.get("heuristicCount") or 0)
    unr_n = int(data.get("unresolvedCount") or 0)
    out = {
        "ok": True,
        "schemaVersion": int(data.get("schemaVersion") or 1),
        "featuresVersion": data.get("featuresVersion"),
        "edges": edges,
        "edgeCount": int(data.get("edgeCount") or len(edges)),
        "functionCount": data.get("functionCount"),
        "staticEdgeCount": static_n,
        "heuristicCount": heur_n,
        "unresolvedCount": unr_n,
        "truncated": bool(data.get("truncated")),
        "callGraphQuality": data.get("callGraphQuality"),
        "analysisProfile": data.get("analysisProfile"),
        "notes": [f"callGraph=ok edges={len(edges)}"],
        "analysisLimitations": limitations,
        "dotPath": str(path).replace(".json", ".dot") if path.with_suffix(".dot").exists() or Path(str(path).replace(".json", ".dot")).exists() else None,
    }
    try:
        from callgraph_quality import enrich_call_graph

        out = enrich_call_graph(out)
    except Exception:
        pass
    return out


def summarize_call_graph_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    edges = full.get("edges") or []
    sample = edges[:30] if isinstance(edges, list) else []
    quality = full.get("callGraphQuality") or {}
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "edgeCount": full.get("edgeCount", len(sample)),
        "staticEdgeCount": full.get("staticEdgeCount"),
        "heuristicCount": full.get("heuristicCount"),
        "unresolvedCount": full.get("unresolvedCount"),
        "truncated": bool(full.get("truncated")),
        "callGraphQuality": {
            "directCalls": quality.get("directCalls"),
            "indirectCalls": quality.get("indirectCalls"),
            "internalBranches": quality.get("internalBranches"),
            "tailCalls": quality.get("tailCalls"),
            "unresolvedCalls": quality.get("unresolvedCalls"),
            "unknownControlFlow": quality.get("unknownControlFlow"),
            "source": quality.get("source"),
            "notes": quality.get("notes"),
        }
        if quality
        else None,
        "notes": list(full.get("notes") or []),
        "analysisLimitations": list(full.get("analysisLimitations") or [])
        + list(quality.get("analysisLimitations") or []),
        "sampleEdges": sample,
    }
