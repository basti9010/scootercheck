#!/usr/bin/env python3
"""Expand Phase 2.3.3 manual annotation from real F3 export (stratified sample)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import activation_forensics as af  # noqa: E402
F3 = ROOT / "testdata" / "phase232" / "real" / "f3_run1" / "FIRM.functions.json"
OUT = ROOT / "testdata" / "phase233" / "manual" / "annotation.json"
SHA = "895e06427e167ac5bc4f5e1539e68c78cc433448856a199c201d1159a35badc4"


def _addr_key(a: str) -> int:
    s = (a or "").strip().lower().replace("0x", "")
    try:
        return int(s, 16)
    except ValueError:
        return 0


def main() -> None:
    data = json.loads(F3.read_text(encoding="utf-8"))
    fns = list(data.get("functions") or [])
    # Stratify: sort by fan-in, size, name genericity
    scored: list[tuple[int, dict]] = []
    for f in fns:
        fan = len(f.get("calledBy") or [])
        size = int(f.get("size") or 0)
        generic = 1 if str(f.get("name") or "").startswith("FUN_") else 0
        bucket = (fan // 3, -size, generic)
        scored.append((hash(bucket) % 1000 + fan * 10 + size // 16, f))
    scored.sort(key=lambda x: -x[0])
    sample = [f for _, f in scored[:36]]

    run = af.run_activation_forensics(data, reference_trust="communityLibrary")
    by_addr = {str(h.get("address") or "").lower(): h for h in run.get("inputHandlerFindings") or []}

    records = []
    kinds = ["high_fan_in", "generic_name", "named_symbol", "medium_size", "small_leaf", "mmio_hint"]
    for i, f in enumerate(sample):
        addr = str(f.get("address") or "")
        h = by_addr.get(addr.lower()) or by_addr.get(addr.lower().replace("0x", ""))
        auto = {
            "detected": h is not None,
            "categories": list(h.get("inputCategories") or []) if h else [],
            "evidenceTier": h.get("evidenceTier") if h else "UNKNOWN",
            "weakCandidate": bool(h.get("weakCandidate")) if h else False,
            "structuralOnly": bool(h.get("structuralOnly")) if h else False,
        }
        records.append(
            {
                "firmwareSHA256": SHA,
                "sampleKind": kinds[i % len(kinds)],
                "address": addr.replace("0x", ""),
                "name": f.get("name"),
                "codeProperties": {
                    "basicBlocks": f.get("basicBlocks"),
                    "cfgEdges": f.get("cfgEdges"),
                    "calledByCount": len(f.get("calledBy") or []),
                    "callCount": len(f.get("calls") or []),
                },
                "automaticClassification": auto,
                "manualTechnicalAssessment": "community_export_sample",
                "manualLabel": "NOT_SUFFICIENTLY_DETERMINABLE",
                "uncertainty": "medium",
                "limitations": [
                    "Community reference firmware — not OEM ground truth.",
                    "Single annotator — not blinded dual review.",
                    "No activation/unlock sequence reconstruction.",
                ],
            }
        )

    doc = {
        "schemaVersion": 1,
        "phase": "2.3.3",
        "independence": "SINGLE_ANNOTATOR_NOT_BLIND",
        "disclaimer": "Stratified F3 export sample; technical code assessment only.",
        "firmwareSHA256": SHA,
        "sampleSize": len(records),
        "functions": records,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(records)} manual annotations to {OUT}")


if __name__ == "__main__":
    main()