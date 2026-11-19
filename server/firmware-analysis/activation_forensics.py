"""Phase 2.3 / 2.3.1 — Activation Forensics (hidden input mechanism detection).

Builds on Ghidra exports, Input Behavior, Function Matching/Diff, Callgraph,
FSM analysis, and Phase 2.3.1 semantic data-flow features.

Hard rules
----------
* Never invent function meanings or vehicle behavior claims.
* Never reconstruct or emit usable activation / unlock sequences.
* Never brute-force or auto-test real vehicles.
* STATIC_CONFIRMED = concrete static code property — NOT a vehicle proof.
* Community references must not be labeled as OEM-verified.
* High analysis priority is NOT a manipulation proof.
* Overall evidence must reflect the *distribution* of findings (Phase 2.3.1).
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

try:
    from semantic_dataflow import analyze_semantic_dataflow
except Exception:  # pragma: no cover
    analyze_semantic_dataflow = None  # type: ignore

SCHEMA_VERSION = 2
PHASE = "2.3.2"
MAX_FUNCTIONS = 2500
MAX_HANDLERS = 100
MAX_CONDITIONAL = 80
MAX_UNDOCUMENTED = 60
MAX_GRAPH_NODES = 200
MAX_GRAPH_EDGES = 400
MAX_PRIORITY = 80
ANALYSIS_TIMEOUT_SEC = float(__import__("os").environ.get("ACTIVATION_FORENSICS_TIMEOUT_SEC", "45") or "45")

STATIC_CONFIRMED = "STATIC_CONFIRMED"
INDICATIVE = "INDICATIVE"
SPECULATIVE = "SPECULATIVE"
UNKNOWN = "UNKNOWN"

# Conditional-logic quality classes (Phase 2.3.1)
CONDITIONAL_LOGIC_ONLY = "CONDITIONAL_LOGIC_ONLY"
INPUT_RELATED_CONDITIONAL_LOGIC = "INPUT_RELATED_CONDITIONAL_LOGIC"
STATE_RELATED_CONDITIONAL_LOGIC = "STATE_RELATED_CONDITIONAL_LOGIC"
FEATURE_GATE_CANDIDATE = "FEATURE_GATE_CANDIDATE"
NOT_CLASSIFIABLE = "NOT_CLASSIFIABLE"

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

_LEGACY_CAT_MAP: dict[str, str] = {
    "button_or_key": "button_input",
    "gpio_event": "gpio_input",
    "ble_message": "ble_input",
    "uart_or_comm": "uart_input",
    "event_queue": "event_queue",
    "state_update": "state_update",
    "input_callback": "input_callback",
}

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

_BRANCH_MNEMONICS = frozenset(
    {
        "b", "beq", "bne", "blt", "bgt", "ble", "bge", "bcs", "bcc", "bmi", "bpl",
        "bvs", "bvc", "bhi", "bls", "cbz", "cbnz", "tbb", "tbh",
        "it", "ite", "itt", "itee", "itet", "itte", "itti",
    }
)
_COMPARE_MNEMONICS = frozenset({"cmp", "cmn", "tst", "teq"})
_STORE_MNEMONICS = frozenset({"str", "strb", "strh", "strd", "stm", "push"})
_LOAD_MNEMONICS = frozenset({"ldr", "ldrb", "ldrh", "ldrd", "ldm", "pop"})

REL_CALLS = "CALLS"
REL_REFERENCES = "REFERENCES"
REL_PROCESSES_INPUT = "PROCESSES_INPUT"
REL_UPDATES_STATE = "UPDATES_STATE"
REL_STRUCTURALLY_DIFFERS = "STRUCTURALLY_DIFFERS_FROM"
REL_BELONGS_TO_GROUP = "BELONGS_TO_FUNCTION_GROUP"

PROVENANCE_GHIDRA = "GHIDRA_EXPORTED"
PROVENANCE_MNEMONIC = "MNEMONIC_DERIVED"
PROVENANCE_PARTIAL = "PARTIAL"
PROVENANCE_UNAVAILABLE = "NOT_AVAILABLE"

BASE_LIMITATIONS = [
    "Activation Forensics ist eine statische Codeanalyse — kein Nachweis realen Fahrzeugverhaltens.",
    "Keine Rekonstruktion oder Ausgabe von Aktivierungs-/Umgehungssequenzen.",
    "Funktionsnamen und Strings sind nur ergänzende Hinweise; generische Namen (FUN_*) sind üblich.",
    "Nicht jede undokumentierte Funktion ist eine Tuningfunktion; nicht jede Änderung ist Manipulation.",
    "Hohe Analysepriorität ist kein Manipulationsnachweis.",
    "Community-Referenzen sind keine verifizierte Herstellerfirmware.",
    "Gesamt-Evidenz spiegelt die Verteilung der Einzelfunde wider — ein starker Einzelfund bestätigt nicht alle Ergebnisse.",
]


def _result_limits(
    *,
    total_analyzed: int,
    total_candidates: int,
    returned: int,
    configured_limit: int,
    truncation_reason: str | None = None,
    analysis_complete: bool = True,
) -> dict[str, Any]:
    omitted = max(0, total_candidates - returned)
    return {
        "totalFunctionsAnalyzed": total_analyzed,
        "totalCandidatesDetected": total_candidates,
        "returnedCandidates": returned,
        "omittedCandidates": omitted,
        "resultTruncated": omitted > 0,
        "truncationReason": truncation_reason if omitted > 0 else None,
        "configuredLimit": configured_limit,
        "analysisComplete": analysis_complete,
    }


def _dataflow_provenance(dataflow_fn: dict[str, Any] | None) -> str:
    if not isinstance(dataflow_fn, dict):
        return PROVENANCE_UNAVAILABLE
    prov = str(dataflow_fn.get("provenance") or dataflow_fn.get("source") or "").upper()
    if prov in (PROVENANCE_GHIDRA, "DATAFLOW_EXPORT", "GHIDRA_EXPORTED"):
        return PROVENANCE_GHIDRA
    if prov in (PROVENANCE_MNEMONIC, "DERIVED", "MNEMONIC_DERIVED"):
        q = str(dataflow_fn.get("quality") or "").lower()
        return PROVENANCE_PARTIAL if q in ("partial", "missing") else PROVENANCE_MNEMONIC
    if prov == PROVENANCE_PARTIAL:
        return PROVENANCE_PARTIAL
    src = str(dataflow_fn.get("source") or "").lower()
    if src == "dataflow_export" and str(dataflow_fn.get("quality") or "").lower() == "ok":
        return PROVENANCE_GHIDRA
    if src in ("derived", "function_export"):
        q = str(dataflow_fn.get("quality") or "").lower()
        return PROVENANCE_PARTIAL if q != "ok" else PROVENANCE_MNEMONIC
    return PROVENANCE_UNAVAILABLE


def _map_tier(legacy: str | None) -> str:
    t = (legacy or "").strip().lower()
    if t in (EVIDENCE_CONFIRMED, "confirmed", "confirmed_static", "static_confirmed"):
        return STATIC_CONFIRMED
    if t in (EVIDENCE_INDICATIVE, "indicative"):
        return INDICATIVE
    if t in (EVIDENCE_SPECULATIVE, "speculative"):
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


def _mmio_hint(f: dict[str, Any]) -> bool:
    """STM32-ish peripheral window 0x40000000–0x5FFFFFFF in constants."""
    for c in f.get("constants") or []:
        s = str(c).lower().replace("0x", "")
        try:
            v = int(s, 16) if s else -1
        except ValueError:
            continue
        if 0x40000000 <= v <= 0x5FFFFFFF:
            return True
    return False


def _structural_signals(f: dict[str, Any], df: dict[str, Any] | None) -> dict[str, Any]:
    mnems = _mnemonics(f)
    compares = sum(1 for m in mnems if m in _COMPARE_MNEMONICS)
    branches = sum(1 for m in mnems if m in _BRANCH_MNEMONICS) or int(f.get("branchMnemonicCount") or 0)
    stores = sum(1 for m in mnems if any(m.startswith(p) for p in ("str", "stm", "push")))
    loads = sum(1 for m in mnems if any(m.startswith(p) for p in ("ldr", "ldm", "pop")))
    bb = int(f.get("basicBlocks") or 0)
    edges = int(f.get("cfgEdges") or 0)
    calls = len(f.get("calls") or [])
    called_by = len(f.get("calledBy") or [])

    if isinstance(df, dict):
        compares = max(compares, int(df.get("compareOps") or 0))
        branches = max(branches, int(df.get("conditionalBranches") or 0))
        stores = max(stores, int(df.get("memoryWrites") or 0))
        loads = max(loads, int(df.get("memoryReads") or 0))
        calls = max(calls, int(df.get("callCount") or 0))

    return {
        "compareOps": compares,
        "conditionalBranches": branches,
        "storeOps": stores,
        "loadOps": loads,
        "basicBlocks": bb,
        "cfgEdges": edges,
        "callCount": calls,
        "calledByCount": called_by,
        "hasConditionalLogic": bool(compares >= 1 and (branches >= 1 or (bb >= 2 and edges >= 2))),
        "hasStateStorePattern": bool(stores >= 1 and (compares >= 1 or branches >= 1)),
        "mmioHint": _mmio_hint(f),
        "parameterCount": (df or {}).get("parameterCount") if isinstance(df, dict) else f.get("parameterCount"),
    }


def _extra_categories(f: dict[str, Any]) -> list[tuple[str, str, str]]:
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


def _structural_input_strength(sig: dict[str, Any]) -> tuple[int, int, list[str]]:
    """Return (strong, weak, detail tags). Load+branch alone is not enough."""
    strong = 0
    weak = 0
    details: list[str] = []
    # ISR / callback-like fan-in with memory + conditional control flow.
    if sig["calledByCount"] >= 3 and sig["hasConditionalLogic"] and sig["loadOps"] >= 1:
        strong += 1
        details.append("fan_in_isr_like")
    # Peripheral MMIO window + at least one caller + conditional.
    if sig["mmioHint"] and sig["hasConditionalLogic"] and sig["calledByCount"] >= 1:
        strong += 1
        details.append("mmio_input_path")
    # Explicit parameter + compare/branch (signature-aware dataflow).
    if (sig.get("parameterCount") or 0) >= 1 and sig["compareOps"] >= 1 and sig["conditionalBranches"] >= 1:
        strong += 1
        details.append("parameter_gated")
    # Supporting (weak) structural co-signals — never sufficient alone.
    if (
        sig["loadOps"] >= 2
        and sig["storeOps"] >= 1
        and sig["compareOps"] >= 2
        and sig["hasConditionalLogic"]
    ):
        weak += 1
        details.append("load_store_conditional")
    if sig["calledByCount"] >= 2 and sig["hasStateStorePattern"] and sig["hasConditionalLogic"]:
        weak += 1
        details.append("callback_state_update")
    if sig["loadOps"] >= 1 and sig["hasConditionalLogic"]:
        weak += 1
        details.append("dataflow_load_conditional")
    return strong, weak, details


def _independent_feature_score(
    *,
    scored: dict[str, Any] | None,
    extras: list[tuple[str, str, str]],
    sig: dict[str, Any],
    generic: bool,
) -> tuple[float, list[str], list[str], bool]:
    """Weighted independent features. Name/string alone cannot yield STATIC_CONFIRMED."""
    score = 0.0
    methods: list[str] = []
    evidence: list[str] = []
    name_only = True

    if scored:
        methods.append("input_behavior_classify")
        evidence.extend(list(scored.get("evidence") or [])[:6])
        score += float(scored.get("score") or 0)
        name_only = False

    for _cat, method, note in extras:
        methods.append(method)
        evidence.append(note)
        # Cap name/string contribution.
        score += 0.25 if method == "name_hint" else 0.2

    strong, weak, details = _structural_input_strength(sig)
    if "dataflow_load_conditional" in details:
        score += 0.35
        methods.append("dataflow_load_conditional")
        evidence.append(
            f"loads={sig['loadOps']} compares={sig['compareOps']} branches={sig['conditionalBranches']}"
        )
        name_only = False
    if sig["hasStateStorePattern"]:
        score += 0.25
        methods.append("state_store_pattern")
        evidence.append(f"stores={sig['storeOps']}")
        name_only = False
    if "mmio_input_path" in details:
        score += 0.9
        methods.append("mmio_constant_hint")
        evidence.append("peripheral-window constant co-located with conditional logic + caller")
        name_only = False
    if "fan_in_isr_like" in details or sig["calledByCount"] >= 2:
        score += 0.45 if "fan_in_isr_like" in details else 0.2
        methods.append("callback_fan_in")
        evidence.append(f"calledBy={sig['calledByCount']}")
        name_only = False
    if "parameter_gated" in details:
        score += 0.7
        methods.append("parameter_conditional")
        evidence.append(f"parameterCount={sig.get('parameterCount')}")
        name_only = False
    # Dense branch-only without other signals: weak, do not classify as input alone.
    if sig["compareOps"] >= 3 and sig["conditionalBranches"] >= 4 and strong == 0 and weak <= 1:
        methods.append("dense_conditional_only")
        evidence.append("dense compares/branches without input-linkage signals")

    if generic:
        methods.append("generic_name")
        evidence.append("generic Ghidra name — classification must not rely on name alone")

    return score, sorted(set(methods)), evidence, name_only


def classify_activation_handler(
    f: dict[str, Any],
    *,
    dataflow_fn: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    scored = classify_input_function(f)
    extras = _extra_categories(f)
    sig = _structural_signals(f, dataflow_fn)
    generic = is_generic_name(_name(f))

    categories: list[str] = []
    if scored:
        categories = _map_categories(list(scored.get("categories") or []), [])
    for cat, _, _ in extras:
        if cat not in categories:
            categories.append(cat)

    score, methods, evidence, name_only = _independent_feature_score(
        scored=scored, extras=extras, sig=sig, generic=generic
    )

    # Name-independent structural input candidate (no category from names/strings/IB).
    structural_only = False
    if not categories:
        strong, weak, details = _structural_input_strength(sig)
        # Require ≥1 strong signal AND ≥1 additional co-signal; name-independent path needs MMIO or fan-in≥3.
        has_linkage = (
            "mmio_input_path" in details
            or "fan_in_isr_like" in details
            or sig.get("calledByCount", 0) >= 3
            or sig.get("mmioHint")
        )
        if strong >= 1 and (strong + weak) >= 2 and has_linkage:
            structural_only = True
            categories.append("input_callback")
            methods.append("structural_multi_signal")
            evidence.append(
                f"strongStructural={strong} weakStructural={weak} details={','.join(details)}"
            )
            score += 0.5
        else:
            # Do not promote load+branch / dense-branch noise to a handler.
            return None

    # Feature gate: never from branches alone; structural-only callback ≠ gate.
    gate_class = classify_conditional_quality(
        sig, categories, structural_only_callback=structural_only
    )
    if gate_class == FEATURE_GATE_CANDIDATE and not structural_only:
        if "conditional_feature_gate" not in categories:
            categories.append("conditional_feature_gate")
            methods.append("feature_gate_candidate")
            evidence.append("semantic input + state-related conditional + store pattern")
            score += 0.3
    elif "conditional_feature_gate" in categories and gate_class != FEATURE_GATE_CANDIDATE:
        # Downgrade name/string-only feature_gate without structural support.
        if gate_class in (CONDITIONAL_LOGIC_ONLY, NOT_CLASSIFIABLE, STATE_RELATED_CONDITIONAL_LOGIC) and not scored:
            if not any(m in methods for m in ("feature_gate_candidate", "input_behavior_classify")):
                categories = [c for c in categories if c != "conditional_feature_gate"]

    if not categories:
        return None

    # Evidence tier rules (2.3.1): name/string alone → SPECULATIVE; need multi-signal for INDICATIVE.
    legacy_tier = scored.get("evidenceTier") if scored else None
    tier = _map_tier(legacy_tier)
    independent = [m for m in methods if m not in ("name_hint", "string_hint", "generic_name")]
    df_prov = _dataflow_provenance(dataflow_fn)
    if structural_only:
        # Structural-only without Ghidra export / name-IB semantics: never INDICATIVE from mnemonics alone.
        strong, _weak, _d = _structural_input_strength(sig)
        ghidra_ok = df_prov == PROVENANCE_GHIDRA
        if ghidra_ok and strong >= 2 and not name_only:
            tier = INDICATIVE
        else:
            tier = SPECULATIVE
    elif name_only or (not independent and extras and not scored):
        tier = SPECULATIVE
    elif scored and scored.get("evidenceTier") in (EVIDENCE_CONFIRMED, "confirmed", "confirmed_static"):
        # Only keep STATIC_CONFIRMED if not solely name-driven OR has structural co-signal.
        if independent:
            tier = STATIC_CONFIRMED
        else:
            tier = INDICATIVE
    elif len(independent) >= 2 or (scored and independent):
        if tier in (UNKNOWN, SPECULATIVE):
            tier = INDICATIVE
    else:
        if tier == STATIC_CONFIRMED:
            tier = INDICATIVE
        if not scored and not independent:
            tier = SPECULATIVE

    # Dense conditional-only must not become handler without categories from stronger signals.
    if "dense_conditional_only" in methods and not scored and not extras and not structural_only:
        return None

    return {
        "functionId": _addr(f) or _name(f) or "unknown",
        "address": _addr(f) or None,
        "name": _name(f) or None,
        "genericName": generic,
        "inputCategories": categories,
        "detectionMethods": methods,
        "technicalFindings": evidence[:14],
        "confidence": round(min(score, 5.0), 3),
        "evidenceTier": tier,
        "weakCandidate": bool(structural_only and tier == SPECULATIVE),
        "structuralOnly": structural_only,
        "conditionalLogic": {
            "compareOps": sig["compareOps"],
            "conditionalBranches": sig["conditionalBranches"],
            "storeOps": sig["storeOps"],
            "loadOps": sig["loadOps"],
            "basicBlocks": sig["basicBlocks"],
            "cfgEdges": sig["cfgEdges"],
            "hasConditionalLogic": sig["hasConditionalLogic"],
            "hasStateStorePattern": sig["hasStateStorePattern"],
            "qualityClass": gate_class,
        },
        "featureWeights": {
            "structuralSignals": len(independent),
            "nameOrStringHints": sum(1 for m in methods if m in ("name_hint", "string_hint")),
            "mmioHint": sig["mmioHint"],
            "calledByCount": sig["calledByCount"],
            "structuralOnly": structural_only,
        },
        "basicBlocks": sig["basicBlocks"],
        "cfgEdges": sig["cfgEdges"],
        "fingerprint": f.get("fingerprint"),
        "dataflowProvenance": df_prov,
        "limitations": [
            "STATIC_CONFIRMED bezieht sich auf Codeeigenschaften, nicht auf Fahrzeugverhalten.",
            "Namen/Strings allein erzeugen keinen sicheren Nachweis.",
            "Strukturelle FUN_*-Kandidaten sind schwache Hinweise ohne semantische Namen/Strings.",
        ],
    }


def classify_conditional_quality(
    sig: dict[str, Any],
    categories: list[str],
    *,
    structural_only_callback: bool = False,
) -> str:
    """Phase 2.3.1 conditional classification — branches alone ≠ feature gate."""
    if not sig.get("hasConditionalLogic"):
        return NOT_CLASSIFIABLE
    semantic_input = any(
        c in categories
        for c in (
            "button_input",
            "gpio_input",
            "indicator_input",
            "hazard_indicator_input",
            "ble_input",
            "uart_input",
            "event_queue",
        )
    )
    callback_input = "input_callback" in categories and not structural_only_callback
    input_related = semantic_input or callback_input
    state_related = "state_update" in categories or bool(sig.get("hasStateStorePattern"))
    # Feature gate needs semantic/non-structural input linkage + state store + compares.
    if (
        semantic_input
        and state_related
        and sig.get("compareOps", 0) >= 1
        and sig.get("storeOps", 0) >= 1
    ):
        return FEATURE_GATE_CANDIDATE
    if (
        callback_input
        and state_related
        and sig.get("compareOps", 0) >= 2
        and sig.get("storeOps", 0) >= 1
        and not structural_only_callback
    ):
        return FEATURE_GATE_CANDIDATE
    if input_related or (structural_only_callback and "input_callback" in categories):
        return INPUT_RELATED_CONDITIONAL_LOGIC
    if state_related and sig.get("compareOps", 0) >= 1:
        return STATE_RELATED_CONDITIONAL_LOGIC
    return CONDITIONAL_LOGIC_ONLY


def detect_undocumented_logic(
    subject_fns: list[dict[str, Any]],
    *,
    function_diff: dict[str, Any] | None = None,
    input_handlers: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    limitations = [
        "Nicht jede undokumentierte Funktion ist eine Tuningfunktion.",
        "Nicht jede strukturelle Änderung ist eine Manipulation.",
        "Nicht jede bedingte Verzweigung ist eine Aktivierungsbedingung.",
    ]
    findings: list[dict[str, Any]] = []
    handler_addrs = {str(h.get("address") or "") for h in (input_handlers or []) if h.get("address")}
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
        p for p in pairs if str(p.get("status") or "") in ("STRUKTURELL_VERAENDERT", "STRUCTURALLY_CHANGED", "changed")
    ]
    unmatched = [
        p for p in pairs if str(p.get("status") or "") in ("NICHT_VERGLEICHBAR", "UNMATCHED", "ambiguous")
    ]
    for p in (added + changed)[:MAX_UNDOCUMENTED]:
        addr = str(
            (p.get("subject") or {}).get("address")
            if isinstance(p.get("subject"), dict)
            else p.get("subjectAddress") or p.get("address") or ""
        )
        status = str(p.get("status") or "")
        is_input = addr in handler_addrs
        findings.append(
            {
                "kind": (
                    "structurally_changed_input"
                    if is_input and "VERAENDERT" in status.upper()
                    else (
                        "added_function"
                        if "HINZU" in status.upper() or status.lower() == "added"
                        else "structural_change"
                    )
                ),
                "address": addr or None,
                "name": (
                    (p.get("subject") or {}).get("name")
                    if isinstance(p.get("subject"), dict)
                    else p.get("subjectName") or p.get("name")
                ),
                "diffStatus": status,
                "inputRelated": is_input,
                "evidenceTier": INDICATIVE if is_input else SPECULATIVE,
                "technicalFindings": [f"functionDiff.status={status}", f"inputRelated={is_input}"],
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
    dataflow_by_addr: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    handler_by_addr = {str(h.get("address") or ""): h for h in (input_handlers or []) if h.get("address")}
    findings_all: list[dict[str, Any]] = []
    class_counts = {
        CONDITIONAL_LOGIC_ONLY: 0,
        INPUT_RELATED_CONDITIONAL_LOGIC: 0,
        STATE_RELATED_CONDITIONAL_LOGIC: 0,
        FEATURE_GATE_CANDIDATE: 0,
        NOT_CLASSIFIABLE: 0,
    }
    for f in subject_fns[:MAX_FUNCTIONS]:
        addr = _addr(f)
        df = (dataflow_by_addr or {}).get(addr)
        sig = _structural_signals(f, df)
        if not sig["hasConditionalLogic"]:
            continue
        linked = handler_by_addr.get(addr)
        cats = list(linked.get("inputCategories") or []) if linked else []
        structural_only = bool(linked.get("structuralOnly")) if linked else False
        qclass = classify_conditional_quality(
            sig, cats, structural_only_callback=structural_only
        )
        class_counts[qclass] = class_counts.get(qclass, 0) + 1
        if qclass == FEATURE_GATE_CANDIDATE:
            tier = INDICATIVE
        elif qclass in (INPUT_RELATED_CONDITIONAL_LOGIC, STATE_RELATED_CONDITIONAL_LOGIC):
            tier = INDICATIVE if linked and not structural_only else SPECULATIVE
        else:
            tier = SPECULATIVE
        findings_all.append(
            {
                "functionId": addr or _name(f) or "unknown",
                "address": addr or None,
                "name": _name(f) or None,
                "inputCategories": cats,
                "qualityClass": qclass,
                "structuralOnly": structural_only,
                "compareOps": sig["compareOps"],
                "conditionalBranches": sig["conditionalBranches"],
                "storeOps": sig["storeOps"],
                "loadOps": sig["loadOps"],
                "stateUpdatePattern": sig["hasStateStorePattern"],
                "basicBlocks": sig["basicBlocks"],
                "cfgEdges": sig["cfgEdges"],
                "evidenceTier": tier,
                "technicalFindings": [
                    f"qualityClass={qclass}",
                    f"compares={sig['compareOps']}",
                    f"branches={sig['conditionalBranches']}",
                    f"stores={sig['storeOps']}",
                ],
                "limitations": [
                    "Kontrollflussmerkmale belegen keine Aktivierungsbedingung am Fahrzeug.",
                    "Vergleiche+Branches allein ergeben kein Feature Gate.",
                ],
            }
        )
    findings_all.sort(
        key=lambda x: (
            0 if x.get("qualityClass") == FEATURE_GATE_CANDIDATE else 1,
            0 if x.get("inputCategories") else 1,
            -int(x.get("conditionalBranches") or 0),
        )
    )
    total_cond = len(findings_all)
    findings = findings_all[:MAX_CONDITIONAL]
    cond_limits = _result_limits(
        total_analyzed=min(len(subject_fns), MAX_FUNCTIONS),
        total_candidates=total_cond,
        returned=len(findings),
        configured_limit=MAX_CONDITIONAL,
        truncation_reason="MAX_CONDITIONAL" if total_cond > MAX_CONDITIONAL else None,
    )
    return {
        "ok": True,
        "summary": {
            "functionsWithConditionalLogic": len(findings),
            "functionsWithConditionalLogicTotal": total_cond,
            "inputLinked": sum(1 for x in findings if x.get("inputCategories")),
            "stateStorePatterns": sum(1 for x in findings if x.get("stateUpdatePattern")),
            "qualityClasses": class_counts,
            "featureGateCandidates": class_counts.get(FEATURE_GATE_CANDIDATE, 0),
            "conditionalLogicOnly": class_counts.get(CONDITIONAL_LOGIC_ONLY, 0),
            "resultLimits": cond_limits,
        },
        "findings": findings,
        "resultLimits": cond_limits,
        "evidenceTier": INDICATIVE if findings else UNKNOWN,
        "analysisLimitations": [
            "Bedingte Verzweigungen allein sind keine Aktivierungslogik.",
            "FEATURE_GATE_CANDIDATE erfordert eingabe- und zustandsbezogene Signale.",
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
    call_graph: dict[str, Any] | None = None,
) -> dict[str, Any]:
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    seen_nodes: set[str] = set()
    seen_edges: set[tuple[str, str, str]] = set()
    edge_tier_counts = {
        "confirmedEdgeCount": 0,
        "indicativeEdgeCount": 0,
        "speculativeEdgeCount": 0,
        "unresolvedEdgeCount": 0,
    }

    call_pairs: set[tuple[str, str]] = set()
    for e in list((call_graph or {}).get("edges") or [])[:5000]:
        if not isinstance(e, dict):
            continue
        a = str(e.get("from") or e.get("src") or "").strip()
        b = str(e.get("to") or e.get("dst") or "").strip()
        if a and b:
            call_pairs.add((a, b))

    def add_node(nid: str, ntype: str, **meta: Any) -> None:
        if nid in seen_nodes or len(nodes) >= MAX_GRAPH_NODES:
            return
        seen_nodes.add(nid)
        nodes.append({"id": nid, "type": ntype, **meta})

    def add_edge(src: str, dst: str, kind: str, *, evidence: str, tier: str, confirmed: bool) -> None:
        if len(edges) >= MAX_GRAPH_EDGES:
            return
        if src not in seen_nodes or dst not in seen_nodes:
            edge_tier_counts["unresolvedEdgeCount"] += 1
            return
        key = (src, dst, kind)
        if key in seen_edges:
            return
        seen_edges.add(key)
        edges.append(
            {
                "from": src,
                "to": dst,
                "relation": kind,
                "technicalFinding": evidence,
                "confirmed": confirmed,
                "evidenceTier": tier,
            }
        )
        if tier == STATIC_CONFIRMED or confirmed:
            edge_tier_counts["confirmedEdgeCount"] += 1
        elif tier == INDICATIVE:
            edge_tier_counts["indicativeEdgeCount"] += 1
        elif tier == SPECULATIVE:
            edge_tier_counts["speculativeEdgeCount"] += 1
        else:
            edge_tier_counts["unresolvedEdgeCount"] += 1

    handler_work = handlers
    for h in handler_work[:MAX_HANDLERS]:
        addr = str(h.get("address") or h.get("functionId") or "")
        if not addr:
            continue
        nid = f"fn:{addr}"
        add_node(nid, "firmware_function", address=addr, name=h.get("name"), evidenceTier=h.get("evidenceTier"))
        # PROCESSES_INPUT only with sufficient input evidence.
        if h.get("evidenceTier") in (STATIC_CONFIRMED, INDICATIVE) and (h.get("inputCategories") or []):
            for cat in h.get("inputCategories") or []:
                cid = f"cat:{cat}"
                add_node(cid, "input_category", category=cat)
                add_edge(
                    nid,
                    cid,
                    REL_PROCESSES_INPUT,
                    evidence="; ".join((h.get("technicalFindings") or [])[:3]) or "classified_input",
                    tier=str(h.get("evidenceTier") or INDICATIVE),
                    confirmed=h.get("evidenceTier") == STATIC_CONFIRMED,
                )
        cond = h.get("conditionalLogic") or {}
        if cond.get("hasStateStorePattern") and cond.get("storeOps", 0) >= 1:
            sid = f"state:{addr}"
            add_node(sid, "state_variable_candidate", address=addr, verified=False)
            add_edge(
                nid,
                sid,
                REL_UPDATES_STATE,
                evidence=f"stores={cond.get('storeOps')} compares={cond.get('compareOps')}",
                tier=INDICATIVE,
                confirmed=False,
            )

    # CALLS only with callgraph evidence.
    for a, b in list(call_pairs)[:200]:
        sa, sb = f"fn:{a}", f"fn:{b}"
        if sa in seen_nodes and sb in seen_nodes:
            add_edge(sa, sb, REL_CALLS, evidence="callgraph_edge", tier=STATIC_CONFIRMED, confirmed=True)

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
            stateCount=sm.get("stateCount"),
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
            tier=SPECULATIVE,
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
        add_node(rn, "reference_function", address=raddr, name=ref.get("name") or p.get("referenceName"))
        add_edge(
            sn,
            rn,
            REL_STRUCTURALLY_DIFFERS,
            evidence=f"functionDiff={status}",
            tier=STATIC_CONFIRMED,
            confirmed=True,
        )

    nodes_total = len(nodes)
    edges_total = len(edges)
    graph_limits = _result_limits(
        total_analyzed=len(handlers),
        total_candidates=nodes_total + edges_total,
        returned=nodes_total + edges_total,
        configured_limit=MAX_GRAPH_NODES + MAX_GRAPH_EDGES,
        truncation_reason=(
            "MAX_GRAPH_NODES_OR_EDGES"
            if (len(seen_nodes) >= MAX_GRAPH_NODES or len(edges) >= MAX_GRAPH_EDGES)
            else None
        ),
    )
    graph_limits["totalGraphNodes"] = nodes_total
    graph_limits["totalGraphEdges"] = edges_total
    graph_limits["returnedGraphNodes"] = nodes_total
    graph_limits["returnedGraphEdges"] = edges_total

    return {
        "ok": True,
        "schemaVersion": SCHEMA_VERSION,
        "nodeCount": len(nodes),
        "edgeCount": len(edges),
        "nodes": nodes,
        "edges": edges,
        "quality": {
            "nodeCount": len(nodes),
            "edgeCount": len(edges),
            **edge_tier_counts,
        },
        "resultLimits": graph_limits,
        "analysisLimitations": [
            "Graph dokumentiert technische Zusammenhänge, keine Umgehungssequenzen.",
            "CALLS nur bei Callgraph-Beleg; PROCESSES_INPUT nur bei ausreichender Input-Evidenz.",
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
    cond_addrs = {
        str(x.get("address") or "")
        for x in list((conditional or {}).get("findings") or [])
        if x.get("address") and x.get("qualityClass") in (
            FEATURE_GATE_CANDIDATE,
            INPUT_RELATED_CONDITIONAL_LOGIC,
        )
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
            reasons.append("conditional_logic_quality")
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
    sm = state_machine_analysis if isinstance(state_machine_analysis, dict) else {}
    samples = list(sm.get("sampleStateMachines") or sm.get("stateMachines") or [])
    handler_addrs = {str(h.get("address") or "") for h in handlers}
    links: list[dict[str, Any]] = []
    for s in samples[:24]:
        addr = str(s.get("functionAddress") or s.get("address") or "")
        quality = str(s.get("analysisQuality") or s.get("evidenceTier") or "STATIC_CANDIDATE")
        state_count = s.get("stateCount")
        if state_count is None:
            state_count = s.get("estimatedStates") if s.get("stateCountVerified") else None
        links.append(
            {
                "functionAddress": addr or None,
                "functionName": s.get("functionName") or s.get("name"),
                "linkedToInputHandler": addr in handler_addrs,
                "fsmEvidenceTier": quality,
                "stateCount": state_count,
                "transitionCount": s.get("transitionCount") if s.get("transitionCountVerified") else None,
                "stateCountVerified": bool(s.get("stateCountVerified")),
                "dynamicRuntimeVerified": bool((runtime_validation or {}).get("dynamicRuntimeVerified"))
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
    profile_compat: Any = None,
    reference_trust: str | None,
    function_diff: dict[str, Any] | None,
    input_diff: dict[str, Any] | None,
    handlers: list[dict[str, Any]],
) -> dict[str, Any]:
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
                or ((p.get("subject") or {}).get("address") if isinstance(p.get("subject"), dict) else p.get("address")),
                "referenceAddress": p.get("referenceAddress")
                or ((p.get("reference") or {}).get("address") if isinstance(p.get("reference"), dict) else None),
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
        "profileCompatibility": {"ok": compat_ok, "status": compat_status, "reasons": compat_reasons},
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


def aggregate_evidence(handlers: list[dict[str, Any]], conditional: dict[str, Any] | None) -> dict[str, Any]:
    """Phase 2.3.1 — distribution-aware evidence summary (not max-tier wash)."""
    counts = {
        "staticConfirmedCount": 0,
        "indicativeCount": 0,
        "speculativeCount": 0,
        "unknownCount": 0,
        "ambiguousCount": 0,
    }
    strongest = None
    rank = {STATIC_CONFIRMED: 0, INDICATIVE: 1, SPECULATIVE: 2, UNKNOWN: 3}
    for h in handlers:
        t = str(h.get("evidenceTier") or UNKNOWN)
        if t == STATIC_CONFIRMED:
            counts["staticConfirmedCount"] += 1
        elif t == INDICATIVE:
            counts["indicativeCount"] += 1
        elif t == SPECULATIVE:
            counts["speculativeCount"] += 1
        else:
            counts["unknownCount"] += 1
        if (h.get("featureWeights") or {}).get("nameOrStringHints") and not (
            (h.get("featureWeights") or {}).get("structuralSignals")
        ):
            counts["ambiguousCount"] += 1
        if strongest is None or rank.get(t, 9) < rank.get(str(strongest.get("evidenceTier")), 9):
            strongest = {
                "address": h.get("address"),
                "name": h.get("name"),
                "evidenceTier": t,
                "inputCategories": h.get("inputCategories"),
            }

    total = sum(counts[k] for k in ("staticConfirmedCount", "indicativeCount", "speculativeCount", "unknownCount"))
    if total == 0:
        overall = UNKNOWN
        summary = "Keine Input-Handler-Kandidaten."
    elif counts["staticConfirmedCount"] and counts["staticConfirmedCount"] == total:
        overall = STATIC_CONFIRMED
        summary = "Alle Handler mit STATIC_CONFIRMED Codeeigenschaften (nicht Fahrzeugbeweis)."
    elif counts["staticConfirmedCount"]:
        overall = INDICATIVE
        summary = (
            f"Gemischte Evidenz: {counts['staticConfirmedCount']} static-confirmed, "
            f"{counts['indicativeCount']} indicative, {counts['speculativeCount']} speculative — "
            "Gesamtbewertung INDICATIVE (kein pauschales STATIC_CONFIRMED)."
        )
    elif counts["indicativeCount"] >= counts["speculativeCount"]:
        overall = INDICATIVE
        summary = "Überwiegend indikative strukturelle Hinweise."
    else:
        overall = SPECULATIVE
        summary = "Überwiegend spekulative / schwache Hinweise."

    return {
        **counts,
        "overallEvidenceSummary": summary,
        "overallEvidenceTier": overall,
        "strongestIndividualFinding": strongest,
        "analysisCoverage": {
            "handlerCount": total,
            "conditionalFindingCount": (conditional or {}).get("summary", {}).get("functionsWithConditionalLogic"),
            "featureGateCandidates": (conditional or {}).get("summary", {}).get("featureGateCandidates"),
            "conditionalLogicOnly": (conditional or {}).get("summary", {}).get("conditionalLogicOnly"),
        },
        "limitations": [
            "Ein einzelner STATIC_CONFIRMED-Befund bestätigt nicht die Gesamtanalyse.",
            "STATIC_CONFIRMED ≠ Nachweis realen Fahrzeugverhaltens.",
        ],
    }


def summarize_activation_forensics_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(full, dict):
        return {"ok": False}
    summary = full.get("summary") or {}
    handlers = list(full.get("inputHandlerFindings") or [])[:12]
    dist = full.get("activationEvidenceDistribution") or {}
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", SCHEMA_VERSION),
        "phase": full.get("phase", PHASE),
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
                "genericName": h.get("genericName"),
                "weakCandidate": h.get("weakCandidate"),
                "structuralOnly": h.get("structuralOnly"),
            }
            for h in handlers
        ],
        "undocumentedLogic": {
            "summary": (full.get("undocumentedLogic") or {}).get("summary"),
            "evidenceTier": (full.get("undocumentedLogic") or {}).get("evidenceTier"),
        },
        "conditionalLogicFindings": {
            "summary": (full.get("conditionalLogicFindings") or {}).get("summary"),
            "resultLimits": (full.get("conditionalLogicFindings") or {}).get("resultLimits"),
        },
        "resultLimits": full.get("resultLimits"),
        "conditionalLogicQuality": (full.get("conditionalLogicFindings") or {}).get("summary", {}).get("qualityClasses"),
        "fsmIntegration": {
            "fsmCandidateCount": (full.get("fsmIntegration") or {}).get("fsmCandidateCount"),
            "inputLinkedFsmCount": (full.get("fsmIntegration") or {}).get("inputLinkedFsmCount"),
        },
        "activationEvidenceGraph": {
            "nodeCount": (full.get("activationEvidenceGraph") or {}).get("nodeCount"),
            "edgeCount": (full.get("activationEvidenceGraph") or {}).get("edgeCount"),
            "resultLimits": (full.get("activationEvidenceGraph") or {}).get("resultLimits"),
        },
        "evidenceGraphQuality": (full.get("activationEvidenceGraph") or {}).get("quality"),
        "activationEvidenceDistribution": {
            "staticConfirmedCount": dist.get("staticConfirmedCount"),
            "indicativeCount": dist.get("indicativeCount"),
            "speculativeCount": dist.get("speculativeCount"),
            "unknownCount": dist.get("unknownCount"),
            "ambiguousCount": dist.get("ambiguousCount"),
            "overallEvidenceTier": dist.get("overallEvidenceTier"),
            "overallEvidenceSummary": dist.get("overallEvidenceSummary"),
            "strongestIndividualFinding": dist.get("strongestIndividualFinding"),
        },
        "inputDetectionQuality": full.get("inputDetectionQuality"),
        "semanticDataFlow": full.get("semanticDataFlowSummary"),
        "referenceComparison": {
            "referenceTrust": (full.get("referenceComparison") or {}).get("referenceTrust"),
            "referenceIsCommunity": (full.get("referenceComparison") or {}).get("referenceIsCommunity"),
            "profileCompatibility": (full.get("referenceComparison") or {}).get("profileCompatibility"),
        },
        "prioritization": {"top": list((full.get("prioritization") or {}).get("prioritizedFunctions") or [])[:8]},
        "evidenceTier": dist.get("overallEvidenceTier") or full.get("evidenceTier"),
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
    dataflow_export: dict[str, Any] | None = None,
    deadline_sec: float | None = None,
    negative_control: bool = False,
) -> dict[str, Any]:
    t0 = time.monotonic()
    limit = deadline_sec if deadline_sec is not None else ANALYSIS_TIMEOUT_SEC
    limitations = list(BASE_LIMITATIONS)
    notes: list[str] = [f"phase={PHASE}"]
    if negative_control:
        notes.append("analysisMode=negative_control_reference")
        limitations.append(
            "Kontrollprüfung an Referenzfirmware — Community-Herkunft bleibt sichtbar; kein OEM-Automatismus."
        )

    # Accept exports that omit ok=true but have functions (real Ghidra dumps).
    fa = function_analysis
    if isinstance(fa, dict) and fa.get("functions") and "ok" not in fa:
        fa = {**fa, "ok": True}

    if not fa or not fa.get("ok"):
        return {
            "ok": False,
            "schemaVersion": SCHEMA_VERSION,
            "phase": PHASE,
            "inputHandlerFindings": [],
            "undocumentedLogic": {"ok": False, "findings": []},
            "conditionalLogicFindings": {"ok": False, "findings": []},
            "activationEvidenceGraph": {"ok": False, "nodes": [], "edges": []},
            "activationEvidenceDistribution": aggregate_evidence([], None),
            "analysisLimitations": limitations + ["Funktionsexport fehlt/ungültig."],
            "notes": notes + ["activationForensics=missing_export"],
            "evidenceTier": UNKNOWN,
        }

    subject_fns = _fns(fa)
    ib = input_behavior if isinstance(input_behavior, dict) and input_behavior.get("ok") else None
    if ib is None:
        ib = analyze_input_behavior(fa, call_graph=call_graph)

    # Semantic dataflow (optional export or derived).
    sdf = None
    dataflow_by_addr: dict[str, dict[str, Any]] = {}
    if analyze_semantic_dataflow is not None:
        try:
            sdf = analyze_semantic_dataflow(fa, dataflow_export=dataflow_export, call_graph=call_graph)
            for row in list((sdf or {}).get("functions") or []):
                a = str(row.get("address") or "")
                if a:
                    dataflow_by_addr[a] = row
            notes.extend((sdf or {}).get("notes") or [])
        except Exception as e:
            notes.append(f"semanticDataFlow={type(e).__name__}")

    handlers_all: list[dict[str, Any]] = []
    analysis_complete = True
    for f in subject_fns[:MAX_FUNCTIONS]:
        if time.monotonic() - t0 > limit:
            notes.append("activationForensics=timeout_partial")
            limitations.append("Analyse vorzeitig beendet (Timeout) — Teilergebnis.")
            analysis_complete = False
            break
        h = classify_activation_handler(f, dataflow_fn=dataflow_by_addr.get(_addr(f)))
        if h:
            handlers_all.append(h)
    handlers_all.sort(
        key=lambda x: (
            {STATIC_CONFIRMED: 0, INDICATIVE: 1, SPECULATIVE: 2, UNKNOWN: 3}.get(str(x.get("evidenceTier")), 9),
            -float(x.get("confidence") or 0),
        )
    )
    total_handler_candidates = len(handlers_all)
    handlers = handlers_all[:MAX_HANDLERS]
    handler_limits = _result_limits(
        total_analyzed=min(len(subject_fns), MAX_FUNCTIONS),
        total_candidates=total_handler_candidates,
        returned=len(handlers),
        configured_limit=MAX_HANDLERS,
        truncation_reason="MAX_HANDLERS" if total_handler_candidates > MAX_HANDLERS else None,
        analysis_complete=analysis_complete,
    )

    category_counts: dict[str, int] = {c: 0 for c in INPUT_CATEGORIES}
    for h in handlers:
        for c in h.get("inputCategories") or []:
            category_counts[c] = category_counts.get(c, 0) + 1

    undoc = detect_undocumented_logic(subject_fns, function_diff=function_diff, input_handlers=handlers)
    cond = analyze_conditional_logic(subject_fns, input_handlers=handlers, dataflow_by_addr=dataflow_by_addr)
    sm_raw = ib.get("stateMachineAnalysis") if isinstance(ib, dict) else None
    if not sm_raw or not sm_raw.get("ok"):
        sm_raw = analyze_state_machines(subject_fns, ib.get("inputFunctions") if ib else [])
    fsm = integrate_fsm(sm_raw, handlers, runtime_validation=runtime_validation)
    graph = build_evidence_graph(
        handlers=handlers,
        conditional=cond,
        undocumented=undoc,
        state_machines=sm_raw,
        function_diff=function_diff,
        call_graph=call_graph,
    )
    matching = (function_diff or {}).get("functionMatching") if isinstance(function_diff, dict) else None
    prio = prioritize_functions(handlers, conditional=cond, undocumented=undoc, matching=matching)
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
    dist = aggregate_evidence(handlers, cond)

    # Detection quality snapshot (fixture metrics filled by tests).
    input_detection_quality = {
        "genericNamedHandlers": sum(1 for h in handlers if h.get("genericName")),
        "namedHandlers": sum(1 for h in handlers if not h.get("genericName")),
        "structuralMultiSignal": sum(
            1 for h in handlers if "structural_multi_signal" in (h.get("detectionMethods") or [])
        ),
        "nameOrStringOnly": dist.get("ambiguousCount"),
        "note": "Keine Precision/Recall für reale Firmware ohne unabhängige Ground Truth.",
    }

    semantic_summary = None
    if isinstance(sdf, dict):
        sdf_sum = sdf.get("summary") or {}
        semantic_summary = {
            "ok": sdf.get("ok"),
            "functionsAnalyzed": sdf_sum.get("totalFunctions", sdf_sum.get("functionCount")),
            "withMemoryReads": sdf_sum.get("withMemoryReads"),
            "withMemoryWrites": sdf_sum.get("withMemoryWrites"),
            "withConditionals": sdf_sum.get("withConditionals"),
            "withCalls": sdf_sum.get("withCalls"),
            "qualityOk": sdf_sum.get("qualityOk"),
            "qualityPartial": sdf_sum.get("qualityPartial"),
            "qualityMissing": sdf_sum.get("qualityMissing"),
            "fromDataflowExport": sdf_sum.get("exportedFunctions", sdf_sum.get("fromDataflowExport")),
            "derivedOnly": sdf_sum.get("derivedFunctions", sdf_sum.get("derivedOnly")),
            "provenanceCounts": sdf_sum.get("provenanceCounts"),
            "dataflowCoveragePercent": sdf_sum.get("dataflowCoveragePercent"),
            "source": (
                "dataflow_export"
                if sdf_sum.get("exportedFunctions", sdf_sum.get("fromDataflowExport"))
                else ("derived" if sdf_sum.get("derivedFunctions", sdf_sum.get("derivedOnly")) else None)
            ),
        }
        for lim in list(sdf.get("analysisLimitations") or [])[:4]:
            if lim not in limitations:
                limitations.append(lim)

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
            "inputHandlerCandidateTotal": total_handler_candidates,
            "categories": {k: v for k, v in category_counts.items() if v},
            "undocumentedFindingCount": (undoc.get("summary") or {}).get("findingCount"),
            "conditionalLogicCount": (cond.get("summary") or {}).get("functionsWithConditionalLogic"),
            "fsmLinkedCount": fsm.get("inputLinkedFsmCount"),
            "graphNodeCount": graph.get("nodeCount"),
            "graphEdgeCount": graph.get("edgeCount"),
            "elapsedSec": elapsed,
            "negativeControl": negative_control,
        },
        "resultLimits": {
            "handlers": handler_limits,
            "conditionalLogic": cond.get("resultLimits") or (cond.get("summary") or {}).get("resultLimits"),
            "evidenceGraph": graph.get("resultLimits"),
        },
        "categoryCounts": category_counts,
        "inputHandlerFindings": handlers,
        "undocumentedLogic": undoc,
        "conditionalLogicFindings": cond,
        "fsmIntegration": fsm,
        "activationEvidenceGraph": graph,
        "activationEvidenceDistribution": dist,
        "inputDetectionQuality": input_detection_quality,
        "semanticDataFlowSummary": semantic_summary,
        "prioritization": prio,
        "referenceComparison": ref_cmp,
        "evidenceTier": dist.get("overallEvidenceTier") or UNKNOWN,
        "analysisLimitations": limitations,
        "notes": notes,
    }


def evaluate_detection_quality(
    findings: list[dict[str, Any]],
    ground_truth: list[dict[str, Any]],
    *,
    category_key: str = "inputCategories",
) -> dict[str, Any]:
    gt_pos = [g for g in ground_truth if g.get("expectDetect", True)]
    gt_neg = [g for g in ground_truth if not g.get("expectDetect", True)]

    def _key(x: dict[str, Any]) -> str:
        return str(x.get("address") or x.get("name") or x.get("functionId") or "").lower()

    found_keys = {_key(f) for f in findings}
    tp = fn = ambiguous = 0
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
    tn = 0
    for g in gt_neg:
        if _key(g) not in found_keys:
            tn += 1
    gt_keys = {_key(g) for g in ground_truth}
    for f in findings:
        if _key(f) and _key(f) not in gt_keys:
            fp += 1
    precision = (tp / (tp + fp)) if (tp + fp) else None
    recall = (tp / (tp + fn)) if (tp + fn) else None
    f1 = None
    if precision is not None and recall is not None and (precision + recall) > 0:
        f1 = 2 * precision * recall / (precision + recall)
    return {
        "truePositives": tp,
        "trueNegatives": tn,
        "falsePositives": fp,
        "falseNegatives": fn,
        "precision": round(precision, 4) if precision is not None else None,
        "recall": round(recall, 4) if recall is not None else None,
        "f1Score": round(f1, 4) if f1 is not None else None,
        "ambiguousFindings": ambiguous,
        "unknownFindings": sum(1 for f in findings if f.get("evidenceTier") == UNKNOWN),
        "disclaimer": (
            "Metriken gelten nur für kontrollierte Fixtures — "
            "nicht als Erkennungsgenauigkeit realer Scooter-Firmware."
        ),
    }
