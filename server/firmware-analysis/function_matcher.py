"""Multi-stage intelligent function matching (Phase 2.2C / 2.2E).

Matches Ghidra ExportFunctionAnalysis inventories across firmware versions
without relying on absolute addresses or generic FUN_* names.

Stages:
  1. Exact normalized fingerprint (unique 1:1)
  2. Structural CFG / size / mnemonic similarity (size-bucket prefilter)
  3. Call-neighborhood propagation from already matched pairs
  4. Ambiguity detection (identical helpers → AMBIGUOUS, no forced pick)

Phase 2.2E: size/BB prefiltering avoids uncontrolled O(n·m) pairwise scans.
The 2500-function soft cap remains; overflow is truncated=true (incomplete).

Confidence: HIGH | MEDIUM | LOW | AMBIGUOUS | UNMATCHED
"""
from __future__ import annotations

import re
from collections import defaultdict
from typing import Any

CONF_HIGH = "HIGH"
CONF_MEDIUM = "MEDIUM"
CONF_LOW = "LOW"
CONF_AMBIGUOUS = "AMBIGUOUS"
CONF_UNMATCHED = "UNMATCHED"

# Structural score thresholds (0..1)
_STRUCT_HIGH = 0.92
_STRUCT_MEDIUM = 0.78
_STRUCT_LOW = 0.62
_AMBIGUITY_GAP = 0.05  # if top-2 scores within this → AMBIGUOUS
_SIZE_BUCKET = 16  # bytes — index granularity for candidate prefilter
_SIZE_TOLERANCE = 0.35  # ±35% size window
_BB_TOLERANCE = 3  # ± basic-block window when both known
_MAX_CANDIDATES = 64  # hard cap per subject after prefilter

_GENERIC_NAME_RE = re.compile(
    r"^(FUN_|SUB_|LAB_|DAT_|unk_|thunk_|FID_conflict_|s_|caseD_)",
    re.IGNORECASE,
)
_ADDR_NAME_RE = re.compile(r"^FUN_[0-9a-fA-F]{4,}$")


def is_generic_name(name: str | None) -> bool:
    n = (name or "").strip()
    if not n:
        return True
    if _GENERIC_NAME_RE.match(n) or _ADDR_NAME_RE.match(n):
        return True
    # Ghidra sometimes emits bare hex entry names
    if re.fullmatch(r"[0-9a-fA-F]{6,}", n):
        return True
    return False


