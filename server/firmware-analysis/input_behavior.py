"""Static Input Behavior + State Machine analysis (Phase 2.2C).

Documents technical properties of Ghidra function exports related to input
handling and state-like control flow. Heuristic — never invents scooter
activation sequences or claims verified vehicle behavior.
"""
from __future__ import annotations

from typing import Any

from function_matcher import is_generic_name, match_functions

# Categories are technical code properties, not vehicle claims.
CATEGORY_HINTS: dict[str, tuple[str, ...]] = {
    "button_or_key": ("button", "key", "press", "btn", "taste", "switch_in"),
    "gpio_event": ("gpio", "exti", "irq_gpio", "hal_gpio"),
    "ble_message": ("ble", "bluetooth", "gatt", "nordic", "nus", "att_"),
    "uart_or_comm": ("uart", "usart", "can_", "spi_", "i2c_", "rx_", "tx_"),
    # Avoid bare "handler" / "pin" / "key" alone — too many IRQ/reset/math false positives.
    "event_queue": ("queue", "event", "msg_", "mailbox", "dispatch", "event_handler", "msg_handler"),
    "state_update": ("state", "mode", "fsm", "transition", "status_set", "set_state"),
    "input_callback": ("callback", "on_input", "process_input", "input_", "handle_input", "input_handler"),
}

# Explicit non-input entry points (Cortex-M / boot).
_NAME_DENYLIST = (
    "reset_handler",
    "nmi_handler",
    "hardfault",
    "memmanage",
    "busfault",
    "usagefault",
    "svcall",
    "pendsv",
    "systick",
    "default_handler",
)

STRING_HINTS: dict[str, tuple[str, ...]] = {
    "button_or_key": ("button", "key", "press", "btn"),
    "gpio_event": ("gpio", "exti", "pin"),
    "ble_message": ("ble", "gatt", "bluetooth"),
    "uart_or_comm": ("uart", "usart", "rx", "tx"),
    "event_queue": ("event", "queue", "msg"),
    "state_update": ("state", "mode", "fsm"),
}

# Evidence for code properties (NOT verified vehicle behavior).
EVIDENCE_CONFIRMED = "confirmed_static"
EVIDENCE_INDICATIVE = "indicative"
EVIDENCE_SPECULATIVE = "speculative"
EVIDENCE_UNKNOWN = "unknown"
# Backward-compat alias still accepted by older clients/tests.
EVIDENCE_CONFIRMED_LEGACY = "confirmed"

FSM_CANDIDATE = "STATE_MACHINE_CANDIDATE"
FSM_STRUCTURE = "STATE_STRUCTURE_IDENTIFIED"
FSM_TRANSITIONS = "STATE_TRANSITIONS_IDENTIFIED"
FSM_NOT_VERIFIABLE = "NOT_VERIFIABLE"

MAX_FUNCTIONS = 2500
MAX_INPUT_FUNCS = 80
MAX_STATE_MACHINES = 12

# Names that are pure helpers — never promote via call-neighborhood alone.
_HELPER_NAME_DENY = (
    "add_",
    "mul_",
    "xor_",
    "sub_",
    "div_",
    "loop_",
    "memcpy",
    "memset",
    "strcmp",
    "strlen",
)


