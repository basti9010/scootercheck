"""Phase 2.3.3 — controlled Ghidra export ground truth (synthetic)."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from semantic_dataflow import analyze_semantic_dataflow, load_dataflow_export

ROOT = Path(__file__).resolve().parent
GT_DIR = ROOT / "testdata" / "phase233" / "ghidra_export_gt"


def _load(name: str) -> dict:
    return json.loads((GT_DIR / name).read_text(encoding="utf-8"))


class Phase233GhidraExportGtTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gt = _load("ground_truth.json")
        cls.fns = _load("synthetic_functions.json")
        cls.df = load_dataflow_export(GT_DIR / "synthetic_dataflow.json")

    def test_synthetic_export_vs_ground_truth(self) -> None:
        sdf = analyze_semantic_dataflow(self.fns, dataflow_export=self.df)
        by_addr = {str(r.get("address")): r for r in sdf.get("functions") or []}
        stats = {"correct": 0, "missing": 0, "wrong": 0, "unknown": 0}
        for spec in self.gt["functions"]:
            addr = spec["address"]
            exp = spec["expect"]
            row = by_addr.get(addr)
            if not row:
                stats["missing"] += 1
                continue
            mismatches = []
            for key in ("parameterCount", "memoryReads", "memoryWrites", "callCount", "conditionalBranches"):
                if exp.get(key) != row.get(key):
                    mismatches.append(key)
            if exp.get("quality") and str(exp.get("quality")) != str(row.get("quality")):
                mismatches.append("quality")
            if mismatches:
                stats["wrong"] += 1
            else:
                stats["correct"] += 1
            if row.get("parameterCount") is None and exp.get("parameterCount") is None:
                stats["unknown"] += 0  # expected unknown signature
        self.assertEqual(len(self.gt["functions"]), 10)
        self.assertGreaterEqual(stats["correct"], 7, stats)
        self.assertLessEqual(stats["wrong"], 3, stats)

    def test_dataflow_field_presence(self) -> None:
        sdf = analyze_semantic_dataflow(self.fns, dataflow_export=self.df)
        qm = (sdf.get("summary") or {}).get("dataflowQualityMetrics") or {}
        for key in (
            "dataflowExportCoverage",
            "parameterRecoveryCoverage",
            "memoryAccessCoverage",
            "dataReferenceCoverage",
            "unresolvedDataflowCount",
            "semanticConfidenceDistribution",
        ):
            self.assertIn(key, qm, key)


if __name__ == "__main__":
    unittest.main()