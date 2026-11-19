"""Phase 2.3.2 — unified ground truth, provenance, truncation, detection metrics."""
from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest import mock

import activation_forensics as af
from semantic_dataflow import analyze_semantic_dataflow, load_dataflow_export

ROOT = Path(__file__).resolve().parent
TD = ROOT / "testdata" / "phase232" / "fixtures"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _gt_cases(gt: dict, *, variant: str) -> list[dict]:
    addr_key = "addressD" if variant == "D_shifted" else "addressA"
    return [
        {"address": c[addr_key], "expectDetect": c["expectDetect"], "id": c["id"]}
        for c in gt["cases"]
    ]


class Phase232ValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gt = _load(TD / "ground_truth.json")
        cls.variants = {
            "A_named": _load(TD / "A_named.functions.json"),
            "B_generic": _load(TD / "B_generic.functions.json"),
            "C_no_strings": _load(TD / "C_no_strings.functions.json"),
            "D_shifted": _load(TD / "D_shifted.functions.json"),
            "E_anon_meta": _load(TD / "E_anon_meta.functions.json"),
        }

    def _run(self, export: dict, **kwargs) -> dict:
        return af.run_activation_forensics(export, reference_trust="communityLibrary", **kwargs)

    def test_unified_ground_truth_counts(self) -> None:
        pos = self.gt["expectCounts"]["positives"]
        neg = self.gt["expectCounts"]["negatives"]
        for name in self.variants:
            cases = _gt_cases(self.gt, variant=name if name == "D_shifted" else "A_named")
            if name == "D_shifted":
                cases = _gt_cases(self.gt, variant="D_shifted")
            self.assertEqual(sum(1 for c in cases if c["expectDetect"]), pos, name)
            self.assertEqual(sum(1 for c in cases if not c["expectDetect"]), neg, name)

    def test_metrics_tn_f1_across_variants(self) -> None:
        expect_pos = self.gt["expectCounts"]["positives"]
        for name, export in self.variants.items():
            r = self._run(export)
            cases = _gt_cases(self.gt, variant="D_shifted" if name == "D_shifted" else "A_named")
            m = af.evaluate_detection_quality(r["inputHandlerFindings"], cases)
            self.assertIn("trueNegatives", m)
            self.assertIn("f1Score", m)
            self.assertIn("disclaimer", m)
            self.assertGreaterEqual(m["truePositives"], 1, name)
            # A should retain majority of expected positives
            if name == "A_named":
                self.assertGreaterEqual(m["truePositives"], max(5, expect_pos // 2), name)
            if m["f1Score"] is not None:
                self.assertGreater(m["f1Score"], 0.0)

    def test_truncation_fields_when_over_limit(self) -> None:
        export = self.variants["A_named"]
        with mock.patch.object(af, "MAX_HANDLERS", 3):
            r = self._run(export)
        limits = r.get("resultLimits") or {}
        hlim = limits.get("handlers") or {}
        self.assertGreater(hlim.get("totalCandidatesDetected", 0), hlim.get("returnedCandidates", 0))
        self.assertTrue(hlim.get("resultTruncated"))
        self.assertEqual(hlim.get("truncationReason"), "MAX_HANDLERS")
        self.assertIn("configuredLimit", hlim)
        poll = af.summarize_activation_forensics_for_poll(r)
        self.assertIn("resultLimits", poll)

    def test_semantic_provenance_summary(self) -> None:
        dataflow = load_dataflow_export(TD / "A_named.dataflow.json")
        sdf = analyze_semantic_dataflow(self.variants["A_named"], dataflow_export=dataflow)
        s = sdf.get("summary") or {}
        for key in (
            "totalFunctions",
            "exportedFunctions",
            "derivedFunctions",
            "partialFunctions",
            "unavailableFunctions",
            "dataflowCoveragePercent",
            "provenanceCounts",
        ):
            self.assertIn(key, s)
        self.assertGreater(s["exportedFunctions"], 0)
        self.assertAlmostEqual(
            s["dataflowCoveragePercent"],
            s["exportedFunctions"] / s["totalFunctions"] * 100.0,
            places=6,
        )
        r = self._run(self.variants["A_named"], dataflow_export=dataflow)
        sem = r.get("semanticDataFlowSummary") or {}
        self.assertIn("provenanceCounts", sem)
        self.assertIn("dataflowCoveragePercent", sem)

    def test_structural_only_speculative_without_ghidra(self) -> None:
        r = self._run(self.variants["B_generic"])
        structural = [
            h for h in r["inputHandlerFindings"] if h.get("structuralOnly") or "structural_multi_signal" in (h.get("detectionMethods") or [])
        ]
        for h in structural:
            if h.get("dataflowProvenance") != af.PROVENANCE_GHIDRA:
                self.assertEqual(h.get("evidenceTier"), af.SPECULATIVE)

    def test_bad_missing_dataflow_still_ok(self) -> None:
        bad = load_dataflow_export(TD / "H_bad_dataflow.json")
        sdf = analyze_semantic_dataflow(
            _load(TD / "G_missing_dataflow.functions.json"),
            dataflow_export=bad if bad.get("ok") else {"ok": False, "functions": []},
        )
        self.assertIn("ok", sdf)
        r = self._run(self.variants["E_anon_meta"])
        self.assertTrue(r["ok"])


if __name__ == "__main__":
    unittest.main()