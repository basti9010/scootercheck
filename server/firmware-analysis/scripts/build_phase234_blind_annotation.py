#!/usr/bin/env python3
"""Build blinded annotation packet from F3 export (no auto labels in packet)."""
from __future__ import annotations

import hashlib
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
F3_FN = ROOT / "testdata" / "phase232" / "real" / "f3_run1" / "FIRM.functions.json"
F3_SHA = "895e06427e167ac5bc4f5e1539e68c78cc433448856a199c201d1159a35badc4"
OUT = ROOT / "testdata" / "phase234" / "annotation"


def _tech(fn: dict) -> dict:
    return {
        "basicBlocks": fn.get("basicBlocks"),
        "cfgEdges": fn.get("cfgEdges"),
        "size": fn.get("size"),
        "callCount": len(fn.get("calls") or []) if isinstance(fn.get("calls"), list) else fn.get("callCount"),
        "calledByCount": len(fn.get("calledBy") or [])
        if isinstance(fn.get("calledBy"), list)
        else fn.get("calledByCount"),
        "hasStrings": bool(fn.get("strings")),
        "hasConstants": bool(fn.get("constants")),
        "mnemonicCount": len(fn.get("mnemonics") or []) if isinstance(fn.get("mnemonics"), list) else None,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    payload = json.loads(F3_FN.read_text(encoding="utf-8"))
    funcs = payload.get("functions") or []
    # Stratified-ish sample by size buckets
    buckets = {"small": [], "medium": [], "large": [], "complex": []}
    for f in funcs:
        bb = int(f.get("basicBlocks") or 0)
        sz = int(f.get("size") or 0)
        if bb >= 12 or sz >= 200:
            buckets["complex"].append(f)
        elif bb >= 6:
            buckets["large"].append(f)
        elif bb >= 3:
            buckets["medium"].append(f)
        else:
            buckets["small"].append(f)

    rng = random.Random(234001)
    sample: list[dict] = []
    for key, take in (("complex", 8), ("large", 8), ("medium", 8), ("small", 8)):
        pool = list(buckets[key])
        rng.shuffle(pool)
        sample.extend(pool[:take])
    rng.shuffle(sample)
    sample = sample[:32]

    blinded = []
    key_map = []
    for i, f in enumerate(sample):
        anon_id = f"ANN_{i:02d}_{hashlib.sha256(str(f.get('address')).encode()).hexdigest()[:8]}"
        blinded.append(
            {
                "anonymousId": anon_id,
                "firmwareSHA256": F3_SHA,
                "technicalProperties": _tech(f),
                "manualLabel": None,
                "uncertainty": None,
                "notes": None,
                "allowedLabels": [
                    "GENERAL_INPUT_PROCESSING",
                    "OTHER_PROGRAM_LOGIC",
                    "NOT_SUFFICIENTLY_DETERMINABLE",
                ],
            }
        )
        key_map.append(
            {
                "anonymousId": anon_id,
                "address": f.get("address"),
                "name": f.get("name"),
                # Auto classification filled AFTER blind labeling, in compare step.
                "automaticClassification": None,
            }
        )

    packet = {
        "schemaVersion": 1,
        "phase": "2.3.4",
        "blinding": "AUTO_LABELS_WITHHELD",
        "independence": "SINGLE_ANNOTATOR_BLIND_PACKET",
        "secondAnnotator": "SECOND_ANNOTATOR_NOT_AVAILABLE",
        "firmwareSHA256": F3_SHA,
        "sampleSize": len(blinded),
        "instructions": [
            "Label each item using only technicalProperties.",
            "Do not use function names or automatic classifications (withheld).",
            "Prefer NOT_SUFFICIENTLY_DETERMINABLE when uncertain.",
        ],
        "items": blinded,
    }
    (OUT / "blind_packet.json").write_text(json.dumps(packet, indent=2) + "\n", encoding="utf-8")
    (OUT / "blind_key_unsealed.json").write_text(json.dumps({"items": key_map}, indent=2) + "\n", encoding="utf-8")
    print("wrote", OUT / "blind_packet.json", "n=", len(blinded))


if __name__ == "__main__":
    main()
