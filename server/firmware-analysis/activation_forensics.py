"""Phase 2.3 — Activation Forensics (hidden input mechanism detection).

Builds on existing Ghidra exports, Input Behavior, Function Matching/Diff,
Callgraph, and FSM analysis. Documents *technical code properties* only.

Hard rules
----------
* Never invent function meanings or vehicle behavior claims.
* Never reconstruct or emit usable activation / unlock sequences.
* Never brute-force or auto-test real vehicles.
* STATIC_CONFIRMED = concrete static code property observed — NOT a vehicle proof.
* Community references must not be labeled as OEM-verified.
* High analysis priority is NOT a manipulation proof.
"""
from __future__ import annotations

import time
from typing import Any

from function_matcher import is_generic_name
from input_behavior import (
    EVIDENCE_CONFIRMED,
    EVIDENCE_INDICATIVE,
    EVIDENCE_SPECULATIVE,
    EVIDENCE_UNKNOWN,
    analyze_input_behavior,
    analyze_state_machines,
    classify_input_function,
    diff_input_behavior,
)

SCHEMA_VERSION = 1
PHASE = "2.3"
MAX_FUNCTIONS = 2500
MAX_HANDLERS = 100
MAX_CONDITIONAL = 80
MAX_UNDOCUMENTED = 60
MAX_GRAPH_NODES = 200
MAX_GRAPH_EDGES = 400
MAX_PRIORITY = 80
ANALYSIS_TIMEOUT_SEC = float(__import__("os").environ.get("ACTIVATION_FORENSICS_TIMEOUT_SEC", "45") or "45")

# Forensic evidence tiers (API-facing; map from input_behavior tiers).
STATIC_CONFIRMED = "STATIC_CONFIRMED"
INDICATIVE = "INDICATIVE"
SPECULATIVE = "SPECULATIVE"
UNKNOWN = "UNKNOWN"

# Input categories (technical; not vehicle claims).
INPUT_CATEGORIES = (
    "button_input",
    "gpio_input",
    "indicator_input",
    "hazard_indicator_input",
    "ble_input",
    "uart_input",
    "event_queue",
    "input_callback",
    "state_update",
    "conditional_feature_gate",
)

# Map legacy input_behavior categories → Phase 2.3 categories.
_LEGACY_CAT_MAP: dict[str, str] = {
    "button_or_key": "button_input",
    "gpio_event": "gpio_input",
    "ble_message": "ble_input",
    "uart_or_comm": "uart_input",
    "event_queue": "event_queue",
    "state_update": "state_update",
    "input_callback": "input_callback",
}

# Extra name/string hints for indicator / hazard / feature-gate (supplementary only).
_EXTRA_NAME_HINTS: dict[str, tuple[str, ...]] = {
    "indicator_input": ("indicator", "blinker", "turn_sig", "turnsig", "direction_lamp", "dir_lamp"),
    "hazard_indicator_input": ("hazard", "warnblink", "warn_blink", "haz_lamp", "emergency_flasher"),
    "conditional_feature_gate": ("feature_gate", "feat_en", "unlock_chk", "gate_check", "enable_if"),
}

_EXTRA_STRING_HINTS: dict[str, tuple[str, ...]] = {
    "indicator_input": ("indicator", "blinker", "turn"),
    "hazard_indicator_input": ("hazard", "warnblink", "hazard"),
    "conditional_feature_gate": ("feature", "gate", "enable"),
}

# Branch / compare mnemonics for conditional logic (Thumb/ARM common).
_BRANCH_MNEMONICS = frozenset(
    {
        "b",
        "beq",
        "bne",
        "blt",
        "bgt",
        "ble",
        "bge",
        "bcs",
        "bcc",
        "bmi",
        "bpl",
        "bvs",
        "bvc",
        "bhi",
        "bls",
        "cbz",
        "cbnz",
        "tbb",
        "tbh",
        "it",
        "ite",
        "itt",
        "itee",
        "itet",
        "itte",
        "itti",
    }
)
_COMPARE_MNEMONICS = frozenset({"cmp", "cmn", "tst", "teq"})
_STORE_MNEMONICS = frozenset({"str", "strb", "strh", "strd", "stm", "push"})

# Graph relation kinds.
REL_CALLS = "CALLS"
REL_REFERENCES = "REFERENCES"
REL_PROCESSES_INPUT = "PROCESSES_INPUT"
REL_UPDATES_STATE = "UPDATES_STATE"
REL_STRUCTURALLY_DIFFERS = "STRUCTURALLY_DIFFERS_FROM"
REL_BELONGS_TO_GROUP = "BELONGS_TO_FUNCTION_GROUP"

BASE_LIMITATIONS = [
    "Activation Forensics ist eine statische Codeanalyse — kein Nachweis realen Fahrzeugverhaltens.",
    "Keine Rekonstruktion oder Ausgabe von Aktivierungs-/Umgehungssequenzen.",
    "Funktionsnamen und Strings sind nur ergänzende Hinweise; generische Namen (FUN_*) sind üblich.",
    "Nicht jede undokumentierte Funktion ist eine Tuningfunktion; nicht jede Änderung ist Manipulation.",
    "Hohe Analysepriorität ist kein Manipulationsnachweis.",
    "Community-Referenzen sind keine verifizierte Herstellerfirmware.",
]


