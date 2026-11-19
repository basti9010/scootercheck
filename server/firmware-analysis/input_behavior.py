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
    "gpio_event": ("gpio", "pin", "exti", "port_", "irq_gpio", "hal_gpio"),
    "ble_message": ("ble", "bluetooth", "gatt", "nordic", "nus", "att_"),
    "uart_or_comm": ("uart", "usart", "can_", "spi_", "i2c_", " comm", "rx_", "tx_"),
    "event_queue": ("queue", "event", "msg_", "mailbox", "dispatch", "handler"),
    "state_update": ("state", "mode", "fsm", "transition", "status_set", "set_state"),
    "input_callback": ("callback", "on_input", "process_input", "input_", "handle_input"),
}

STRING_HINTS: dict[str, tuple[str, ...]] = {
    "button_or_key": ("button", "key", "press", "btn"),
    "gpio_event": ("gpio", "exti", "pin"),
    "ble_message": ("ble", "gatt", "bluetooth"),
    "uart_or_comm": ("uart", "usart", "rx", "tx"),
    "event_queue": ("event", "queue", "msg"),
    "state_update": ("state", "mode", "fsm"),
}

EVIDENCE_CONFIRMED = "confirmed"  # ≥2 independent signal classes
EVIDENCE_INDICATIVE = "indicative"  # single strong structural/name signal
EVIDENCE_SPECULATIVE = "speculative"  # weak single hint

MAX_FUNCTIONS = 2500
MAX_INPUT_FUNCS = 80
MAX_STATE_MACHINES = 12


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

    notes = [
        f"inputBehavior=ok relevant={len(input_fns)} cats="
        + ",".join(f"{k}:{v}" for k, v in categories.items() if v)
    ]
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
            "inputRelevantCount": len(input_fns),
            "confirmedCount": sum(1 for x in input_fns if x.get("evidenceTier") == EVIDENCE_CONFIRMED),
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
    name = str(f.get("name") or "")
    name_l = name.lower()
    strings = [str(s).lower() for s in (f.get("strings") or [])]
    constants = [str(c).lower() for c in (f.get("constants") or [])]
    calls = [str(c).lower() for c in (f.get("calls") or [])]
    called_by = [str(c).lower() for c in (f.get("calledBy") or [])]
    blocks = int(f.get("basicBlocks") or 0)
    edges = int(f.get("cfgEdges") or 0)

    hits: dict[str, list[str]] = {}
    signal_classes: set[str] = set()

    # Name signals
    for cat, keys in CATEGORY_HINTS.items():
        if any(k in name_l for k in keys):
            hits.setdefault(cat, []).append(f"name:{name}")
            signal_classes.add("name")

    # String signals (need ≥1, but alone insufficient for confirmed)
    for cat, keys in STRING_HINTS.items():
        for s in strings:
            if any(k in s for k in keys):
                hits.setdefault(cat, []).append(f"string:{s[:48]}")
                signal_classes.add("string")
                break

    # Call-graph neighborhood soft hints
    neigh = " ".join(calls + called_by)
    for cat, keys in CATEGORY_HINTS.items():
        if any(k in neigh for k in keys):
            hits.setdefault(cat, []).append("call_neighborhood")
            signal_classes.add("calls")

    # Structural: dense branching often accompanies input/dispatch
    structural = False
    if blocks >= 3 and edges >= blocks:
        structural = True
        signal_classes.add("cfg")
        if "input_callback" not in hits and (
            "process" in name_l or "handle" in name_l or "dispatch" in name_l or "input" in name_l
        ):
            hits.setdefault("input_callback", []).append("cfg_dense+name")
        elif "event_queue" not in hits and edges >= blocks + 2:
            # weak — only keep if another signal exists later
            hits.setdefault("event_queue", []).append("cfg_dense")

    if not hits:
        return None

    # Single string OR single weak cfg-only → drop (insufficient)
    cats = list(hits.keys())
    only_string = signal_classes == {"string"}
    only_weak_cfg = signal_classes == {"cfg"} and all(
        e.startswith("cfg_dense") and "name" not in "|".join(v) for v in hits.values() for e in [v[0]]
    )
    if only_string or only_weak_cfg:
        return None

    # Evidence tier
    if len(signal_classes) >= 2 and any(c in signal_classes for c in ("name", "calls", "cfg")):
        tier = EVIDENCE_CONFIRMED
    elif "name" in signal_classes or ("cfg" in signal_classes and "calls" in signal_classes):
        tier = EVIDENCE_INDICATIVE
    else:
        tier = EVIDENCE_SPECULATIVE

    # Score
    score = 0.35 * len(signal_classes) + 0.15 * min(3, len(cats))
    if structural:
        score += 0.1
    if not is_generic_name(name):
        score += 0.15

    evidence = []
    for cat, items in hits.items():
        evidence.extend(items[:3])

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
            "Heuristik — kein Nachweis, dass diese Funktion reale Eingaben verarbeitet."
        ],
    }