def analyze_input_behavior(
    function_analysis: dict[str, Any] | None,
    *,
    call_graph: dict[str, Any] | None = None,
) -> dict[str, Any]:
    fns = _fns(function_analysis)
    limitations = [
        "Input Behavior Analysis ist heuristisch und kein Nachweis realen Fahrzeugverhaltens.",
        "Einzelne Strings/Konstanten allein gelten nicht als Funktionsnachweis.",
        "Keine Aktivierungsfolgen oder Umgehungsempfehlungen.",
    ]
    if not function_analysis or not function_analysis.get("ok"):
        return {
            "ok": False,
            "schemaVersion": 1,
            "inputFunctions": [],
            "categories": {},
            "summary": {"functionCount": 0, "inputRelevantCount": 0},
            "analysisLimitations": limitations + ["Funktionsexport fehlt/ungültig."],
            "notes": ["inputBehavior=missing_export"],
            "evidenceTier": EVIDENCE_SPECULATIVE,
        }

    input_fns: list[dict[str, Any]] = []
    categories: dict[str, int] = {k: 0 for k in CATEGORY_HINTS}
    for f in fns[:MAX_FUNCTIONS]:
        scored = classify_input_function(f)
        if not scored:
            continue
        input_fns.append(scored)
        for cat in scored.get("categories") or []:
            categories[cat] = categories.get(cat, 0) + 1

    input_fns.sort(key=lambda x: (_tier_rank(x.get("evidenceTier")), -float(x.get("score") or 0)))
    input_fns = input_fns[:MAX_INPUT_FUNCS]

    state = analyze_state_machines(fns, input_fns)
    tier = _overall_tier(input_fns, state)

    truncated = len(fns) > MAX_FUNCTIONS
    if truncated:
        limitations = limitations + [
            f"Analyse unvollständig: nur die ersten {MAX_FUNCTIONS} von {len(fns)} Funktionen bewertet."
        ]

    notes = [
        f"inputBehavior=ok relevant={len(input_fns)} cats="
        + ",".join(f"{k}:{v}" for k, v in categories.items() if v)
    ]
    if truncated:
        notes.append(f"inputBehavior=truncated max={MAX_FUNCTIONS} total={len(fns)}")
    if call_graph and call_graph.get("ok"):
        notes.append(f"inputBehavior=callgraph_edges={call_graph.get('edgeCount')}")

    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "static-input-behavior",
        "toolNote": "Static heuristics on Ghidra exports — not dynamic vehicle tracing.",
        "inputFunctions": input_fns,
        "categories": {k: v for k, v in categories.items() if v},
        "summary": {
            "functionCount": len(fns),
            "analyzedFunctionCount": min(len(fns), MAX_FUNCTIONS),
            "truncated": truncated,
            "inputRelevantCount": len(input_fns),
            "confirmedCount": sum(
                1
                for x in input_fns
                if x.get("evidenceTier") in {EVIDENCE_CONFIRMED, EVIDENCE_CONFIRMED_LEGACY}
            ),
            "indicativeCount": sum(1 for x in input_fns if x.get("evidenceTier") == EVIDENCE_INDICATIVE),
            "speculativeCount": sum(1 for x in input_fns if x.get("evidenceTier") == EVIDENCE_SPECULATIVE),
            "categoryCount": len([k for k, v in categories.items() if v]),
        },
        "stateMachineAnalysis": state,
        "evidenceTier": tier,
        "analysisLimitations": limitations + list(state.get("analysisLimitations") or []),
        "notes": notes + list(state.get("notes") or []),
    }


