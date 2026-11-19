"""Structured firmware analysis completeness (Phase 2.2E).

Distinguishes recognized functions from unknown true totals.
A complete function catalog does NOT prove the entire firmware was analyzed.
"""
from __future__ import annotations

from typing import Any

FULL_ANALYSIS = "FULL_ANALYSIS"
PARTIAL_ANALYSIS = "PARTIAL_ANALYSIS"
TRUNCATED = "TRUNCATED"
FAILED = "FAILED"
NOT_SUPPORTED = "NOT_SUPPORTED"


def assess_analysis_completeness(
    *,
    function_analysis: dict[str, Any] | None = None,
    call_graph: dict[str, Any] | None = None,
    catalog_meta: dict[str, Any] | None = None,
    analyzability_status: str | None = None,
    matching: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build firmwareAnalysisCoverage / analysisCompleteness payload."""
    limitations: list[str] = [
        "Erkannte Funktionen ≠ bekannte Gesamtzahl aller realen Funktionen.",
        "Vollständiger Katalog ≠ Nachweis vollständiger Firmwareabdeckung.",
    ]
    fa = function_analysis or {}
    cg = call_graph or {}
    meta = catalog_meta or {}

    recognized = int(fa.get("functionCount") or len(fa.get("functions") or []) or 0)
    truncated_export = bool(fa.get("truncated") or meta.get("truncated"))
    skipped = int(fa.get("truncatedSkipped") or meta.get("truncatedSkipped") or 0)
    analyzed = recognized  # export lists analyzed/recognized functions
    unknown_total = True  # true total almost always unknown for opaque firmware

    status = PARTIAL_ANALYSIS
    aborted: list[str] = []
    missing_refs: list[str] = []

    if analyzability_status in {
        "ARCHITECTURE_UNKNOWN",
        "ENCRYPTED_UNSUPPORTED",
        "INVALID_FIRMWARE_LAYOUT",
        "INCOMPLETE_FILE",
        "NOT_SUPPORTED",
    }:
        status = NOT_SUPPORTED
        limitations.append(f"Analyzability={analyzability_status}")
    elif meta.get("status") == "failed" or (fa and fa.get("ok") is False):
        status = FAILED
        aborted.append(str(meta.get("error") or "function analysis failed"))
    elif truncated_export or (matching or {}).get("summary", {}).get("truncated"):
        status = TRUNCATED
        limitations.append("Funktionslimit erreicht — Ergebnis unvollständig.")
    elif fa.get("ok") and recognized > 0 and not truncated_export:
        # Catalog/export finished for recognized set — still not whole-firmware proof.
        status = FULL_ANALYSIS
        limitations.append(
            "FULL_ANALYSIS bezieht sich auf den erzeugten Funktionskatalog/Export, "
            "nicht auf eine bekannte Gesamtfunktionenzahl der Firmware."
        )
    elif not fa or not fa.get("ok"):
        status = FAILED if analyzability_status == "ANALYSIS_FAILED" else PARTIAL_ANALYSIS
        aborted.append("function export missing/invalid")

    if not meta and not (fa and fa.get("ok")):
        missing_refs.append("reference_catalog")

    match_summary = (matching or {}).get("summary") or {}
    coverage = {
        "recognizedFunctionCount": recognized,
        "analyzedFunctionCount": analyzed,
        "unanalyzedFunctionCount": skipped if truncated_export else None,
        "unknownTrueFunctionTotal": unknown_total,
        "trueFunctionTotal": None,
        "callGraphEdgeCount": cg.get("edgeCount"),
        "unresolvedCallCount": cg.get("unresolvedCount"),
        "truncated": truncated_export or bool(match_summary.get("truncated")),
        "maxFunctions": match_summary.get("maxFunctions") or fa.get("maxFunctions") or meta.get("maxFunctions"),
        "matchingTruncated": bool(match_summary.get("truncated")),
        "matched": match_summary.get("matched"),
        "ambiguous": match_summary.get("ambiguous"),
        "unmatched": match_summary.get("unmatched"),
    }

    catalog_coverage = None
    if meta:
        catalog_coverage = {
            "present": True,
            "status": meta.get("status"),
            "analyzerCompat": meta.get("analyzerCompat"),
            "completenessStatus": meta.get("completenessStatus")
            or meta.get("analysisCompleteness")
            or status,
            "functionCount": meta.get("functionCount"),
            "truncated": bool(meta.get("truncated")),
            "firmwareSHA256": meta.get("firmwareSHA256"),
            "referenceTrust": meta.get("referenceTrust"),
            "ghidraVersion": meta.get("ghidraVersion"),
            "processor": meta.get("processor"),
            "baseAddr": meta.get("baseAddr"),
        }
    else:
        catalog_coverage = {"present": False}

    return {
        "ok": True,
        "schemaVersion": 1,
        "analysisCompleteness": status,
        "firmwareAnalysisCoverage": coverage,
        "referenceCatalogCoverage": catalog_coverage,
        "functionMatchingCoverage": {
            "truncated": bool(match_summary.get("truncated")),
            "matched": match_summary.get("matched"),
            "ambiguous": match_summary.get("ambiguous"),
            "unmatched": match_summary.get("unmatched"),
            "maxFunctions": match_summary.get("maxFunctions"),
        }
        if matching
        else None,
        "abortedSteps": aborted,
        "missingReferences": missing_refs,
        "analysisLimitations": limitations
        + list(fa.get("analysisLimitations") or [])
        + list(meta.get("analysisLimitations") or []),
        "notes": [
            f"analysisCompleteness={status} recognized={recognized} truncated={truncated_export}"
        ],
    }