def match_functions(
    subject_fns: list[dict[str, Any]],
    reference_fns: list[dict[str, Any]],
    *,
    max_functions: int = 2500,
) -> dict[str, Any]:
    """Return match artifacts with pairs + confidence stats."""
    truncated = len(subject_fns) > max_functions or len(reference_fns) > max_functions
    sub = list(subject_fns)[:max_functions]
    ref = list(reference_fns)[:max_functions]
    used_ref: set[int] = set()
    matches: list[dict[str, Any]] = []

    # Index reference
    ref_by_fp: dict[str, list[dict[str, Any]]] = {}
    ref_by_name: dict[str, list[dict[str, Any]]] = {}
    for r in ref:
        fp = str(r.get("fingerprint") or "")
        if fp:
            ref_by_fp.setdefault(fp, []).append(r)
        name = str(r.get("name") or "")
        if name and not is_generic_name(name):
            ref_by_name.setdefault(name, []).append(r)

    # --- Stage 1: unique exact fingerprint ---
    pending_sub: list[dict[str, Any]] = []
    for s in sub:
        fp = str(s.get("fingerprint") or "")
        cands = [c for c in ref_by_fp.get(fp, []) if id(c) not in used_ref] if fp else []
        if len(cands) == 1:
            r = cands[0]
            used_ref.add(id(r))
            matches.append(
                _pair(
                    s,
                    r,
                    confidence=CONF_HIGH,
                    method="fingerprint_exact",
                    score=1.0,
                    features=["fingerprint", "size", "basicBlocks"],
                )
            )
        elif len(cands) > 1:
            # Identical helpers — do not arbitrarily assign
            matches.append(
                _pair(
                    s,
                    None,
                    confidence=CONF_AMBIGUOUS,
                    method="fingerprint_ambiguous",
                    score=1.0,
                    features=["fingerprint"],
                    notes=f"Ambiguous fingerprint shared by {len(cands)} reference functions.",
                    candidates=[_id_brief(c) for c in cands[:8]],
                )
            )
        else:
            pending_sub.append(s)

    # --- Stage 1b: reliable non-generic name (only if unused) ---
    still: list[dict[str, Any]] = []
    for s in pending_sub:
        name = str(s.get("name") or "")
        if name and not is_generic_name(name):
            cands = [c for c in ref_by_name.get(name, []) if id(c) not in used_ref]
            if len(cands) == 1:
                r = cands[0]
                used_ref.add(id(r))
                score = structural_similarity(s, r)
                conf = CONF_HIGH if score >= _STRUCT_MEDIUM else CONF_MEDIUM
                matches.append(
                    _pair(
                        s,
                        r,
                        confidence=conf,
                        method="name_reliable",
                        score=max(score, 0.85),
                        features=["name", "size", "basicBlocks", "cfgEdges"],
                    )
                )
                continue
            if len(cands) > 1:
                matches.append(
                    _pair(
                        s,
                        None,
                        confidence=CONF_AMBIGUOUS,
                        method="name_ambiguous",
                        score=0.0,
                        features=["name"],
                        notes=f"Ambiguous reliable name '{name}'.",
                        candidates=[_id_brief(c) for c in cands[:8]],
                    )
                )
                continue
        still.append(s)
    pending_sub = still

    # --- Stage 2: structural similarity (size/BB prefiltered — avoid O(n·m)) ---
    available_ref = [r for r in ref if id(r) not in used_ref]
    size_index = _build_size_index(available_ref)
    still = []
    for s in pending_sub:
        candidates = _prefilter_candidates(s, available_ref, size_index, used_ref)
        scored: list[tuple[float, dict[str, Any]]] = [
            (structural_similarity(s, r), r) for r in candidates
        ]
        scored.sort(key=lambda t: t[0], reverse=True)
        if not scored or scored[0][0] < _STRUCT_LOW:
            still.append(s)
            continue
        best_score, best = scored[0]
        second = scored[1][0] if len(scored) > 1 else 0.0
        if len(scored) > 1 and (best_score - second) < _AMBIGUITY_GAP and second >= _STRUCT_LOW:
            matches.append(
                _pair(
                    s,
                    None,
                    confidence=CONF_AMBIGUOUS,
                    method="structural_ambiguous",
                    score=best_score,
                    features=["size", "basicBlocks", "cfgEdges", "mnemonics", "callCount"],
                    notes="Top structural candidates too close — left unmatched.",
                    candidates=[_id_brief(scored[0][1]), _id_brief(scored[1][1])],
                )
            )
            continue
        conf = (
            CONF_HIGH
            if best_score >= _STRUCT_HIGH
            else CONF_MEDIUM
            if best_score >= _STRUCT_MEDIUM
            else CONF_LOW
        )
        used_ref.add(id(best))
        matches.append(
            _pair(
                s,
                best,
                confidence=conf,
                method="structural",
                score=best_score,
                features=["size", "basicBlocks", "cfgEdges", "mnemonics", "callCount", "constants"],
            )
        )
    pending_sub = still

    # --- Stage 3: call-neighborhood using already matched pairs ---
    name_map_sub_to_ref = {}
    for m in matches:
        if m.get("reference") and m.get("subject") and m.get("confidence") in {
            CONF_HIGH,
            CONF_MEDIUM,
        }:
            sn = str((m["subject"] or {}).get("name") or "")
            rn = str((m["reference"] or {}).get("name") or "")
            if sn and rn:
                name_map_sub_to_ref[sn] = rn

    still = []
    available_ref = [r for r in ref if id(r) not in used_ref]
    size_index = _build_size_index(available_ref)
    for s in pending_sub:
        best: tuple[float, dict[str, Any]] | None = None
        second_score = 0.0
        for r in _prefilter_candidates(s, available_ref, size_index, used_ref):
            nb = neighborhood_score(s, r, name_map_sub_to_ref)
            base = structural_similarity(s, r)
            score = 0.55 * base + 0.45 * nb
            if best is None or score > best[0]:
                if best is not None:
                    second_score = best[0]
                best = (score, r)
            elif score > second_score:
                second_score = score
        if best is None or best[0] < _STRUCT_LOW:
            still.append(s)
            continue
        best_score, best_r = best
        if (best_score - second_score) < _AMBIGUITY_GAP and second_score >= _STRUCT_LOW:
            matches.append(
                _pair(
                    s,
                    None,
                    confidence=CONF_AMBIGUOUS,
                    method="neighborhood_ambiguous",
                    score=best_score,
                    features=["calls", "calledBy", "structural"],
                    notes="Neighborhood candidates ambiguous.",
                )
            )
            continue
        conf = CONF_MEDIUM if best_score >= _STRUCT_MEDIUM else CONF_LOW
        used_ref.add(id(best_r))
        matches.append(
            _pair(
                s,
                best_r,
                confidence=conf,
                method="call_neighborhood",
                score=best_score,
                features=["calls", "calledBy", "structural"],
            )
        )
        sn = str(s.get("name") or "")
        rn = str(best_r.get("name") or "")
        if sn and rn:
            name_map_sub_to_ref[sn] = rn
    pending_sub = still

    # Unmatched subjects
    for s in pending_sub:
        matches.append(
            _pair(
                s,
                None,
                confidence=CONF_UNMATCHED,
                method=None,
                score=0.0,
                features=[],
                notes="No reliable match under multi-stage criteria.",
            )
        )

    # Unmatched references
    for r in ref:
        if id(r) in used_ref:
            continue
        # skip refs already listed as ambiguous candidates only — still count removed
        matches.append(
            {
                "subject": None,
                "reference": _id_brief(r),
                "referenceFunctionId": _fid(r),
                "subjectFunctionId": None,
                "referenceAddress": r.get("address"),
                "subjectAddress": None,
                "similarityScore": 0.0,
                "matchConfidence": CONF_UNMATCHED,
                "matchMethod": None,
                "featuresUsed": [],
                "limitations": ["Nur in Referenz vorhanden."],
                "candidates": [],
                "notes": "Only in reference.",
            }
        )

    stats = _stats(matches)
    limitations = [
        "Matching is structural/heuristic — not a manipulation verdict.",
        "Identical helper functions with shared fingerprints stay AMBIGUOUS.",
        "Absolute addresses are not used as identity keys.",
        "Generic Ghidra FUN_* names are not treated as reliable identity.",
    ]
    notes = [
        f"functionMatching=ok matched={stats['matched']} ambiguous={stats['ambiguous']} "
        f"unmatched={stats['unmatched']} high={stats['high']} medium={stats['medium']} low={stats['low']}"
    ]
    if truncated:
        limitations.append(
            f"Matching unvollständig: Limit {max_functions} Funktionen "
            f"(subject={len(subject_fns)}, reference={len(reference_fns)})."
        )
        notes.append(
            f"functionMatching=truncated max={max_functions} "
            f"subject={len(subject_fns)} reference={len(reference_fns)}"
        )
    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "intelligent-function-matcher",
        "toolNote": (
            "Multi-stage match (fingerprint → structural → neighborhood). "
            "Generic FUN_* names ignored as identity. Addresses never used as identity."
        ),
        "matches": matches,
        "summary": {**stats, "truncated": truncated, "maxFunctions": max_functions},
        "analysisLimitations": limitations,
        "notes": notes,
    }