def classify_input_function(f: dict[str, Any]) -> dict[str, Any] | None:
    """Classify a function as input-related. Conservative — reduce false positives."""
    name = str(f.get("name") or "")
    name_l = name.lower()
    if any(d in name_l for d in _NAME_DENYLIST):
        return None
    if any(name_l.startswith(p) or f"_{p}" in f"_{name_l}" for p in _HELPER_NAME_DENY):
        # Pure arithmetic/helpers: never classify as input processing.
        return None

    strings = [str(s).lower() for s in (f.get("strings") or [])]
    calls = [str(c).lower() for c in (f.get("calls") or [])]
    called_by = [str(c).lower() for c in (f.get("calledBy") or [])]
    blocks = int(f.get("basicBlocks") or 0)
    edges = int(f.get("cfgEdges") or 0)

    hits: dict[str, list[str]] = {}
    signal_classes: set[str] = set()

    # Strong name signals only (exact-ish category keys in the function name).
    for cat, keys in CATEGORY_HINTS.items():
        if any(k in name_l for k in keys):
            hits.setdefault(cat, []).append(f"name:{name}")
            signal_classes.add("name")

    # Strings alone never confirm; need another class.
    for cat, keys in STRING_HINTS.items():
        for s in strings:
            if any(k in s for k in keys) and len(s) >= 4:
                hits.setdefault(cat, []).append(f"string:{s[:48]}")
                signal_classes.add("string")
                break

    # Call neighborhood: only if the function itself already has a name/string hit,
    # or the name looks like a handler/callback (avoid promoting callees of input fns).
    neigh = " ".join(calls + called_by)
    handlerish = any(t in name_l for t in ("handle", "callback", "dispatch", "process_input", "on_"))
    if "name" in signal_classes or "string" in signal_classes or handlerish:
        for cat, keys in CATEGORY_HINTS.items():
            if any(k in neigh for k in keys):
                hits.setdefault(cat, []).append("call_neighborhood")
                signal_classes.add("calls")
                break

    # CFG density alone is NOT an input signal (common for any branchy helper).
    # Only reinforce an existing name/string classification.
    structural = False
    if blocks >= 3 and edges >= blocks and ("name" in signal_classes or "string" in signal_classes):
        structural = True
        signal_classes.add("cfg")
        if "input_callback" not in hits and any(
            t in name_l for t in ("process", "handle", "dispatch", "input")
        ):
            hits.setdefault("input_callback", []).append("cfg_dense+name")

    if not hits:
        return None

    # Drop weak cases: string-only, cfg-only, call-neighborhood-only, or helperish names.
    if signal_classes <= {"string"} or signal_classes <= {"cfg"} or signal_classes <= {"calls"}:
        return None

    cats = list(hits.keys())

    # confirmed_static: strong name OR (name + another class). Never claim vehicle behavior.
    if "name" in signal_classes and (
        len(signal_classes) >= 2 or any(k in name_l for k in ("process_input", "handle_input", "on_input"))
    ):
        tier = EVIDENCE_CONFIRMED
    elif "name" in signal_classes:
        tier = EVIDENCE_INDICATIVE
    elif "string" in signal_classes and "calls" in signal_classes:
        tier = EVIDENCE_INDICATIVE
    else:
        tier = EVIDENCE_SPECULATIVE

    score = 0.3 * len(signal_classes) + 0.1 * min(3, len(cats))
    if structural:
        score += 0.05
    if not is_generic_name(name):
        score += 0.15

    evidence: list[str] = []
    for items in hits.values():
        evidence.extend(items[:2])

    return {
        "address": f.get("address"),
        "name": name,
        "fingerprint": f.get("fingerprint"),
        "categories": cats,
        "evidenceTier": tier,
        "score": round(min(1.0, score), 3),
        "evidence": evidence[:12],
        "basicBlocks": blocks,
        "cfgEdges": edges,
        "callCount": len(calls),
        "limitations": [
            "confirmed_static = nachvollziehbare Codeeigenschaft, kein Nachweis realen Fahrzeugverhaltens.",
        ],
    }


