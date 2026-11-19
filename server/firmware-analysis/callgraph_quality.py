"""Call-graph quality classification (Phase 2.2F).

Reclassifies edges so internal branches are never counted as unresolved calls.
Works on new ExportCallGraph (schemaVersion≥2) and legacy exports.
"""
from __future__ import annotations

from typing import Any

DIRECT_CALL = "DIRECT_CALL"
INDIRECT_CALL = "INDIRECT_CALL"
INTERNAL_BRANCH = "INTERNAL_BRANCH"
TAIL_CALL = "TAIL_CALL"
UNRESOLVED_CALL = "UNRESOLVED_CALL"
UNKNOWN_CONTROL_FLOW = "UNKNOWN_CONTROL_FLOW"


def classify_edge(edge: dict[str, Any], *, function_ranges: dict[str, tuple[int, int]] | None = None) -> str:
    """Return classification for one edge."""
    existing = edge.get("classification")
    if isinstance(existing, str) and existing in {
        DIRECT_CALL,
        INDIRECT_CALL,
        INTERNAL_BRANCH,
        TAIL_CALL,
        UNRESOLVED_CALL,
        UNKNOWN_CONTROL_FLOW,
    }:
        return existing

    evidence = str(edge.get("evidence") or "").lower()
    kind = str(edge.get("kind") or "").lower()
    to_name = edge.get("toName")
    to_addr = edge.get("to")

    if evidence == "static" or kind in {"direct"}:
        return DIRECT_CALL
    if evidence == "internal" or kind == "internal":
        return INTERNAL_BRANCH
    if evidence == "tail":
        return TAIL_CALL
    if kind == "indirect" or evidence == "heuristic":
        return INDIRECT_CALL
    if evidence == "unresolved":
        # Legacy exporters tagged internal jumps as unresolved when target ≠ function entry.
        if kind in {"jump", "branch"} and to_addr and to_name is None:
            # Without function body ranges we cannot prove internal — mark UNKNOWN not UNRESOLVED_CALL
            # unless kind was explicitly "call".
            return UNKNOWN_CONTROL_FLOW
        if kind == "call":
            return UNRESOLVED_CALL
        return UNKNOWN_CONTROL_FLOW
    if kind == "call" and to_name:
        return DIRECT_CALL
    if kind == "jump" and to_name:
        return TAIL_CALL
    if kind == "jump":
        return UNKNOWN_CONTROL_FLOW
    return UNKNOWN_CONTROL_FLOW


def analyze_callgraph_quality(call_graph: dict[str, Any] | None) -> dict[str, Any]:
    """Build callGraphQuality summary; reclassify legacy edges when needed."""
    limitations = [
        "Interne Sprünge sind keine unresolved Funktionsaufrufe.",
        "Callgraph-Qualität ist strukturell — kein Manipulationsnachweis.",
    ]
    if not call_graph or not call_graph.get("ok", True):
        # allow ok missing for raw export dicts
        if not call_graph or not isinstance(call_graph.get("edges"), list):
            return {
                "ok": False,
                "schemaVersion": 1,
                "directCalls": 0,
                "indirectCalls": 0,
                "internalBranches": 0,
                "tailCalls": 0,
                "unresolvedCalls": 0,
                "unknownControlFlow": 0,
                "edgeCount": 0,
                "analysisLimitations": limitations + ["Callgraph fehlt/ungültig."],
                "notes": ["callGraphQuality=missing"],
            }

    # Prefer embedded quality from Ghidra export when present and complete
    embedded = call_graph.get("callGraphQuality")
    edges = [e for e in (call_graph.get("edges") or []) if isinstance(e, dict)]
    if isinstance(embedded, dict) and any(
        isinstance(embedded.get(k), int)
        for k in ("directCalls", "internalBranches", "unresolvedCalls")
    ):
        quality = {
            "ok": True,
            "schemaVersion": 1,
            "directCalls": int(embedded.get("directCalls") or 0),
            "indirectCalls": int(embedded.get("indirectCalls") or 0),
            "internalBranches": int(embedded.get("internalBranches") or 0),
            "tailCalls": int(embedded.get("tailCalls") or 0),
            "unresolvedCalls": int(embedded.get("unresolvedCalls") or 0),
            "unknownControlFlow": int(embedded.get("unknownControlFlow") or 0),
            "edgeCount": int(call_graph.get("edgeCount") or len(edges)),
            "source": "ghidra_export",
            "analysisLimitations": limitations,
            "notes": [
                f"callGraphQuality=export direct={embedded.get('directCalls')} "
                f"internal={embedded.get('internalBranches')} unresolved={embedded.get('unresolvedCalls')}"
            ],
        }
        return quality

    counts = {
        DIRECT_CALL: 0,
        INDIRECT_CALL: 0,
        INTERNAL_BRANCH: 0,
        TAIL_CALL: 0,
        UNRESOLVED_CALL: 0,
        UNKNOWN_CONTROL_FLOW: 0,
    }
    reclassified = 0
    for e in edges:
        cls = classify_edge(e)
        if e.get("classification") != cls:
            reclassified += 1
            e = {**e, "classification": cls}
        counts[cls] = counts.get(cls, 0) + 1

    return {
        "ok": True,
        "schemaVersion": 1,
        "directCalls": counts[DIRECT_CALL],
        "indirectCalls": counts[INDIRECT_CALL],
        "internalBranches": counts[INTERNAL_BRANCH],
        "tailCalls": counts[TAIL_CALL],
        "unresolvedCalls": counts[UNRESOLVED_CALL],
        "unknownControlFlow": counts[UNKNOWN_CONTROL_FLOW],
        "edgeCount": int(call_graph.get("edgeCount") or len(edges)),
        "reclassifiedEdgeCount": reclassified,
        "source": "python_reclassify",
        "analysisLimitations": limitations
        + [
            "Legacy-Exports ohne classification: Jump→ohne Ziel als UNKNOWN_CONTROL_FLOW, "
            "nicht als UNRESOLVED_CALL."
        ],
        "notes": [
            f"callGraphQuality=reclassify direct={counts[DIRECT_CALL]} "
            f"internal={counts[INTERNAL_BRANCH]} unresolved={counts[UNRESOLVED_CALL]} "
            f"unknown={counts[UNKNOWN_CONTROL_FLOW]}"
        ],
    }


def enrich_call_graph(full: dict[str, Any]) -> dict[str, Any]:
    """Attach callGraphQuality to a loaded call-graph blob."""
    out = dict(full)
    quality = analyze_callgraph_quality(full)
    out["callGraphQuality"] = quality
    # Correct legacy unresolvedCount for poll consumers when we reclassified
    if quality.get("source") == "python_reclassify":
        out["unresolvedCount"] = quality.get("unresolvedCalls")
        out["heuristicCount"] = quality.get("indirectCalls")
    return out
