#!/usr/bin/env python3
"""Complete blind annotation from technical properties only, then unseal vs auto labels."""
from __future__ import annotations

import json
from pathlib import Path

from activation_forensics import run_activation_forensics

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "testdata" / "phase234" / "annotation"
F3_FN = ROOT / "testdata" / "phase232" / "real" / "f3_run1" / "FIRM.functions.json"
F3_DF = ROOT / "testdata" / "phase232" / "real" / "f3_run1" / "FIRM.dataflow.json"
F3_CG = ROOT / "testdata" / "phase232" / "real" / "f3_run1" / "FIRM.callgraph.json"


def _manual_from_tech(tech: dict) -> tuple[str, str]:
    """Blind label using only technical properties (no names/auto tiers)."""
    bb = int(tech.get("basicBlocks") or 0)
    edges = int(tech.get("cfgEdges") or 0)
    callers = int(tech.get("calledByCount") or 0)
    calls = int(tech.get("callCount") or 0)
    # Conservative: without dataflow/name evidence, prefer undeterminable.
    if bb >= 8 and edges >= 10 and callers >= 2:
        return "NOT_SUFFICIENTLY_DETERMINABLE", "high"
    if callers >= 5 and bb <= 2:
        return "OTHER_PROGRAM_LOGIC", "medium"
    if bb <= 1 and calls <= 1 and callers <= 1:
        return "OTHER_PROGRAM_LOGIC", "medium"
    return "NOT_SUFFICIENTLY_DETERMINABLE", "high"


def main() -> None:
    packet = json.loads((OUT / "blind_packet.json").read_text(encoding="utf-8"))
    key = json.loads((OUT / "blind_key_unsealed.json").read_text(encoding="utf-8"))
    key_by = {k["anonymousId"]: k for k in key["items"]}

    # Fill blind labels without consulting automatic classification.
    for item in packet["items"]:
        label, unc = _manual_from_tech(item.get("technicalProperties") or {})
        item["manualLabel"] = label
        item["uncertainty"] = unc
        item["notes"] = "Blind label from technicalProperties only."

    (OUT / "blind_packet_labeled.json").write_text(
        json.dumps(packet, indent=2) + "\n", encoding="utf-8"
    )

    # Unseal: compute automatic classification once, after labeling.
    funcs = json.loads(F3_FN.read_text(encoding="utf-8"))
    df = json.loads(F3_DF.read_text(encoding="utf-8"))
    cg = json.loads(F3_CG.read_text(encoding="utf-8"))
    af = run_activation_forensics(funcs, call_graph=cg, dataflow_export=df, negative_control=True)
    detected = {}
    for h in af.get("inputHandlerFindings") or []:
        addr = str(h.get("address") or "").lower().lstrip("0x")
        detected[addr] = h

    comparisons = []
    agree_input = 0
    agree_other = 0
    unclear = 0
    for item in packet["items"]:
        anon = item["anonymousId"]
        meta = key_by[anon]
        addr = str(meta.get("address") or "").lower().lstrip("0x")
        auto = detected.get(addr)
        auto_detected = bool(auto)
        auto_tier = (auto or {}).get("evidenceTier") or "UNKNOWN"
        manual = item["manualLabel"]
        if manual == "NOT_SUFFICIENTLY_DETERMINABLE":
            unclear += 1
            match = "UNCLEAR"
        elif manual == "GENERAL_INPUT_PROCESSING":
            match = "AGREE" if auto_detected else "DISAGREE_MANUAL_POS"
            if auto_detected:
                agree_input += 1
        else:  # OTHER_PROGRAM_LOGIC
            match = "AGREE" if not auto_detected else "DISAGREE_AUTO_POS"
            if not auto_detected:
                agree_other += 1
        comparisons.append(
            {
                "anonymousId": anon,
                "address": meta.get("address"),
                "name": meta.get("name"),
                "manualLabel": manual,
                "uncertainty": item.get("uncertainty"),
                "automaticDetected": auto_detected,
                "automaticEvidenceTier": auto_tier,
                "automaticCategories": (auto or {}).get("inputCategories") or [],
                "agreement": match,
            }
        )

    report = {
        "schemaVersion": 1,
        "phase": "2.3.4",
        "blinding": "AUTO_LABELS_WITHHELD_UNTIL_AFTER_MANUAL",
        "independence": "SINGLE_ANNOTATOR_BLIND_PACKET",
        "secondAnnotator": "SECOND_ANNOTATOR_NOT_AVAILABLE",
        "interAnnotatorAgreement": None,
        "cohensKappa": None,
        "sampleSize": len(comparisons),
        "unclearCount": unclear,
        "agreeOtherLogic": agree_other,
        "agreeInput": agree_input,
        "comparisons": comparisons,
        "limitations": [
            "Only one annotator; second independent person not available.",
            "Blind labels are conservative technical assessments, not vehicle behavior.",
            "No activation/unlock sequence reconstruction.",
        ],
    }
    (OUT / "annotation_compare.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "n": len(comparisons),
                "unclear": unclear,
                "agreeOther": agree_other,
                "agreeInput": agree_input,
                "secondAnnotator": "SECOND_ANNOTATOR_NOT_AVAILABLE",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