def analyze_state_machines(
    all_fns: list[dict[str, Any]],
    input_fns: list[dict[str, Any]],
) -> dict[str, Any]:
    """FSM heuristics with optional constant/enum structure (Phase 2.2E).

    Basic blocks alone ≠ states. Concrete counts only when distinct state
    constants / documented transitions are recoverable from export fields.
    Unknown firmware stays null without reliable evidence.
    """
    limitations = [
        "Ein Basic Block entspricht nicht automatisch einem Programmzustand.",
        "Konkrete Zustands-/Übergangszahlen nur bei nachvollziehbarer Struktur; sonst null.",
        "Keine Aktivierungsfolgen oder Umgehungsempfehlungen.",
        "STATE_TRANSITIONS_IDENTIFIED nur bei dokumentierter/kontrollierter Übergangsevidenz — keine dynamische Laufzeitverifikation ohne Unicorn/Trace.",
    ]
    machines: list[dict[str, Any]] = []
    input_addrs = {x.get("address") for x in input_fns}
    input_names = {str(x.get("name") or "").lower() for x in input_fns}

    for f in all_fns[:MAX_FUNCTIONS]:
        finding = classify_state_machine(f, input_addrs=input_addrs, input_names=input_names)
        if finding:
            machines.append(finding)

    machines.sort(
        key=lambda m: (
            0
            if m.get("analysisQuality") == FSM_TRANSITIONS
            else 1
            if m.get("analysisQuality") == FSM_STRUCTURE
            else 2
            if m.get("analysisQuality") == FSM_CANDIDATE
            else 3,
            -float(m.get("edgeDensity") or 0),
        )
    )
    machines = machines[:MAX_STATE_MACHINES]
    candidates = sum(1 for m in machines if m.get("analysisQuality") == FSM_CANDIDATE)
    structured = sum(1 for m in machines if m.get("analysisQuality") == FSM_STRUCTURE)
    transitions = sum(1 for m in machines if m.get("analysisQuality") == FSM_TRANSITIONS)

    verified_states = [
        int(m["stateCount"])
        for m in machines
        if isinstance(m.get("stateCount"), int) and m.get("stateCountVerified")
    ]
    verified_trans = [
        int(m["transitionCount"])
        for m in machines
        if isinstance(m.get("transitionCount"), int) and m.get("transitionCountVerified")
    ]

    return {
        "ok": True,
        "schemaVersion": 1,
        "stateMachineCount": len(machines),
        "totalEstimatedStates": sum(verified_states) if verified_states else None,
        "totalEstimatedTransitions": sum(verified_trans) if verified_trans else None,
        "verifiedStateCountTotal": sum(verified_states) if verified_states else None,
        "candidateCount": candidates,
        "structureIdentifiedCount": structured,
        "transitionsIdentifiedCount": transitions,
        "stateMachineValidation": {
            "staticStructure": structured + transitions,
            "controlledTransitionEvidence": transitions,
            "dynamicRuntimeVerified": False,
            "notes": [
                "Keine dynamische Laufzeitverifikation in dieser Analyse.",
                "Übergänge nur aus statischen Konstanten/CMP-/Store-Mustern bzw. dokumentierter Ground Truth.",
            ],
        },
        "stateMachines": machines,
        "analysisLimitations": limitations,
        "notes": [
            f"stateMachines={len(machines)} candidates={candidates} structure={structured} "
            f"transitions={transitions} (no BB-derived state counts)"
        ],
        "evidenceTier": (
            EVIDENCE_CONFIRMED
            if transitions
            else EVIDENCE_INDICATIVE
            if structured or candidates
            else EVIDENCE_SPECULATIVE
        ),
    }