def _map_tier(legacy: str | None) -> str:
    t = (legacy or "").strip().lower()
    if t in (EVIDENCE_CONFIRMED, "confirmed", "confirmed_static"):
        return STATIC_CONFIRMED
    if t == EVIDENCE_INDICATIVE or t == "indicative":
        return INDICATIVE
    if t == EVIDENCE_SPECULATIVE or t == "speculative":
        return SPECULATIVE
    return UNKNOWN


def _fns(export: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not isinstance(export, dict):
        return []
    raw = export.get("functions")
    if not isinstance(raw, list):
        return []
    return [f for f in raw if isinstance(f, dict)]


def _addr(f: dict[str, Any]) -> str:
    return str(f.get("address") or f.get("entry") or "").strip()


def _name(f: dict[str, Any]) -> str:
    return str(f.get("name") or "").strip()


def _mnemonics(f: dict[str, Any]) -> list[str]:
    raw = f.get("mnemonics") or []
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for m in raw:
        if isinstance(m, str):
            out.append(m.lower().split()[0] if m else "")
        elif isinstance(m, dict):
            out.append(str(m.get("mnemonic") or m.get("op") or "").lower())
    return [x for x in out if x]


def _strings_lower(f: dict[str, Any]) -> list[str]:
    raw = f.get("strings") or []
    if not isinstance(raw, list):
        return []
    return [str(s).lower() for s in raw if s is not None]


def _extra_categories(f: dict[str, Any]) -> list[tuple[str, str, str]]:
    """Return list of (category, method, evidence_note)."""
    hits: list[tuple[str, str, str]] = []
    name_l = _name(f).lower()
    strs = _strings_lower(f)
    for cat, needles in _EXTRA_NAME_HINTS.items():
        for n in needles:
            if n in name_l:
                hits.append((cat, "name_hint", f"name contains '{n}'"))
                break
    for cat, needles in _EXTRA_STRING_HINTS.items():
        for n in needles:
            if any(n in s for s in strs):
                hits.append((cat, "string_hint", f"string contains '{n}'"))
                break
    return hits


def _conditional_features(f: dict[str, Any]) -> dict[str, Any]:
    mnems = _mnemonics(f)
    branches = sum(1 for m in mnems if m in _BRANCH_MNEMONICS)
    compares = sum(1 for m in mnems if m in _COMPARE_MNEMONICS)
    stores = sum(1 for m in mnems if m in _STORE_MNEMONICS)
    bb = int(f.get("basicBlocks") or 0)
    edges = int(f.get("cfgEdges") or 0)
    # Prefer explicit mnemonic counts; fall back to CFG density.
    branch_count = branches or int(f.get("branchMnemonicCount") or 0)
    return {
        "compareOps": compares,
        "conditionalBranches": branch_count,
        "storeOps": stores,
        "basicBlocks": bb,
        "cfgEdges": edges,
        "hasConditionalLogic": bool(compares >= 1 and (branch_count >= 1 or edges >= bb >= 2)),
        "hasStateStorePattern": bool(stores >= 1 and (compares >= 1 or branch_count >= 1)),
    }


def _map_categories(legacy_cats: list[str], extras: list[str]) -> list[str]:
    out: list[str] = []
    for c in legacy_cats:
        mapped = _LEGACY_CAT_MAP.get(c, c)
        if mapped in INPUT_CATEGORIES and mapped not in out:
            out.append(mapped)
    for c in extras:
        if c in INPUT_CATEGORIES and c not in out:
            out.append(c)
    return out


def classify_activation_handler(f: dict[str, Any]) -> dict[str, Any] | None:
    """Classify one Ghidra function export into an input-handler finding."""
    scored = classify_input_function(f)
    extras = _extra_categories(f)
    cond = _conditional_features(f)

    categories: list[str] = []
    methods: list[str] = []
    evidence: list[str] = []
    legacy_tier = None
    score = 0.0

    if scored:
        categories = _map_categories(list(scored.get("categories") or []), [])
        methods.append("input_behavior_classify")
        evidence.extend(list(scored.get("evidence") or [])[:8])
        legacy_tier = scored.get("evidenceTier")
        score = float(scored.get("score") or 0)

    for cat, method, note in extras:
        if cat not in categories:
            categories.append(cat)
        methods.append(method)
        evidence.append(note)
        score += 0.35 if method == "name_hint" else 0.25
        if legacy_tier is None:
            legacy_tier = EVIDENCE_INDICATIVE

    # Conditional feature gate from CFG without name/string (weaker).
    if cond["hasConditionalLogic"] and cond["hasStateStorePattern"] and not categories:
        # Alone: speculative conditional gate candidate — not enough for a handler.
        pass
    elif cond["hasConditionalLogic"] and categories:
        if "conditional_feature_gate" not in categories and (
            "state_update" in categories or "input_callback" in categories or "event_queue" in categories
        ):
            categories.append("conditional_feature_gate")
            methods.append("conditional_cfg")
            evidence.append(
                f"conditionalBranches={cond['conditionalBranches']} compares={cond['compareOps']} stores={cond['storeOps']}"
            )
            score += 0.2

    if not categories:
        return None

    # Elevate only when concrete structural properties exist.
    tier = _map_tier(legacy_tier)
    if cond["hasConditionalLogic"] and any(
        c in categories for c in ("button_input", "gpio_input", "ble_input", "uart_input", "event_queue")
    ):
        if tier == SPECULATIVE:
            tier = INDICATIVE
        evidence.append("conditional_logic_co_located_with_input_category")
    if scored and scored.get("evidenceTier") in (EVIDENCE_CONFIRMED, "confirmed", "confirmed_static"):
        tier = STATIC_CONFIRMED

    # Name-only extras without structural support stay speculative.
    if not scored and all(m in ("name_hint", "string_hint") for m in methods):
        if tier == STATIC_CONFIRMED:
            tier = INDICATIVE
        if not cond["hasConditionalLogic"]:
            tier = SPECULATIVE

    return {
        "functionId": _addr(f) or _name(f) or "unknown",
        "address": _addr(f) or None,
        "name": _name(f) or None,
        "genericName": is_generic_name(_name(f)),
        "inputCategories": categories,
        "detectionMethods": sorted(set(methods)),
        "technicalFindings": evidence[:12],
        "confidence": round(min(score, 5.0), 3),
        "evidenceTier": tier,
        "conditionalLogic": cond,
        "basicBlocks": int(f.get("basicBlocks") or 0),
        "cfgEdges": int(f.get("cfgEdges") or 0),
        "fingerprint": f.get("fingerprint"),
        "limitations": [
            "STATIC_CONFIRMED bezieht sich auf Codeeigenschaften, nicht auf Fahrzeugverhalten.",
        ],
    }


def detect_undocumented_logic(
    subject_fns: list[dict[str, Any]],
    *,
    function_diff: dict[str, Any] | None = None,
    input_handlers: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Flag undocumented / unmatched / structurally changed input-related logic."""
    limitations = [
        "Nicht jede undokumentierte Funktion ist eine Tuningfunktion.",
        "Nicht jede strukturelle Änderung ist eine Manipulation.",
        "Nicht jede bedingte Verzweigung ist eine Aktivierungsbedingung.",
    ]
    findings: list[dict[str, Any]] = []
    handler_addrs = {
        str(h.get("address") or "") for h in (input_handlers or []) if h.get("address")
    }

    generic_count = sum(1 for f in subject_fns if is_generic_name(_name(f)))
    findings.append(
        {
            "kind": "generic_named_functions",
            "count": generic_count,
            "evidenceTier": INDICATIVE if generic_count else UNKNOWN,
            "technicalFindings": [f"genericNameCount={generic_count}"],
            "note": "Generische Namen (FUN_*) sind bei Ghidra-Exporten normal.",
        }
    )

    pairs = list((function_diff or {}).get("pairs") or []) if isinstance(function_diff, dict) else []
    added = [p for p in pairs if str(p.get("status") or "") in ("HINZUGEFUEGT", "ADDED", "added")]
    changed = [
        p
        for p in pairs
        if str(p.get("status") or "") in ("STRUKTURELL_VERAENDERT", "STRUCTURALLY_CHANGED", "changed")
    ]
    unmatched = [
        p
        for p in pairs
        if str(p.get("status") or "") in ("NICHT_VERGLEICHBAR", "UNMATCHED", "ambiguous")
    ]

    for p in (added + changed)[:MAX_UNDOCUMENTED]:
        addr = str(
            (p.get("subject") or {}).get("address")
            if isinstance(p.get("subject"), dict)
            else p.get("subjectAddress")
            or p.get("address")
            or ""
        )
        status = str(p.get("status") or "")
        is_input = addr in handler_addrs
        findings.append(
            {
                "kind": "structurally_changed_input" if is_input and "VERAENDERT" in status.upper()
                else ("added_function" if "HINZU" in status.upper() or status.lower() == "added" else "structural_change"),
                "address": addr or None,
                "name": (
                    (p.get("subject") or {}).get("name")
                    if isinstance(p.get("subject"), dict)
                    else p.get("subjectName") or p.get("name")
                ),
                "diffStatus": status,
                "inputRelated": is_input,
                "evidenceTier": INDICATIVE if is_input else SPECULATIVE,
                "technicalFindings": [
                    f"functionDiff.status={status}",
                    f"inputRelated={is_input}",
                ],
                "matchingConfidence": p.get("confidence") or p.get("matchConfidence"),
                "limitations": limitations[:2],
            }
        )

    return {
        "ok": True,
        "summary": {
            "genericNamedFunctions": generic_count,
            "addedVsReference": len(added),
            "structurallyChanged": len(changed),
            "notReliablyMatched": len(unmatched),
            "inputRelatedChanges": sum(1 for x in findings if x.get("inputRelated")),
            "findingCount": len(findings),
        },
        "findings": findings[:MAX_UNDOCUMENTED],
        "evidenceTier": INDICATIVE if (added or changed) else SPECULATIVE,
        "analysisLimitations": limitations,
    }


def analyze_conditional_logic(
    subject_fns: list[dict[str, Any]],
    *,
    input_handlers: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Document conditional / state-dependent control flow (no sequence reconstruction)."""
    handler_by_addr = {
        str(h.get("address") or ""): h for h in (input_handlers or []) if h.get("address")
    }
    findings: list[dict[str, Any]] = []
    for f in subject_fns[:MAX_FUNCTIONS]:
        cond = _conditional_features(f)
        if not cond["hasConditionalLogic"]:
            continue
        addr = _addr(f)
        linked = handler_by_addr.get(addr)
        cats = list(linked.get("inputCategories") or []) if linked else []
        tier = INDICATIVE if linked else SPECULATIVE
        if cond["compareOps"] >= 1 and cond["conditionalBranches"] >= 1:
            if linked and linked.get("evidenceTier") == STATIC_CONFIRMED:
                tier = STATIC_CONFIRMED
        findings.append(
            {
                "functionId": addr or _name(f) or "unknown",
                "address": addr or None,
                "name": _name(f) or None,
                "inputCategories": cats,
                "compareOps": cond["compareOps"],
                "conditionalBranches": cond["conditionalBranches"],
                "storeOps": cond["storeOps"],
                "stateUpdatePattern": cond["hasStateStorePattern"],
                "basicBlocks": cond["basicBlocks"],
                "cfgEdges": cond["cfgEdges"],
                "evidenceTier": tier,
                "technicalFindings": [
                    f"compares={cond['compareOps']}",
                    f"branches={cond['conditionalBranches']}",
                    f"stores={cond['storeOps']}",
                ],
                "limitations": [
                    "Kontrollflussmerkmale belegen keine Aktivierungsbedingung am Fahrzeug.",
                    "Keine Rekonstruktion von Eingabesequenzen.",
                ],
            }
        )
    findings.sort(
        key=lambda x: (
            0 if x.get("inputCategories") else 1,
            -int(x.get("conditionalBranches") or 0),
            -int(x.get("compareOps") or 0),
        )
    )
    findings = findings[:MAX_CONDITIONAL]
    return {
        "ok": True,
        "summary": {
            "functionsWithConditionalLogic": len(findings),
            "inputLinked": sum(1 for x in findings if x.get("inputCategories")),
            "stateStorePatterns": sum(1 for x in findings if x.get("stateUpdatePattern")),
        },
        "findings": findings,
        "evidenceTier": INDICATIVE if findings else UNKNOWN,
        "analysisLimitations": [
            "Bedingte Verzweigungen allein sind keine Aktivierungslogik.",
            "Keine Ausgabe von Vergleichswerten als Umgehungsanleitung.",
        ],
    }


def build_evidence_graph(
    *,
    handlers: list[dict[str, Any]],
    conditional: dict[str, Any] | None,
    undocumented: dict[str, Any] | None,
    state_machines: dict[str, Any] | None,
    function_diff: dict[str, Any] | None,
) -> dict[str, Any]:
    """Compact evidence graph — technical relationships only."""
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    seen_nodes: set[str] = set()

    def add_node(nid: str, ntype: str, **meta: Any) -> None:
        if nid in seen_nodes or len(nodes) >= MAX_GRAPH_NODES:
            return
        seen_nodes.add(nid)
        nodes.append({"id": nid, "type": ntype, **meta})

    def add_edge(src: str, dst: str, kind: str, *, evidence: str, confirmed: bool) -> None:
        if len(edges) >= MAX_GRAPH_EDGES:
            return
        if src not in seen_nodes or dst not in seen_nodes:
            return
        edges.append(
            {
                "from": src,
                "to": dst,
                "relation": kind,
                "technicalFinding": evidence,
                "confirmed": confirmed,
                "evidenceTier": STATIC_CONFIRMED if confirmed else INDICATIVE,
            }
        )

    for h in handlers[:MAX_HANDLERS]:
        addr = str(h.get("address") or h.get("functionId") or "")
        if not addr:
            continue
        nid = f"fn:{addr}"
        add_node(
            nid,
            "firmware_function",
            address=addr,
            name=h.get("name"),
            evidenceTier=h.get("evidenceTier"),
        )
        for cat in h.get("inputCategories") or []:
            cid = f"cat:{cat}"
            add_node(cid, "input_category", category=cat)
            add_edge(
                nid,
                cid,
                REL_PROCESSES_INPUT,
                evidence="; ".join((h.get("technicalFindings") or [])[:3]) or "category_classified",
                confirmed=h.get("evidenceTier") == STATIC_CONFIRMED,
            )
        cond = h.get("conditionalLogic") or {}
        if cond.get("hasStateStorePattern"):
            sid = f"state:{addr}"
            add_node(sid, "state_variable_candidate", address=addr, verified=False)
            add_edge(
                nid,
                sid,
                REL_UPDATES_STATE,
                evidence=f"stores={cond.get('storeOps')} compares={cond.get('compareOps')}",
                confirmed=False,
            )

    for sm in list((state_machines or {}).get("sampleStateMachines") or [])[:20]:
        addr = str(sm.get("functionAddress") or sm.get("address") or "")
        if not addr:
            continue
        smid = f"fsm:{addr}"
        add_node(
            smid,
            "state_machine_candidate",
            address=addr,
            analysisQuality=sm.get("analysisQuality"),
            stateCount=sm.get("stateCount"),  # may be null — do not invent
            evidenceTier=sm.get("analysisQuality") or SPECULATIVE,
        )
        fnid = f"fn:{addr}"
        if fnid not in seen_nodes:
            add_node(fnid, "firmware_function", address=addr, name=sm.get("functionName"))
        add_edge(
            fnid,
            smid,
            REL_BELONGS_TO_GROUP,
            evidence="fsm_candidate_from_static_structure",
            confirmed=False,
        )

    for p in list((function_diff or {}).get("pairs") or [])[:40]:
        status = str(p.get("status") or "")
        if "VERAENDERT" not in status.upper() and "CHANGED" not in status.upper():
            continue
        sub = p.get("subject") if isinstance(p.get("subject"), dict) else {}
        ref = p.get("reference") if isinstance(p.get("reference"), dict) else {}
        saddr = str(sub.get("address") or p.get("subjectAddress") or "")
        raddr = str(ref.get("address") or p.get("referenceAddress") or "")
        if not saddr or not raddr:
            continue
        sn, rn = f"fn:{saddr}", f"ref:{raddr}"
        add_node(sn, "firmware_function", address=saddr, name=sub.get("name") or p.get("subjectName"))
        add_node(
            rn,
            "reference_function",
            address=raddr,
            name=ref.get("name") or p.get("referenceName"),
        )
        add_edge(
            sn,
            rn,
            REL_STRUCTURALLY_DIFFERS,
            evidence=f"functionDiff={status}",
            confirmed=True,
        )

    return {
        "ok": True,
        "schemaVersion": SCHEMA_VERSION,
        "nodeCount": len(nodes),
        "edgeCount": len(edges),
        "nodes": nodes,
        "edges": edges,
        "analysisLimitations": [
            "Graph dokumentiert technische Zusammenhänge, keine Umgehungssequenzen.",
            "Unbestätigte Kanten sind als confirmed=false markiert.",
        ],
    }


def prioritize_functions(
    handlers: list[dict[str, Any]],
    *,
    conditional: dict[str, Any] | None = None,
    undocumented: dict[str, Any] | None = None,
    matching: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Rank forensic attention — priority ≠ manipulation proof."""
    cond_addrs = {
        str(x.get("address") or "")
        for x in list((conditional or {}).get("findings") or [])
        if x.get("address")
    }
    undoc_addrs = {
        str(x.get("address") or "")
        for x in list((undocumented or {}).get("findings") or [])
        if x.get("address") and x.get("inputRelated")
    }
    ranked: list[dict[str, Any]] = []
    for h in handlers:
        addr = str(h.get("address") or "")
        score = float(h.get("confidence") or 0)
        reasons: list[str] = []
        if h.get("evidenceTier") == STATIC_CONFIRMED:
            score += 2.0
            reasons.append("static_confirmed_code_property")
        elif h.get("evidenceTier") == INDICATIVE:
            score += 1.0
            reasons.append("indicative_input_handler")
        if addr in cond_addrs:
            score += 0.8
            reasons.append("conditional_logic")
        if addr in undoc_addrs:
            score += 1.2
            reasons.append("input_related_diff_vs_reference")
        if h.get("genericName"):
            reasons.append("generic_name_name_independent_analysis")
        ranked.append(
            {
                "address": addr or None,
                "name": h.get("name"),
                "priorityScore": round(score, 3),
                "inputCategories": h.get("inputCategories"),
                "evidenceTier": h.get("evidenceTier"),
                "reasons": reasons,
                "note": "Hohe Priorität ist kein Manipulationsnachweis.",
            }
        )
    ranked.sort(key=lambda x: -float(x.get("priorityScore") or 0))
    return {
        "ok": True,
        "prioritizedFunctions": ranked[:MAX_PRIORITY],
        "matchingSummary": (matching or {}).get("summary") if isinstance(matching, dict) else None,
        "analysisLimitations": [
            "Priorisierung steuert Analyseaufwand — keine automatisierte Umgehungssuche.",
        ],
    }


def integrate_fsm(
    state_machine_analysis: dict[str, Any] | None,
    handlers: list[dict[str, Any]],
    *,
    runtime_validation: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Link input handlers ↔ FSM candidates with existing evidence tiers."""
    sm = state_machine_analysis if isinstance(state_machine_analysis, dict) else {}
    samples = list(sm.get("sampleStateMachines") or sm.get("stateMachines") or [])
    handler_addrs = {str(h.get("address") or "") for h in handlers}
    links: list[dict[str, Any]] = []
    for s in samples[:24]:
        addr = str(s.get("functionAddress") or s.get("address") or "")
        quality = str(s.get("analysisQuality") or s.get("evidenceTier") or "STATIC_CANDIDATE")
        # Map FSM qualities; never invent state counts.
        state_count = s.get("stateCount")
        if state_count is None:
            state_count = s.get("estimatedStates") if s.get("stateCountVerified") else None
        links.append(
            {
                "functionAddress": addr or None,
                "functionName": s.get("functionName") or s.get("name"),
                "linkedToInputHandler": addr in handler_addrs,
                "fsmEvidenceTier": quality,
                "stateCount": state_count,  # null when unknown
                "transitionCount": s.get("transitionCount")
                if s.get("transitionCountVerified")
                else None,
                "stateCountVerified": bool(s.get("stateCountVerified")),
                "dynamicRuntimeVerified": bool(
                    (runtime_validation or {}).get("dynamicRuntimeVerified")
                )
                if addr and (runtime_validation or {}).get("dynamicRuntimeVerified")
                else False,
                "technicalFindings": list(s.get("evidence") or [])[:6],
                "limitations": [
                    "Zustandszahlen bleiben null, wenn nicht verifiziert.",
                    "Runtime-Evidenz nur aus kontrollierten Testprogrammen.",
                ],
            }
        )
    return {
        "ok": True,
        "fsmCandidateCount": len(links),
        "inputLinkedFsmCount": sum(1 for x in links if x.get("linkedToInputHandler")),
        "candidates": links,
        "runtimeValidationPresent": bool(runtime_validation),
        "evidenceTier": sm.get("evidenceTier") or "STATIC_CANDIDATE",
        "analysisLimitations": list(sm.get("analysisLimitations") or [])
        + ["FSM-Integration erfindet keine Zustandszahlen aus Basic-Block-Anzahlen."],
    }


def compare_with_reference(
    *,
    subject_sha256: str | None,
    reference_sha256: str | None,
    analysis_profile: dict[str, Any] | None,
    profile_compat: tuple[bool, str, list[str]] | list[Any] | None,
    reference_trust: str | None,
    function_diff: dict[str, Any] | None,
    input_diff: dict[str, Any] | None,
    handlers: list[dict[str, Any]],
) -> dict[str, Any]:
    """Original vs subject comparison focused on input-related functions."""
    trust = (reference_trust or "unknown").strip()
    oem = "oem" in trust.lower() or "manufacturer" in trust.lower() or "verified" in trust.lower()
    community = "community" in trust.lower()
    compat_ok = False
    compat_status = "UNKNOWN"
    compat_reasons: list[str] = []
    if isinstance(profile_compat, (tuple, list)) and len(profile_compat) >= 2:
        compat_ok = bool(profile_compat[0])
        compat_status = str(profile_compat[1])
        if len(profile_compat) >= 3 and isinstance(profile_compat[2], list):
            compat_reasons = [str(x) for x in profile_compat[2]]

    fd_summary = (function_diff or {}).get("summary") if isinstance(function_diff, dict) else {}
    ib_summary = (input_diff or {}).get("summary") if isinstance(input_diff, dict) else {}
    changed_input = []
    for p in list((input_diff or {}).get("pairs") or [])[:40]:
        changed_input.append(
            {
                "subjectAddress": p.get("subjectAddress")
                or (p.get("subject") or {}).get("address")
                if isinstance(p.get("subject"), dict)
                else p.get("address"),
                "referenceAddress": p.get("referenceAddress")
                or (p.get("reference") or {}).get("address")
                if isinstance(p.get("reference"), dict)
                else None,
                "status": p.get("status"),
                "matchingConfidence": p.get("confidence") or p.get("matchConfidence"),
                "technicalRationale": p.get("note") or p.get("reason") or p.get("status"),
            }
        )

    return {
        "ok": True,
        "subjectSHA256": subject_sha256,
        "referenceSHA256": reference_sha256,
        "analysisProfileVersion": (analysis_profile or {}).get("analysisProfileVersion"),
        "analysisProfileHash": (analysis_profile or {}).get("analysisProfileHash"),
        "profileCompatibility": {
            "ok": compat_ok,
            "status": compat_status,
            "reasons": compat_reasons,
        },
        "referenceTrust": trust,
        "referenceIsCommunity": community,
        "referenceIsOemVerified": bool(oem and not community),
        "trustDisclaimer": (
            "Community-Referenz — keine verifizierte Herstellerfirmware."
            if community
            else (
                "Referenzvertrauen wie geliefert; keine automatische Aufwertung."
                if not oem
                else "Referenz als herstellerbezogen markiert — unabhängig prüfen."
            )
        ),
        "functionDiffSummary": fd_summary,
        "inputBehaviorDiffSummary": ib_summary,
        "inputHandlerCount": len(handlers),
        "changedOrAddedInputRelated": changed_input,
        "analysisLimitations": [
            "Vergleich setzt Profilkompatibilität voraus; inkompatible Kataloge werden nicht stillschweigend verglichen.",
            "Unterschiede belegen keine Manipulation am Fahrzeug.",
        ],
    }


def summarize_activation_forensics_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    """Compact poll payload — full detail via artifact download."""
    if not isinstance(full, dict):
        return {"ok": False}
    summary = full.get("summary") or {}
    handlers = list(full.get("inputHandlerFindings") or [])[:12]
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", SCHEMA_VERSION),
        "phase": PHASE,
        "summary": {
            "functionsExamined": summary.get("functionsExamined"),
            "inputHandlerCount": summary.get("inputHandlerCount"),
            "categories": summary.get("categories"),
            "undocumentedFindingCount": summary.get("undocumentedFindingCount"),
            "conditionalLogicCount": summary.get("conditionalLogicCount"),
            "fsmLinkedCount": summary.get("fsmLinkedCount"),
            "graphNodeCount": summary.get("graphNodeCount"),
            "graphEdgeCount": summary.get("graphEdgeCount"),
            "elapsedSec": summary.get("elapsedSec"),
        },
        "categoryCounts": full.get("categoryCounts"),
        "sampleInputHandlers": [
            {
                "address": h.get("address"),
                "name": h.get("name"),
                "inputCategories": h.get("inputCategories"),
                "evidenceTier": h.get("evidenceTier"),
                "confidence": h.get("confidence"),
            }
            for h in handlers
        ],
        "undocumentedLogic": {
            "summary": (full.get("undocumentedLogic") or {}).get("summary"),
            "evidenceTier": (full.get("undocumentedLogic") or {}).get("evidenceTier"),
        },
        "conditionalLogicFindings": {
            "summary": (full.get("conditionalLogicFindings") or {}).get("summary"),
        },
        "fsmIntegration": {
            "fsmCandidateCount": (full.get("fsmIntegration") or {}).get("fsmCandidateCount"),
            "inputLinkedFsmCount": (full.get("fsmIntegration") or {}).get("inputLinkedFsmCount"),
        },
        "activationEvidenceGraph": {
            "nodeCount": (full.get("activationEvidenceGraph") or {}).get("nodeCount"),
            "edgeCount": (full.get("activationEvidenceGraph") or {}).get("edgeCount"),
        },
        "referenceComparison": {
            "referenceTrust": (full.get("referenceComparison") or {}).get("referenceTrust"),
            "referenceIsCommunity": (full.get("referenceComparison") or {}).get(
                "referenceIsCommunity"
            ),
            "profileCompatibility": (full.get("referenceComparison") or {}).get(
                "profileCompatibility"
            ),
        },
        "prioritization": {
            "top": list((full.get("prioritization") or {}).get("prioritizedFunctions") or [])[:8],
        },
        "evidenceTier": full.get("evidenceTier"),
        "analysisLimitations": full.get("analysisLimitations"),
        "notes": full.get("notes"),
    }


def run_activation_forensics(
    function_analysis: dict[str, Any] | None,
    *,
    call_graph: dict[str, Any] | None = None,
    function_diff: dict[str, Any] | None = None,
    input_behavior: dict[str, Any] | None = None,
    input_behavior_diff: dict[str, Any] | None = None,
    analysis_profile: dict[str, Any] | None = None,
    profile_compat: Any = None,
    subject_sha256: str | None = None,
    reference_sha256: str | None = None,
    reference_trust: str | None = None,
    runtime_validation: dict[str, Any] | None = None,
    deadline_sec: float | None = None,
) -> dict[str, Any]:
    """Main Phase 2.3 entry — reuses existing analyses when provided."""
    t0 = time.monotonic()
    limit = deadline_sec if deadline_sec is not None else ANALYSIS_TIMEOUT_SEC
    limitations = list(BASE_LIMITATIONS)
    notes: list[str] = [f"phase={PHASE}"]

    if not function_analysis or not function_analysis.get("ok"):
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "phase": PHASE,
            "inputHandlerFindings": [],
            "undocumentedLogic": {"ok": False, "findings": []},
            "conditionalLogicFindings": {"ok": False, "findings": []},
            "activationEvidenceGraph": {"ok": False, "nodes": [], "edges": []},
            "analysisLimitations": limitations + ["Funktionsexport fehlt/ungültig."],
            "notes": notes + ["activationForensics=missing_export"],
            "evidenceTier": UNKNOWN,
        }

    subject_fns = _fns(function_analysis)
    # Reuse or compute input behavior.
    ib = input_behavior if isinstance(input_behavior, dict) and input_behavior.get("ok") else None
    if ib is None:
        ib = analyze_input_behavior(function_analysis, call_graph=call_graph)

    handlers: list[dict[str, Any]] = []
    for f in subject_fns[:MAX_FUNCTIONS]:
        if time.monotonic() - t0 > limit:
            notes.append("activationForensics=timeout_partial")
            limitations.append("Analyse vorzeitig beendet (Timeout) — Teilergebnis.")
            break
        h = classify_activation_handler(f)
        if h:
            handlers.append(h)
    handlers.sort(
        key=lambda x: (
            {"STATIC_CONFIRMED": 0, "INDICATIVE": 1, "SPECULATIVE": 2, "UNKNOWN": 3}.get(
                str(x.get("evidenceTier")), 9
            ),
            -float(x.get("confidence") or 0),
        )
    )
    handlers = handlers[:MAX_HANDLERS]

    category_counts: dict[str, int] = {c: 0 for c in INPUT_CATEGORIES}
    for h in handlers:
        for c in h.get("inputCategories") or []:
            category_counts[c] = category_counts.get(c, 0) + 1

    undoc = detect_undocumented_logic(
        subject_fns, function_diff=function_diff, input_handlers=handlers
    )
    cond = analyze_conditional_logic(subject_fns, input_handlers=handlers)
    sm_raw = ib.get("stateMachineAnalysis") if isinstance(ib, dict) else None
    # Ensure state machines exist even if IB skipped them.
    if not sm_raw or not sm_raw.get("ok"):
        sm_raw = analyze_state_machines(subject_fns, ib.get("inputFunctions") if ib else [])
    fsm = integrate_fsm(sm_raw, handlers, runtime_validation=runtime_validation)
    graph = build_evidence_graph(
        handlers=handlers,
        conditional=cond,
        undocumented=undoc,
        state_machines=sm_raw,
        function_diff=function_diff,
    )
    matching = (function_diff or {}).get("functionMatching") if isinstance(function_diff, dict) else None
    prio = prioritize_functions(
        handlers, conditional=cond, undocumented=undoc, matching=matching
    )
    ref_cmp = compare_with_reference(
        subject_sha256=subject_sha256,
        reference_sha256=reference_sha256,
        analysis_profile=analysis_profile,
        profile_compat=profile_compat,
        reference_trust=reference_trust,
        function_diff=function_diff,
        input_diff=input_behavior_diff,
        handlers=handlers,
    )

    # Overall tier
    tiers = [str(h.get("evidenceTier")) for h in handlers]
    if STATIC_CONFIRMED in tiers:
        overall = STATIC_CONFIRMED
    elif INDICATIVE in tiers:
        overall = INDICATIVE
    elif SPECULATIVE in tiers:
        overall = SPECULATIVE
    else:
        overall = UNKNOWN

    elapsed = round(time.monotonic() - t0, 3)
    for lim in list(ib.get("analysisLimitations") or [])[:4]:
        if lim not in limitations:
            limitations.append(lim)

    return {
        "ok": True,
        "schemaVersion": SCHEMA_VERSION,
        "phase": PHASE,
        "summary": {
            "functionsExamined": min(len(subject_fns), MAX_FUNCTIONS),
            "inputHandlerCount": len(handlers),
            "categories": {k: v for k, v in category_counts.items() if v},
            "undocumentedFindingCount": (undoc.get("summary") or {}).get("findingCount"),
            "conditionalLogicCount": (cond.get("summary") or {}).get(
                "functionsWithConditionalLogic"
            ),
            "fsmLinkedCount": fsm.get("inputLinkedFsmCount"),
            "graphNodeCount": graph.get("nodeCount"),
            "graphEdgeCount": graph.get("edgeCount"),
            "elapsedSec": elapsed,
        },
        "categoryCounts": category_counts,
        "inputHandlerFindings": handlers,
        "undocumentedLogic": undoc,
        "conditionalLogicFindings": cond,
        "fsmIntegration": fsm,
        "activationEvidenceGraph": graph,
        "prioritization": prio,
        "referenceComparison": ref_cmp,
        "evidenceTier": overall,
        "analysisLimitations": limitations,
        "notes": notes,
    }


# ---------------------------------------------------------------------------
# Ground-truth quality metrics (controlled fixtures only)
# ---------------------------------------------------------------------------


def evaluate_detection_quality(
    findings: list[dict[str, Any]],
    ground_truth: list[dict[str, Any]],
    *,
    category_key: str = "inputCategories",
) -> dict[str, Any]:
    """Compute TP/FP/FN/precision/recall for controlled fixtures.

    ground_truth items: {address|name, categories: [...], expectDetect: bool}
    Metrics MUST NOT be marketed as real-scooter accuracy.
    """
    gt_pos = [g for g in ground_truth if g.get("expectDetect", True)]
    gt_neg = [g for g in ground_truth if not g.get("expectDetect", True)]

    def _key(x: dict[str, Any]) -> str:
        return str(x.get("address") or x.get("name") or x.get("functionId") or "").lower()

    found_keys = {_key(f) for f in findings}
    tp = 0
    fn = 0
    ambiguous = 0
    for g in gt_pos:
        k = _key(g)
        if k in found_keys:
            tp += 1
            f = next((x for x in findings if _key(x) == k), {})
            if f.get("evidenceTier") in (SPECULATIVE, UNKNOWN):
                ambiguous += 1
        else:
            fn += 1
    fp = 0
    for g in gt_neg:
        if _key(g) in found_keys:
            fp += 1
    # Also count findings not in GT as FP when GT is exhaustive.
    gt_keys = {_key(g) for g in ground_truth}
    for f in findings:
        if _key(f) and _key(f) not in gt_keys:
            fp += 1

    precision = (tp / (tp + fp)) if (tp + fp) else None
    recall = (tp / (tp + fn)) if (tp + fn) else None
    return {
        "truePositives": tp,
        "falsePositives": fp,
        "falseNegatives": fn,
        "precision": round(precision, 4) if precision is not None else None,
        "recall": round(recall, 4) if recall is not None else None,
        "ambiguousFindings": ambiguous,
        "unknownFindings": sum(1 for f in findings if f.get("evidenceTier") == UNKNOWN),
        "disclaimer": (
            "Metriken gelten nur für kontrollierte Fixtures — "
            "nicht als Erkennungsgenauigkeit realer Scooter-Firmware."
        ),
    }
