"""Function-level firmware comparison from Ghidra exports (Phase 2 / 2.2C).

Diaphora / BinDiff are not integrated here:
- BinDiff: proprietary Hex-Rays tooling, not redistributable for this stack.
- Diaphora: GPL Ghidra plugin, heavy install/RAM, awkward headless automation on a 4 GB VPS.

Phase 2.2C uses multi-stage intelligent matching (function_matcher) while keeping
the historical summary counters (IDENTISCH / STRUKTURELL_VERAENDERT / …)
backward-compatible for older app builds.
"""
from __future__ import annotations

from typing import Any

from function_matcher import (
    CONF_AMBIGUOUS,
    CONF_HIGH,
    CONF_LOW,
    CONF_MEDIUM,
    CONF_UNMATCHED,
    is_generic_name,
    match_functions,
    summarize_matching_for_poll,
)

STATUS_IDENTICAL = "IDENTISCH"
STATUS_CHANGED = "STRUKTURELL_VERAENDERT"
STATUS_ADDED = "HINZUGEFUEGT"
STATUS_REMOVED = "ENTFERNT"
STATUS_UNCOMPARABLE = "NICHT_VERGLEICHBAR"


def compare_function_analyses(
    subject: dict[str, Any] | None,
    reference: dict[str, Any] | None,
) -> dict[str, Any]:
    sub_fns = _fns(subject)
    ref_fns = _fns(reference)
    limitations = [
        "Funktionsdiff ist kein Manipulationsnachweis.",
        "Vergleich basiert auf multi-stage Function Matching (kein Diaphora/BinDiff).",
        "Absolute Adressen und generische FUN_*-Namen sind keine Identitätsmerkmale.",
    ]
    if subject is None or not subject.get("ok"):
        return _empty(
            STATUS_UNCOMPARABLE,
            "Subject-Funktionsexport fehlt oder ungültig.",
            limitations + ["Subject-Analyse fehlgeschlagen."],
        )
    if reference is None or not reference.get("ok"):
        return _empty(
            STATUS_UNCOMPARABLE,
            "Keine passende Referenz mit Funktionsexport.",
            limitations + ["Referenzfunktionsexport fehlt — kein Cross-Model-Zwang."],
            subject_count=len(sub_fns),
        )
    if not sub_fns and not ref_fns:
        return _empty(
            STATUS_UNCOMPARABLE,
            "Beide Funktionslisten leer.",
            limitations + ["Leere Funktionslisten."],
        )

    # Processor soft-check — incompatible arches → uncomparable
    sp = str((subject or {}).get("processor") or "")
    rp = str((reference or {}).get("processor") or "")
    if sp and rp and _arch_family(sp) != _arch_family(rp):
        return _empty(
            STATUS_UNCOMPARABLE,
            f"Inkompatible Prozessorarchitektur ({sp} vs {rp}).",
            limitations + ["Function Matching übersprungen — Architektur mismatch."],
            subject_count=len(sub_fns),
        )

    matching = match_functions(sub_fns, ref_fns)
    pairs: list[dict[str, Any]] = []
    identical = changed = added = removed = uncomparable = 0

    for m in matching.get("matches") or []:
        if not isinstance(m, dict):
            continue
        sub = m.get("subject")
        ref = m.get("reference")
        conf = m.get("matchConfidence")
        method = m.get("matchMethod")

        if sub and ref and conf in {CONF_HIGH, CONF_MEDIUM, CONF_LOW}:
            # Recover full function dicts for classification when possible
            s_full = _find_fn(sub_fns, sub) or sub
            r_full = _find_fn(ref_fns, ref) or ref
            status, detail = _classify_pair(s_full, r_full)
            if status == STATUS_IDENTICAL:
                identical += 1
            elif status == STATUS_CHANGED:
                changed += 1
            else:
                uncomparable += 1
            pairs.append(
                {
                    "status": status,
                    "subject": _brief(s_full),
                    "reference": _brief(r_full),
                    "matchMethod": method,
                    "matchConfidence": conf,
                    "similarityScore": m.get("similarityScore"),
                    "featuresUsed": m.get("featuresUsed") or [],
                    "differences": detail,
                    "evidenceTier": "statisch",
                    "notes": m.get("notes")
                    or "Struktureller Vergleich — keine Tuning-Aussage.",
                }
            )
        elif sub and not ref:
            if conf == CONF_AMBIGUOUS:
                pairs.append(
                    {
                        "status": STATUS_UNCOMPARABLE,
                        "subject": _brief(sub),
                        "reference": None,
                        "matchMethod": method,
                        "matchConfidence": conf,
                        "similarityScore": m.get("similarityScore"),
                        "featuresUsed": m.get("featuresUsed") or [],
                        "candidates": m.get("candidates") or [],
                        "differences": {"reason": "ambiguous-match"},
                        "evidenceTier": "statisch",
                        "notes": m.get("notes")
                        or "Mehrdeutige Kandidaten — keine willkürliche Zuordnung.",
                    }
                )
                uncomparable += 1
            else:
                pairs.append(
                    {
                        "status": STATUS_ADDED,
                        "subject": _brief(sub),
                        "reference": None,
                        "matchMethod": method,
                        "matchConfidence": conf or CONF_UNMATCHED,
                        "similarityScore": m.get("similarityScore"),
                        "featuresUsed": m.get("featuresUsed") or [],
                        "evidenceTier": "statisch",
                        "notes": m.get("notes") or "Nur im Subject vorhanden.",
                    }
                )
                added += 1
        elif ref and not sub:
            pairs.append(
                {
                    "status": STATUS_REMOVED,
                    "subject": None,
                    "reference": _brief(ref),
                    "matchMethod": None,
                    "matchConfidence": CONF_UNMATCHED,
                    "evidenceTier": "statisch",
                    "notes": "Nur in Referenz vorhanden.",
                }
            )
            removed += 1

    matching_summary = matching.get("summary") or {}
    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "ghidra-function-export-diff",
        "toolNote": (
            "Phase-2.2C multi-stage matcher (fingerprint/structural/neighborhood). "
            "Diaphora/BinDiff nicht integriert."
        ),
        "summary": {
            "identical": identical,
            "structurallyChanged": changed,
            "added": added,
            "removed": removed,
            "uncomparable": uncomparable,
            "subjectFunctionCount": len(sub_fns),
            "referenceFunctionCount": len(ref_fns),
            "matched": matching_summary.get("matched", identical + changed),
            "ambiguous": matching_summary.get("ambiguous", 0),
            "matchHigh": matching_summary.get("high", 0),
            "matchMedium": matching_summary.get("medium", 0),
            "matchLow": matching_summary.get("low", 0),
            "overall": (
                STATUS_UNCOMPARABLE
                if uncomparable and not (identical or changed or added or removed)
                else STATUS_CHANGED
                if changed or added or removed or uncomparable
                else STATUS_IDENTICAL
                if identical
                else STATUS_UNCOMPARABLE
            ),
        },
        "pairs": pairs,
        "functionMatching": summarize_matching_for_poll(matching),
        "analysisLimitations": limitations + list(matching.get("analysisLimitations") or []),
        "notes": list(matching.get("notes") or [])
        + [
            f"functionDiff=ok identical={identical} changed={changed} "
            f"added={added} removed={removed} ambiguous={matching_summary.get('ambiguous', 0)}"
        ],
    }