def classify_state_machine(
    f: dict[str, Any],
    *,
    input_addrs: set[Any] | None = None,
    input_names: set[str] | None = None,
) -> dict[str, Any] | None:
    """Classify one function as FSM candidate / structure / transitions / skip."""
    input_addrs = input_addrs or set()
    input_names = input_names or set()
    name = str(f.get("name") or "")
    name_l = name.lower()
    blocks = int(f.get("basicBlocks") or 0)
    edges = int(f.get("cfgEdges") or 0)
    mnemonics = [str(m).lower() for m in (f.get("mnemonics") or [])]
    strings = [str(s) for s in (f.get("strings") or [])]
    strings_l = [s.lower() for s in strings]
    constants = list(f.get("constants") or [])
    branchy = sum(
        1
        for m in mnemonics
        if m.startswith(("b", "cbz", "cbnz", "tbz", "tbnz")) or m in {"it", "bx", "blx", "cmp", "cmn"}
    )

    # Explicit fixture / export annotations (controlled tests)
    annotated_states = f.get("stateValues") or f.get("documentedStates")
    annotated_transitions = f.get("documentedTransitions") or f.get("stateTransitions")
    state_var = f.get("stateVariable") or f.get("stateVariableAddress")

    state_labels = _extract_state_labels(strings)
    state_consts = _extract_state_constants(constants, state_labels, annotated_states)
    cmp_hits = _count_state_comparisons(mnemonics, constants, state_consts)
    store_hits = _count_state_stores(mnemonics, strings_l, state_var)

    name_stateish = any(k in name_l for k in ("state", "mode", "fsm", "process_input", "tick"))
    string_stateish = bool(state_labels) or any(
        any(k in s for k in ("state", "mode", "fsm")) for s in strings_l
    )
    linked_input = f.get("address") in input_addrs or name_l in input_names
    density = edges / max(blocks, 1)

    # Branchy math without state signals → never an FSM.
    if blocks >= 3 and branchy >= 2 and not (
        name_stateish or string_stateish or linked_input or state_consts or annotated_states
    ):
        return None
    if blocks < 2 and not (annotated_states or state_consts):
        return None

    signals = 0
    evidence: list[str] = []
    if name_stateish:
        signals += 1
        evidence.append(f"name:{name}")
    if string_stateish:
        signals += 1
        evidence.append("string:state/mode/fsm")
    if linked_input:
        signals += 1
        evidence.append("linked_input_heuristic")
    if density >= 1.3 and branchy >= 3:
        signals += 1
        evidence.append(f"cfg density={density:.2f} branches={branchy}")
    if state_consts and len(state_consts) >= 2:
        signals += 1
        evidence.append(f"state_constants={state_consts[:8]}")
    if state_var:
        signals += 1
        evidence.append(f"state_variable={state_var}")
    if cmp_hits >= 1:
        signals += 1
        evidence.append(f"state_comparisons={cmp_hits}")
    if store_hits >= 1:
        signals += 1
        evidence.append(f"state_stores={store_hits}")
    if annotated_transitions:
        signals += 1
        evidence.append(f"documented_transitions={len(annotated_transitions)}")

    if signals == 0:
        return None
    if signals == 1 and not (name_stateish or string_stateish or linked_input or state_consts):
        return None

    state_count = None
    transition_count = None
    state_count_verified = False
    transition_count_verified = False
    quality = FSM_NOT_VERIFIABLE
    uncertainty = "Unzureichende Merkmale für belastbare FSM-Aussage."

    # Transitions: documented edges OR (state consts + cmp + store) on controlled structure.
    if annotated_transitions and isinstance(annotated_transitions, list) and len(annotated_transitions) >= 1:
        quality = FSM_TRANSITIONS
        transition_count = len(annotated_transitions)
        transition_count_verified = True
        if annotated_states and isinstance(annotated_states, list):
            state_count = len(annotated_states)
            state_count_verified = True
        elif state_consts and len(state_consts) >= 2:
            state_count = len(state_consts)
            state_count_verified = True
        uncertainty = (
            "Zustandsübergänge aus dokumentierter Ground Truth / Exportannotation — "
            "keine dynamische Laufzeitverifikation."
        )
    elif (
        state_consts
        and len(state_consts) >= 2
        and (name_stateish or string_stateish)
        and cmp_hits >= max(1, len(state_consts) - 1)
        and (store_hits >= 1 or state_var)
    ):
        quality = FSM_TRANSITIONS
        state_count = len(state_consts)
        state_count_verified = True
        # Transitions estimated from cmp/store evidence, still static.
        transition_count = max(cmp_hits, store_hits)
        transition_count_verified = True
        uncertainty = (
            "Statische Übergangsstruktur aus Konstanten/CMP/Store — "
            "keine dynamische Laufzeitverifikation."
        )
    elif state_consts and len(state_consts) >= 2 and (name_stateish or string_stateish):
        quality = FSM_STRUCTURE
        state_count = len(state_consts)
        state_count_verified = True
        transition_count = None
        uncertainty = (
            "Zustandskonstanten/Enum-Struktur nachvollziehbar; Übergänge nicht verifiziert."
        )
    elif signals >= 3 and name_stateish:
        quality = FSM_STRUCTURE
        uncertainty = (
            "Strukturhinweise vorhanden; konkrete Zustandszahl ohne dokumentierte "
            "Zustandskonstanten nicht verifizierbar."
        )
    elif signals >= 2 or name_stateish:
        quality = FSM_CANDIDATE
        uncertainty = (
            "Zustandsabhängige Verarbeitung vermutet — Anzahl der Zustände nicht verifiziert."
        )
    else:
        return None

    return {
        "functionAddress": f.get("address"),
        "functionName": name,
        "estimatedStates": state_count,
        "estimatedTransitions": transition_count,
        "stateCount": state_count,
        "transitionCount": transition_count,
        "stateCountVerified": state_count_verified,
        "transitionCountVerified": transition_count_verified,
        "stateValues": state_consts or annotated_states,
        "stateVariable": state_var,
        "stateLabels": state_labels[:12],
        "documentedTransitions": annotated_transitions
        if isinstance(annotated_transitions, list)
        else None,
        "basicBlocks": blocks,
        "cfgEdges": edges,
        "branchMnemonicCount": branchy,
        "edgeDensity": round(density, 3),
        "linkedToInputHeuristic": bool(linked_input),
        "analysisQuality": quality,
        "validationKind": (
            "controlled_static"
            if quality == FSM_TRANSITIONS
            else "static_structure"
            if quality == FSM_STRUCTURE
            else "heuristic"
        ),
        "dynamicRuntimeVerified": False,
        "evidence": evidence[:10] + [f"cfg blocks={blocks} edges={edges} (not used as stateCount)"],
        "uncertainty": uncertainty,
        "limitations": [
            "Keine konkreten Aktivierungsfolgen abgeleitet.",
            "Basic-Block-Anzahl ist kein Zustandszähler.",
            "Keine dynamische Laufzeitverifikation ohne separaten Trace.",
        ],
    }


