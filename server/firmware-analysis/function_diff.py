"""Function-level firmware comparison from Ghidra exports (Phase 2).

Diaphora / BinDiff are not integrated here:
- BinDiff: proprietary Hex-Rays tooling, not redistributable for this stack.
- Diaphora: GPL Ghidra plugin, heavy install/RAM, awkward headless automation on a 4 GB VPS.

This module compares ExportFunctionAnalysis inventories only. Structural change ≠ manipulation.
"""
from __future__ import annotations

from typing import Any

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
        "Vergleich basiert auf Ghidra-Export-Fingerprints (kein Diaphora/BinDiff).",
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

    ref_by_name = {str(f.get("name") or ""): f for f in ref_fns if f.get("name")}
    ref_by_fp = {}
    for f in ref_fns:
        fp = f.get("fingerprint")
        if fp:
            ref_by_fp.setdefault(str(fp), []).append(f)

    used_ref: set[int] = set()
    pairs: list[dict[str, Any]] = []
    identical = changed = added = removed = uncomparable = 0

    for s in sub_fns:
        match, how = _match(s, ref_by_name, ref_by_fp, used_ref)
        if match is None:
            pairs.append(
                {
                    "status": STATUS_ADDED,
                    "subject": _brief(s),
                    "reference": None,
                    "matchMethod": None,
                    "evidenceTier": "statisch",
                    "notes": "Nur im Subject vorhanden.",
                }
            )
            added += 1
            continue
        used_ref.add(id(match))
        status, detail = _classify_pair(s, match)
        if status == STATUS_IDENTICAL:
            identical += 1
        elif status == STATUS_CHANGED:
            changed += 1
        else:
            uncomparable += 1
        pairs.append(
            {
                "status": status,
                "subject": _brief(s),
                "reference": _brief(match),
                "matchMethod": how,
                "differences": detail,
                "evidenceTier": "statisch",
                "notes": "Struktureller Vergleich — keine Tuning-Aussage.",
            }
        )

    for r in ref_fns:
        if id(r) in used_ref:
            continue
        pairs.append(
            {
                "status": STATUS_REMOVED,
                "subject": None,
                "reference": _brief(r),
                "matchMethod": None,
                "evidenceTier": "statisch",
                "notes": "Nur in Referenz vorhanden.",
            }
        )
        removed += 1

    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "ghidra-function-export-diff",
        "toolNote": "Diaphora/BinDiff nicht integriert — begrenzter Fingerprint-/CFG-Vergleich.",
        "summary": {
            "identical": identical,
            "structurallyChanged": changed,
            "added": added,
            "removed": removed,
            "uncomparable": uncomparable,
            "subjectFunctionCount": len(sub_fns),
            "referenceFunctionCount": len(ref_fns),
        },
        "pairs": pairs,
        "analysisLimitations": limitations,
        "notes": [
            f"functionDiff=ok identical={identical} changed={changed} "
            f"added={added} removed={removed}"
        ],
    }


def summarize_diff_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    pairs = full.get("pairs") or []
    # Prefer non-identical samples for UI.
    interesting = [p for p in pairs if isinstance(p, dict) and p.get("status") != STATUS_IDENTICAL]
    sample = (interesting or pairs)[:40]
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "tool": full.get("tool"),
        "toolNote": full.get("toolNote"),
        "summary": full.get("summary") or {},
        "samplePairs": sample,
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "notes": list(full.get("notes") or []),
    }


def _fns(blob: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not blob:
        return []
    raw = blob.get("functions") or []
    return [f for f in raw if isinstance(f, dict)]


def _match(
    subject: dict[str, Any],
    by_name: dict[str, dict[str, Any]],
    by_fp: dict[str, list[dict[str, Any]]],
    used: set[int],
) -> tuple[dict[str, Any] | None, str | None]:
    name = str(subject.get("name") or "")
    if name and name in by_name and id(by_name[name]) not in used:
        return by_name[name], "name"
    fp = subject.get("fingerprint")
    if fp and str(fp) in by_fp:
        for cand in by_fp[str(fp)]:
            if id(cand) not in used:
                return cand, "fingerprint"
    return None, None


def _classify_pair(a: dict[str, Any], b: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    detail: dict[str, Any] = {}
    same_fp = (a.get("fingerprint") or "") == (b.get("fingerprint") or "") and bool(a.get("fingerprint"))
    same_size = a.get("size") == b.get("size")
    same_blocks = a.get("basicBlocks") == b.get("basicBlocks")
    same_edges = a.get("cfgEdges") == b.get("cfgEdges")
    same_calls = sorted(a.get("calls") or []) == sorted(b.get("calls") or [])
    if same_fp and same_size and same_blocks:
        return STATUS_IDENTICAL, {"reason": "fingerprint+size+blocks"}
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


def _empty(status: str, note: str, limitations: list[str], subject_count: int = 0) -> dict[str, Any]:
    return {
        "ok": status != STATUS_UNCOMPARABLE or subject_count > 0,
        "schemaVersion": 1,
        "tool": "ghidra-function-export-diff",
        "toolNote": "Diaphora/BinDiff nicht integriert.",
        "summary": {
            "identical": 0,
            "structurallyChanged": 0,
            "added": 0,
            "removed": 0,
            "uncomparable": subject_count if status == STATUS_UNCOMPARABLE else 0,
            "subjectFunctionCount": subject_count,
            "referenceFunctionCount": 0,
            "overall": status,
        },
        "pairs": [],
        "analysisLimitations": limitations,
        "notes": [note],
    }