def analyze_state_machines(
    all_fns: list[dict[str, Any]],
    input_fns: list[dict[str, Any]],
) -> dict[str, Any]:
    """Detect switch-/branch-heavy functions as candidate FSMs (technical structure only)."""
    limitations = [
        "Zustandsautomaten sind strukturelle Hypothesen aus CFG-Mustern.",
        "Anzahl Zustände/Übergänge ist geschätzt, nicht dynamisch verifiziert.",
    ]
    machines: list[dict[str, Any]] = []
    input_addrs = {x.get("address") for x in input_fns}

    for f in all_fns[:MAX_FUNCTIONS]:
        blocks = int(f.get("basicBlocks") or 0)
        edges = int(f.get("cfgEdges") or 0)
        mnemonics = [str(m).lower() for m in (f.get("mnemonics") or [])]
        branchy = sum(1 for m in mnemonics if m.startswith(("b", "cbz", "cbnz", "tbz", "tbnz", "it")))
        # Switch-like: several blocks, edges ≈ or > blocks, some branches
        if blocks < 3 or edges < 3:
            continue
        density = edges / max(blocks, 1)
        if density < 1.1 and branchy < 2:
            continue

        # Estimate states/transitions conservatively
        est_states = max(2, min(blocks, 16))
        est_trans = max(1, min(edges, 32))
        related_input = f.get("address") in input_addrs or any(
            "state" in str(f.get("name") or "").lower()
            or "mode" in str(f.get("name") or "").lower()
            or "fsm" in str(f.get("name") or "").lower()
            or "process_input" in str(f.get("name") or "").lower()
            for _ in [0]
        )
        quality = "indicative" if related_input and density >= 1.2 else "speculative"
        if related_input and branchy >= 3 and density >= 1.3:
            quality = "indicative"

        machines.append(
            {
                "functionAddress": f.get("address"),
                "functionName": f.get("name"),
                "estimatedStates": est_states,
                "estimatedTransitions": est_trans,
                "basicBlocks": blocks,
                "cfgEdges": edges,
                "branchMnemonicCount": branchy,
                "edgeDensity": round(density, 3),
                "linkedToInputHeuristic": bool(related_input),
                "analysisQuality": quality,
                "evidence": [
                    f"cfg blocks={blocks} edges={edges}",
                    f"branchMnemonics={branchy}",
                ],
                "uncertainty": (
                    "Zustandszahl aus Basisblöcken geschätzt; "
                    "keine Laufzeitverifikation der Übergänge."
                ),
                "limitations": [
                    "Keine konkreten Aktivierungsfolgen abgeleitet.",
                ],
            }
        )

    machines.sort(
        key=lambda m: (
            0 if m.get("analysisQuality") == "indicative" else 1,
            -float(m.get("edgeDensity") or 0),
        )
    )
    machines = machines[:MAX_STATE_MACHINES]

    return {
        "ok": True,
        "schemaVersion": 1,
        "stateMachineCount": len(machines),
        "totalEstimatedStates": sum(int(m.get("estimatedStates") or 0) for m in machines),
        "totalEstimatedTransitions": sum(int(m.get("estimatedTransitions") or 0) for m in machines),
        "stateMachines": machines,
        "analysisLimitations": limitations,
        "notes": [f"stateMachines={len(machines)}"],
        "evidenceTier": (
            EVIDENCE_INDICATIVE
            if any(m.get("analysisQuality") == "indicative" for m in machines)
            else EVIDENCE_SPECULATIVE
        ),
    }


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
        "totalEstimatedStates": sm.get("totalEstimatedStates"),
        "totalEstimatedTransitions": sm.get("totalEstimatedTransitions"),
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
        EVIDENCE_INDICATIVE: 1,
        EVIDENCE_SPECULATIVE: 2,
    }.get(tier or "", 9)


def _overall_tier(input_fns: list[dict[str, Any]], state: dict[str, Any]) -> str:
    if any(x.get("evidenceTier") == EVIDENCE_CONFIRMED for x in input_fns):
        return EVIDENCE_CONFIRMED
    if any(x.get("evidenceTier") == EVIDENCE_INDICATIVE for x in input_fns):
        return EVIDENCE_INDICATIVE
    if state.get("evidenceTier") == EVIDENCE_INDICATIVE:
        return EVIDENCE_INDICATIVE
    return EVIDENCE_SPECULATIVE