def _extract_state_labels(strings: list[str]) -> list[str]:
    out: list[str] = []
    for s in strings:
        sl = s.lower()
        if sl.startswith("state_") or sl.startswith("mode_") or "state=" in sl or "mode=" in sl:
            out.append(s[:64])
        elif sl in {"idle", "active", "error", "init", "ready", "fault"}:
            out.append(s[:64])
    return out


def _extract_state_constants(
    constants: list[Any],
    labels: list[str],
    annotated: Any,
) -> list[int]:
    if isinstance(annotated, list) and annotated and all(isinstance(x, int) for x in annotated):
        return sorted(set(int(x) for x in annotated))
    vals: list[int] = []
    for c in constants:
        try:
            if isinstance(c, int):
                v = c
            else:
                s = str(c).strip().lower()
                v = int(s, 0)
        except Exception:
            continue
        # Small enum-like immediates only
        if 0 <= v <= 32:
            vals.append(v)
    # Without state labels / annotations, small immediates are NOT states
    # (avoids classifying branchy arithmetic helpers as FSMs).
    if not labels and not annotated:
        return []
    uniq = sorted(set(vals))
    return uniq if len(uniq) >= 2 else []


def _count_state_comparisons(
    mnemonics: list[str],
    constants: list[Any],
    state_consts: list[int],
) -> int:
    if not state_consts:
        return sum(1 for m in mnemonics if m.startswith("cmp") or m in {"cbz", "cbnz"})
    # Prefer explicit overlap between exported constants and state set
    const_ints: set[int] = set()
    for c in constants:
        try:
            const_ints.add(int(c) if isinstance(c, int) else int(str(c), 0))
        except Exception:
            continue
    overlap = const_ints & set(state_consts)
    cmp_n = sum(1 for m in mnemonics if m.startswith("cmp") or m in {"cbz", "cbnz", "tbb", "tbh"})
    if overlap:
        return max(len(overlap), min(cmp_n, len(state_consts)))
    return min(cmp_n, len(state_consts)) if cmp_n else 0


def _count_state_stores(mnemonics: list[str], strings_l: list[str], state_var: Any) -> int:
    stores = sum(1 for m in mnemonics if m.startswith(("str", "stm")))
    if state_var:
        return max(1, stores)
    if any("state" in s or "mode" in s for s in strings_l) and stores:
        return stores
    return 0


