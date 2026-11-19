#!/usr/bin/env python3
"""Recompute Phase 2.3.4 parameter GT metrics with separated exact vs accepted rates."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GT_DIR = ROOT / "testdata" / "phase234" / "param_gt"


def main() -> None:
    gt = json.loads((GT_DIR / "ground_truth.json").read_text(encoding="utf-8"))
    df = json.loads((GT_DIR / "out" / "param_gt.dataflow.json").read_text(encoding="utf-8"))
    rows = sorted(
        [f for f in (df.get("functions") or []) if f.get("name") != "reset_handler"],
        key=lambda x: int(str(x.get("address") or "0"), 16),
    )
    specs = list(gt.get("functions") or [])
    exact = 0
    accepted = 0
    unknown = 0
    partial = 0
    wrong = 0
    missing = 0
    details = []
    for i, spec in enumerate(specs):
        if i >= len(rows):
            missing += 1
            details.append({"id": spec["id"], "status": "MISSING"})
            continue
        row = rows[i]
        got = row.get("parameterCount")
        quality = row.get("parameterQuality") or "UNKNOWN_PARAMETER_COUNT"
        exp = spec["expectedParameterCount"]
        allow = bool(spec.get("allowUnknown"))
        if quality == "PARTIAL_SIGNATURE":
            partial += 1
        if got is None:
            unknown += 1
            status = "UNKNOWN"
            if allow:
                accepted += 1
                status = "UNKNOWN_ACCEPTED"
        elif int(got) == int(exp):
            exact += 1
            accepted += 1
            status = "EXACT"
        else:
            wrong += 1
            status = "WRONG"
            if allow:
                accepted += 1
                status = "WRONG_ACCEPTED_AMBIGUOUS"
        details.append(
            {
                "id": spec["id"],
                "name": spec.get("logicalName"),
                "ghidraName": row.get("name"),
                "address": row.get("address"),
                "expected": exp,
                "got": got,
                "quality": quality,
                "status": status,
            }
        )
    n = len(specs) or 1
    report = {
        "phase": "2.3.4-final",
        "functionExportCount": len(df.get("functions") or []),
        "evaluatedCases": len(specs),
        "exactParameterAccuracy": exact / n * 100.0,
        "acceptedOrAmbiguousRate": accepted / n * 100.0,
        # Legacy alias must track exact accuracy (never inflate past exact).
        "recoveryAccuracyPercent": exact / n * 100.0,
        "unknownParameterRate": unknown / n * 100.0,
        "partialSignatureRate": partial / n * 100.0,
        "recoveredParameterCoverage": sum(
            1
            for d in details
            if d.get("got") is not None
            and d.get("quality") in ("RECOVERED_PARAMETER_COUNT", "CONFIRMED_ZERO_PARAMETERS", "PARTIAL_SIGNATURE")
        )
        / n
        * 100.0,
        "exactCount": exact,
        "acceptedCount": accepted,
        "wrongCount": wrong,
        "unknownCount": unknown,
        "partialCount": partial,
        "missingCount": missing,
        "note": (
            "exactParameterAccuracy counts only exact matches. "
            "acceptedOrAmbiguousRate may include documented allowUnknown cases. "
            "Do not equate accepted rate with exact accuracy."
        ),
        "details": details,
    }
    out = GT_DIR / "out" / "param_gt_report.json"
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in report if k != "details"}, indent=2))


if __name__ == "__main__":
    main()