def _build_size_index(refs: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    idx: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for r in refs:
        sz = _num(r.get("size"))
        bucket = int(sz // _SIZE_BUCKET) if sz is not None else -1
        idx[bucket].append(r)
    return idx


def _prefilter_candidates(
    subject: dict[str, Any],
    available_ref: list[dict[str, Any]],
    size_index: dict[int, list[dict[str, Any]]],
    used_ref: set[int],
) -> list[dict[str, Any]]:
    """Restrict pairwise comparisons to size/BB-compatible refs."""
    sz = _num(subject.get("size"))
    bb = _num(subject.get("basicBlocks"))
    if sz is None or sz <= 0:
        # No size → capped scan of unused refs
        out = [r for r in available_ref if id(r) not in used_ref][:_MAX_CANDIDATES]
        return out

    lo = max(1.0, sz * (1.0 - _SIZE_TOLERANCE))
    hi = sz * (1.0 + _SIZE_TOLERANCE)
    b0 = int(lo // _SIZE_BUCKET)
    b1 = int(hi // _SIZE_BUCKET)
    cands: list[dict[str, Any]] = []
    for b in range(b0, b1 + 1):
        for r in size_index.get(b, []):
            if id(r) in used_ref:
                continue
            rsz = _num(r.get("size"))
            if rsz is None or not (lo <= rsz <= hi):
                continue
            rbb = _num(r.get("basicBlocks"))
            if bb is not None and rbb is not None and abs(bb - rbb) > _BB_TOLERANCE:
                continue
            cands.append(r)
            if len(cands) >= _MAX_CANDIDATES:
                return cands
    # Fallback: if prefilter empty, allow a small unfiltered sample (still capped)
    if not cands:
        cands = [r for r in available_ref if id(r) not in used_ref][: min(16, _MAX_CANDIDATES)]
    return cands


def structural_similarity(a: dict[str, Any], b: dict[str, Any]) -> float:
    """Weighted 0..1 structural score."""
    scores: list[tuple[float, float]] = []  # (weight, value)

    sa, sb = _num(a.get("size")), _num(b.get("size"))
    if sa is not None and sb is not None and max(sa, sb) > 0:
        scores.append((0.22, 1.0 - min(1.0, abs(sa - sb) / max(sa, sb))))

    ba, bb = _num(a.get("basicBlocks")), _num(b.get("basicBlocks"))
    if ba is not None and bb is not None and max(ba, bb) > 0:
        scores.append((0.18, 1.0 - min(1.0, abs(ba - bb) / max(ba, bb))))

    ea, eb = _num(a.get("cfgEdges")), _num(b.get("cfgEdges"))
    if ea is not None and eb is not None and max(ea, eb) > 0:
        scores.append((0.12, 1.0 - min(1.0, abs(ea - eb) / max(ea, eb))))

    ca, cb = len(a.get("calls") or []), len(b.get("calls") or [])
    if max(ca, cb) > 0:
        scores.append((0.10, 1.0 - min(1.0, abs(ca - cb) / max(ca, cb))))
    else:
        scores.append((0.05, 1.0))

    ma, mb = _norm_list(a.get("mnemonics")), _norm_list(b.get("mnemonics"))
    # Empty mnemonic lists are NOT evidence of equality (common in sparse fixtures).
    if not ma and not mb:
        scores.append((0.28, 0.0))
    else:
        scores.append((0.28, jaccard(ma, mb)))

    ca_set, cb_set = _norm_const(a.get("constants")), _norm_const(b.get("constants"))
    if not ca_set and not cb_set:
        scores.append((0.10, 0.0))
    else:
        scores.append((0.10, jaccard(ca_set, cb_set)))

    if a.get("fingerprint") and a.get("fingerprint") == b.get("fingerprint"):
        scores.append((0.20, 1.0))

    if not scores:
        return 0.0
    wsum = sum(w for w, _ in scores)
    score = sum(w * v for w, v in scores) / wsum if wsum else 0.0
    # Different fingerprints require stronger structural evidence.
    fa, fb = a.get("fingerprint"), b.get("fingerprint")
    if fa and fb and fa != fb:
        score *= 0.72
    return score


def neighborhood_score(
    subject: dict[str, Any],
    reference: dict[str, Any],
    sub_to_ref_names: dict[str, str],
) -> float:
    """Compare mapped call names / callers using already-matched name map."""
    def mapped(names: list[str]) -> set[str]:
        out: set[str] = set()
        for n in names:
            if is_generic_name(n):
                continue
            out.add(sub_to_ref_names.get(n, n))
        return out

    s_calls = mapped([str(x) for x in (subject.get("calls") or [])])
    r_calls = {str(x) for x in (reference.get("calls") or []) if not is_generic_name(str(x))}
    s_by = mapped([str(x) for x in (subject.get("calledBy") or [])])
    r_by = {str(x) for x in (reference.get("calledBy") or []) if not is_generic_name(str(x))}
    return 0.6 * jaccard(s_calls, r_calls) + 0.4 * jaccard(s_by, r_by)


def jaccard(a: set[str] | list[str], b: set[str] | list[str]) -> float:
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 1.0
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def summarize_matching_for_poll(full: dict[str, Any], *, max_samples: int = 40) -> dict[str, Any]:
    matches = [m for m in (full.get("matches") or []) if isinstance(m, dict)]
    interesting = [
        m
        for m in matches
        if m.get("matchConfidence") in {CONF_AMBIGUOUS, CONF_UNMATCHED, CONF_LOW}
        or (m.get("reference") and m.get("subject"))
    ]
    sample = (interesting or matches)[:max_samples]
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "tool": full.get("tool"),
        "toolNote": full.get("toolNote"),
        "summary": full.get("summary") or {},
        "sampleMatches": sample,
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "notes": list(full.get("notes") or []),
    }


# --- helpers ---


def _pair(
    subject: dict[str, Any] | None,
    reference: dict[str, Any] | None,
    *,
    confidence: str,
    method: str | None,
    score: float,
    features: list[str],
    notes: str = "",
    candidates: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    return {
        "subject": _id_brief(subject) if subject else None,
        "reference": _id_brief(reference) if reference else None,
        "subjectFunctionId": _fid(subject) if subject else None,
        "referenceFunctionId": _fid(reference) if reference else None,
        "subjectAddress": (subject or {}).get("address"),
        "referenceAddress": (reference or {}).get("address"),
        "similarityScore": round(float(score), 4),
        "matchConfidence": confidence,
        "matchMethod": method,
        "featuresUsed": features,
        "limitations": [
            "Structural/heuristic match — not proof of equivalence of runtime behavior."
        ],
        "candidates": candidates or [],
        "notes": notes,
    }


def _id_brief(f: dict[str, Any] | None) -> dict[str, Any] | None:
    if not f:
        return None
    return {
        "address": f.get("address"),
        "name": f.get("name"),
        "size": f.get("size"),
        "basicBlocks": f.get("basicBlocks"),
        "cfgEdges": f.get("cfgEdges"),
        "fingerprint": f.get("fingerprint"),
        "confidence": f.get("confidence"),
        "callCount": len(f.get("calls") or []),
    }


def _fid(f: dict[str, Any] | None) -> str | None:
    if not f:
        return None
    return f"{f.get('address')}|{f.get('name')}|{f.get('fingerprint')}"


def _num(v: Any) -> float | None:
    if v is None:
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def _norm_list(v: Any) -> set[str]:
    if not isinstance(v, list):
        return set()
    return {str(x).lower() for x in v if x is not None}


def _norm_const(v: Any) -> set[str]:
    """Drop code-looking immediates so address shifts do not dominate."""
    out: set[str] = set()
    if not isinstance(v, list):
        return out
    for x in v:
        s = str(x).lower()
        try:
            n = int(s, 0)
        except ValueError:
            out.add(s)
            continue
        # Skip flash/SRAM-looking pointers
        if 0x08000000 <= n < 0x08200000 or 0x20000000 <= n < 0x20100000:
            continue
        if n < 0x100:  # small immediates are useful
            out.add(hex(n))
    return out


def _stats(matches: list[dict[str, Any]]) -> dict[str, Any]:
    high = medium = low = ambiguous = unmatched = matched = 0
    for m in matches:
        conf = m.get("matchConfidence")
        has_both = m.get("subject") is not None and m.get("reference") is not None
        if conf == CONF_HIGH and has_both:
            high += 1
            matched += 1
        elif conf == CONF_MEDIUM and has_both:
            medium += 1
            matched += 1
        elif conf == CONF_LOW and has_both:
            low += 1
            matched += 1
        elif conf == CONF_AMBIGUOUS:
            ambiguous += 1
        elif m.get("subject") is not None and m.get("reference") is None:
            unmatched += 1
        elif m.get("subject") is None and m.get("reference") is not None:
            unmatched += 1
    return {
        "matched": matched,
        "high": high,
        "medium": medium,
        "low": low,
        "ambiguous": ambiguous,
        "unmatched": unmatched,
        "pairCount": len(matches),
    }