def diff_input_behavior(
    subject: dict[str, Any] | None,
    reference: dict[str, Any] | None,
    *,
    subject_fns: list[dict[str, Any]] | None = None,
    reference_fns: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Compare input-behavior results across two firmwares using function matching."""
    limitations = [
        "Input-Behavior-Diff ist strukturell — keine Manipulationsaussage.",
        "Strukturelle Änderung ≠ Nachweis einer Veränderung des Eingabeverhaltens am Fahrzeug.",
    ]
    if not subject or not subject.get("ok"):
        return {
            "ok": False,
            "schemaVersion": 1,
            "summary": {},
            "pairs": [],
            "analysisLimitations": limitations + ["Subject Input Behavior fehlt."],
            "notes": ["inputBehaviorDiff=missing_subject"],
        }
    if not reference or not reference.get("ok"):
        return {
            "ok": False,
            "schemaVersion": 1,
            "summary": {},
            "pairs": [],
            "analysisLimitations": limitations + ["Referenz Input Behavior fehlt."],
            "notes": ["inputBehaviorDiff=missing_reference"],
        }

    sub_in = [x for x in (subject.get("inputFunctions") or []) if isinstance(x, dict)]
    ref_in = [x for x in (reference.get("inputFunctions") or []) if isinstance(x, dict)]

    # Prefer full function inventories for matching when available
    match_blob = None
    if subject_fns and reference_fns:
        match_blob = match_functions(subject_fns, reference_fns)

    pairs: list[dict[str, Any]] = []
    identical = changed = added = removed = unmatched = 0

    used_ref: set[str] = set()
    ref_by_fp = {str(r.get("fingerprint") or ""): r for r in ref_in if r.get("fingerprint")}
    ref_by_name = {
        str(r.get("name") or ""): r
        for r in ref_in
        if r.get("name") and not is_generic_name(str(r.get("name")))
    }

    # Build address map from intelligent matcher if present
    addr_map: dict[str, str] = {}
    if match_blob:
        for m in match_blob.get("matches") or []:
            if m.get("subject") and m.get("reference") and m.get("matchConfidence") in {
                "HIGH",
                "MEDIUM",
                "LOW",
            }:
                sa = str((m["subject"] or {}).get("address") or "")
                ra = str((m["reference"] or {}).get("address") or "")
                if sa and ra:
                    addr_map[sa] = ra

    for s in sub_in:
        ref = None
        method = None
        sa = str(s.get("address") or "")
        if sa and sa in addr_map:
            ra = addr_map[sa]
            ref = next((r for r in ref_in if str(r.get("address")) == ra), None)
            method = "function_matcher"
        if ref is None:
            fp = str(s.get("fingerprint") or "")
            if fp and fp in ref_by_fp:
                ref = ref_by_fp[fp]
                method = "fingerprint"
        if ref is None:
            name = str(s.get("name") or "")
            if name and name in ref_by_name:
                ref = ref_by_name[name]
                method = "name"
        if ref is None:
            pairs.append(
                {
                    "status": "HINZUGEFUEGT",
                    "subject": s,
                    "reference": None,
                    "matchMethod": None,
                    "evidenceTier": s.get("evidenceTier"),
                    "notes": "Eingabebezogene Funktion nur im Subject.",
                }
            )
            added += 1
            continue
        used_ref.add(str(ref.get("address") or ref.get("fingerprint") or ref.get("name")))
        same_cats = set(s.get("categories") or []) == set(ref.get("categories") or [])
        same_tier = s.get("evidenceTier") == ref.get("evidenceTier")
        if same_cats and same_tier and s.get("fingerprint") == ref.get("fingerprint"):
            status = "IDENTISCH"
            identical += 1
        else:
            status = "STRUKTURELL_VERAENDERT"
            changed += 1
        pairs.append(
            {
                "status": status,
                "subject": s,
                "reference": ref,
                "matchMethod": method,
                "evidenceTier": s.get("evidenceTier"),
                "notes": "Struktureller Input-Vergleich — kein Verhaltensnachweis.",
            }
        )

    for r in ref_in:
        key = str(r.get("address") or r.get("fingerprint") or r.get("name"))
        if key in used_ref:
            continue
        pairs.append(
            {
                "status": "ENTFERNT",
                "subject": None,
                "reference": r,
                "matchMethod": None,
                "evidenceTier": r.get("evidenceTier"),
                "notes": "Eingabebezogene Funktion nur in Referenz.",
            }
        )
        removed += 1

    # State machine structural diff (counts only)
    ss = (subject.get("stateMachineAnalysis") or {}).get("stateMachineCount") or 0
    rs = (reference.get("stateMachineAnalysis") or {}).get("stateMachineCount") or 0
    sm_diff = {
        "subjectStateMachines": ss,
        "referenceStateMachines": rs,
        "delta": int(ss) - int(rs),
        "notes": "Nur Anzahl/Struktur — keine semantische FSM-Äquivalenz.",
    }

    return {
        "ok": True,
        "schemaVersion": 1,
        "tool": "input-behavior-diff",
        "summary": {
            "identical": identical,
            "structurallyChanged": changed,
            "added": added,
            "removed": removed,
            "unmatched": unmatched,
            "subjectInputCount": len(sub_in),
            "referenceInputCount": len(ref_in),
        },
        "pairs": pairs[:80],
        "stateMachineDiff": sm_diff,
        "analysisLimitations": limitations,
        "notes": [
            f"inputBehaviorDiff=ok identical={identical} changed={changed} "
            f"added={added} removed={removed}"
        ],
        "evidenceTier": EVIDENCE_INDICATIVE,
    }


def summarize_input_behavior_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    fns = list(full.get("inputFunctions") or [])[:24]
    sm = full.get("stateMachineAnalysis") or {}
    sm_poll = {
        "ok": sm.get("ok"),
        "stateMachineCount": sm.get("stateMachineCount"),
        # May be null — clients must not invent placeholders.
        "totalEstimatedStates": sm.get("totalEstimatedStates"),
        "totalEstimatedTransitions": sm.get("totalEstimatedTransitions"),
        "candidateCount": sm.get("candidateCount"),
        "structureIdentifiedCount": sm.get("structureIdentifiedCount"),
        "transitionsIdentifiedCount": sm.get("transitionsIdentifiedCount"),
        "stateMachineValidation": sm.get("stateMachineValidation"),
        "evidenceTier": sm.get("evidenceTier"),
        "sampleStateMachines": list(sm.get("stateMachines") or [])[:8],
        "analysisLimitations": sm.get("analysisLimitations"),
        "notes": sm.get("notes"),
    }
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "tool": full.get("tool"),
        "toolNote": full.get("toolNote"),
        "summary": full.get("summary") or {},
        "categories": full.get("categories") or {},
        "sampleInputFunctions": fns,
        "stateMachineAnalysis": sm_poll,
        "evidenceTier": full.get("evidenceTier"),
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "notes": list(full.get("notes") or []),
    }


def summarize_input_diff_for_poll(full: dict[str, Any]) -> dict[str, Any]:
    pairs = list(full.get("pairs") or [])
    interesting = [p for p in pairs if p.get("status") != "IDENTISCH"]
    return {
        "ok": bool(full.get("ok")),
        "schemaVersion": full.get("schemaVersion", 1),
        "tool": full.get("tool"),
        "summary": full.get("summary") or {},
        "samplePairs": (interesting or pairs)[:24],
        "stateMachineDiff": full.get("stateMachineDiff"),
        "evidenceTier": full.get("evidenceTier"),
        "analysisLimitations": list(full.get("analysisLimitations") or []),
        "notes": list(full.get("notes") or []),
    }


def _fns(blob: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not blob:
        return []
    return [f for f in (blob.get("functions") or []) if isinstance(f, dict)]


def _tier_rank(tier: str | None) -> int:
    return {
        EVIDENCE_CONFIRMED: 0,
        EVIDENCE_CONFIRMED_LEGACY: 0,
        EVIDENCE_INDICATIVE: 1,
        EVIDENCE_SPECULATIVE: 2,
        EVIDENCE_UNKNOWN: 3,
    }.get(tier or "", 9)


def _overall_tier(input_fns: list[dict[str, Any]], state: dict[str, Any]) -> str:
    tiers = {x.get("evidenceTier") for x in input_fns}
    if EVIDENCE_CONFIRMED in tiers or EVIDENCE_CONFIRMED_LEGACY in tiers:
        return EVIDENCE_CONFIRMED
    if EVIDENCE_INDICATIVE in tiers:
        return EVIDENCE_INDICATIVE
    if state.get("evidenceTier") == EVIDENCE_INDICATIVE:
        return EVIDENCE_INDICATIVE
    if not input_fns and not (state.get("stateMachines") or []):
        return EVIDENCE_UNKNOWN
    return EVIDENCE_SPECULATIVE