def summarize_diff_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    pairs = full.get("pairs") or []
    # Prefer non-identical samples for UI.
    interesting = [p for p in pairs if isinstance(p, dict) and p.get("status") != STATUS_IDENTICAL]
    sample = (interesting or pairs)[:40]
    out = {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "tool": full.get("tool"),
        "toolNote": full.get("toolNote"),
        "summary": full.get("summary") or {},
        "samplePairs": sample,
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "notes": list(full.get("notes") or []),
    }
    # Compact matching summary for poll (full matches stay on artifact endpoint).
    fm = full.get("functionMatching")
    if isinstance(fm, dict):
        out["functionMatching"] = {
            "ok": fm.get("ok"),
            "summary": fm.get("summary"),
            "tool": fm.get("tool"),
            "toolNote": fm.get("toolNote"),
            "analysisLimitations": fm.get("analysisLimitations"),
            "sampleMatches": (fm.get("sampleMatches") or [])[:20],
        }
    return out


def _fns(blob: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not blob:
        return []
    raw = blob.get("functions") or []
    return [f for f in raw if isinstance(f, dict)]


def _find_fn(fns: list[dict[str, Any]], brief: dict[str, Any]) -> dict[str, Any] | None:
    addr = brief.get("address")
    name = brief.get("name")
    fp = brief.get("fingerprint")
    for f in fns:
        if addr and f.get("address") == addr:
            return f
        if fp and f.get("fingerprint") == fp and f.get("name") == name:
            return f
    return None


def _classify_pair(a: dict[str, Any], b: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    detail: dict[str, Any] = {}
    same_fp = (a.get("fingerprint") or "") == (b.get("fingerprint") or "") and bool(a.get("fingerprint"))
    same_size = a.get("size") == b.get("size")
    same_blocks = a.get("basicBlocks") == b.get("basicBlocks")
    same_edges = a.get("cfgEdges") == b.get("cfgEdges")
    same_calls = sorted(a.get("calls") or []) == sorted(b.get("calls") or [])
    if same_fp and same_size and same_blocks:
        # Body-identical: still note call-name set diffs as transitive dependency hints
        # without flipping IDENTISCH (callee body may differ independently).
        if not same_calls:
            detail["dependencyNote"] = "callNamesDiffer; body fingerprint identical"
            detail["callsChanged"] = True
        return STATUS_IDENTICAL, {"reason": "fingerprint+size+blocks", **detail}
    if a.get("size") is None or b.get("size") is None:
        return STATUS_UNCOMPARABLE, {"reason": "missing-size"}
    if not same_size:
        detail["size"] = {"subject": a.get("size"), "reference": b.get("size")}
    if not same_blocks:
        detail["basicBlocks"] = {"subject": a.get("basicBlocks"), "reference": b.get("basicBlocks")}
    if not same_edges:
        detail["cfgEdges"] = {"subject": a.get("cfgEdges"), "reference": b.get("cfgEdges")}
    if not same_calls:
        detail["callsChanged"] = True
    if a.get("fingerprint") != b.get("fingerprint"):
        detail["fingerprintChanged"] = True
    # Soft rename: generic vs reliable names
    if is_generic_name(str(a.get("name") or "")) or is_generic_name(str(b.get("name") or "")):
        detail["genericName"] = True
    return STATUS_CHANGED, detail


def _brief(f: dict[str, Any]) -> dict[str, Any]:
    return {
        "address": f.get("address"),
        "name": f.get("name"),
        "size": f.get("size"),
        "basicBlocks": f.get("basicBlocks"),
        "cfgEdges": f.get("cfgEdges"),
        "fingerprint": f.get("fingerprint"),
        "confidence": f.get("confidence"),
    }


def _arch_family(processor: str) -> str:
    p = processor.lower()
    if "arm" in p or "cortex" in p or "thumb" in p:
        return "arm"
    if "mips" in p:
        return "mips"
    if "x86" in p or "x86-64" in p:
        return "x86"
    return p.split(":")[0] if p else "unknown"


def _empty(status: str, note: str, limitations: list[str], subject_count: int = 0) -> dict[str, Any]:
    return {
        "ok": status != STATUS_UNCOMPARABLE or subject_count > 0,
        "schemaVersion": 1,
        "tool": "ghidra-function-export-diff",
        "toolNote": "Phase-2.2C multi-stage matcher — Diaphora/BinDiff nicht integriert.",
        "summary": {
            "identical": 0,
            "structurallyChanged": 0,
            "added": 0,
            "removed": 0,
            "uncomparable": subject_count if status == STATUS_UNCOMPARABLE else 0,
            "subjectFunctionCount": subject_count,
            "referenceFunctionCount": 0,
            "matched": 0,
            "ambiguous": 0,
            "matchHigh": 0,
            "matchMedium": 0,
            "matchLow": 0,
            "overall": status,
        },
        "pairs": [],
        "functionMatching": {
            "ok": False,
            "summary": {},
            "sampleMatches": [],
            "analysisLimitations": limitations,
            "notes": [note],
        },
        "analysisLimitations": limitations,
        "notes": [note],
    }
