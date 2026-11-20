"""Phase 2.3.4 — parameter quality metrics & controlled GT report."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from semantic_dataflow import analyze_semantic_dataflow, compute_dataflow_quality_metrics

ROOT = Path(__file__).resolve().parent
P234 = ROOT / "testdata" / "phase234"
P232_F3 = ROOT / "testdata" / "phase232" / "real" / "f3_run1"


class Phase234ParameterQualityTests(unittest.TestCase):
    def test_legacy_zero_reinterpreted_as_unknown(self) -> None:
        funcs = json.loads((P232_F3 / "FIRM.functions.json").read_text(encoding="utf-8"))
        df = json.loads((P232_F3 / "FIRM.dataflow.json").read_text(encoding="utf-8"))
        sdf = analyze_semantic_dataflow(funcs, dataflow_export=df)
        qm = (sdf.get("summary") or {}).get("dataflowQualityMetrics") or {}
        self.assertGreater(qm.get("parameterUnknownCoverage") or 0, 99.0)
        self.assertEqual(qm.get("parameterRecoveryCoverage"), 0.0)
        dist = qm.get("parameterQualityDistribution") or {}
        self.assertGreaterEqual(dist.get("UNKNOWN_PARAMETER_COUNT") or 0, 180)
        # Ensure records expose quality, not fake zeros.
        sample = (sdf.get("functions") or [None])[0]
        self.assertIsNotNone(sample)
        assert sample is not None
        self.assertIsNone(sample.get("parameterCount"))
        self.assertEqual(sample.get("parameterQuality"), "UNKNOWN_PARAMETER_COUNT")

    def test_confirmed_zero_vs_unknown(self) -> None:
        fns = {
            "functions": [
                {"address": "0x1", "name": "a", "basicBlocks": 1, "size": 8, "mnemonics": ["mov", "bx"]},
                {"address": "0x2", "name": "b", "basicBlocks": 1, "size": 8, "mnemonics": ["mov", "bx"]},
            ]
        }
        df = {
            "functions": [
                {
                    "address": "0x1",
                    "name": "a",
                    "parameterCount": 0,
                    "parameterQuality": "CONFIRMED_ZERO_PARAMETERS",
                    "signatureSource": "ANALYSIS",
                    "memoryReads": 0,
                    "memoryWrites": 0,
                    "compareOps": 0,
                    "conditionalBranches": 0,
                    "callCount": 0,
                    "dataReferenceCount": 0,
                    "quality": "ok",
                },
                {
                    "address": "0x2",
                    "name": "b",
                    "parameterCount": None,
                    "parameterQuality": "UNKNOWN_PARAMETER_COUNT",
                    "signatureSource": "DEFAULT",
                    "memoryReads": 0,
                    "memoryWrites": 0,
                    "compareOps": 0,
                    "conditionalBranches": 0,
                    "callCount": 0,
                    "dataReferenceCount": 0,
                    "quality": "partial",
                },
            ]
        }
        sdf = analyze_semantic_dataflow(fns, dataflow_export=df)
        qm = compute_dataflow_quality_metrics(sdf)
        self.assertEqual(qm.get("parameterKnownCount"), 1)
        self.assertEqual(qm.get("parameterUnknownCount"), 1)
        dist = qm.get("parameterQualityDistribution") or {}
        self.assertEqual(dist.get("CONFIRMED_ZERO_PARAMETERS"), 1)
        self.assertEqual(dist.get("UNKNOWN_PARAMETER_COUNT"), 1)

    def test_param_gt_report_accuracy(self) -> None:
        report_path = P234 / "param_gt" / "out" / "param_gt_report.json"
        self.assertTrue(report_path.is_file(), "run scripts/run_phase234_param_gt_ghidra.py first")
        report = json.loads(report_path.read_text(encoding="utf-8"))
        # Exact match rate must stay at 90% for the controlled 10-function GT
        # (opaque_cc recovered 3 instead of expected 2).
        self.assertEqual(report.get("exactParameterAccuracy"), 90.0)
        self.assertEqual(report.get("exactCount"), 9)
        self.assertEqual(report.get("wrongCount"), 1)
        # Accepted/ambiguous may be higher when allowUnknown is documented.
        self.assertGreaterEqual(report.get("acceptedOrAmbiguousRate") or 0, 90.0)
        self.assertLessEqual(report.get("exactParameterAccuracy") or 0, report.get("acceptedOrAmbiguousRate") or 0)
        # Legacy alias must track exact accuracy — never inflate to 100% when wrong≠0.
        if "recoveryAccuracyPercent" in report:
            self.assertEqual(report["recoveryAccuracyPercent"], report["exactParameterAccuracy"])
        self.assertEqual(report.get("unknownParameterRate"), 0.0)
        self.assertEqual(report.get("partialSignatureRate"), 0.0)
        self.assertEqual(report.get("recoveredParameterCoverage"), 100.0)
        details = report.get("details") or []
        self.assertEqual(len(details), 10)
        opaque = next(d for d in details if d.get("id") == "gt_opaque")
        self.assertEqual(opaque.get("expected"), 2)
        self.assertEqual(opaque.get("got"), 3)
        self.assertIn(opaque.get("status"), {"WRONG", "WRONG_ACCEPTED_AMBIGUOUS"})

    def test_blind_annotation_packet(self) -> None:
        packet = json.loads(
            (P234 / "annotation" / "blind_packet_labeled.json").read_text(encoding="utf-8")
        )
        compare = json.loads(
            (P234 / "annotation" / "annotation_compare.json").read_text(encoding="utf-8")
        )
        self.assertEqual(packet.get("secondAnnotator"), "SECOND_ANNOTATOR_NOT_AVAILABLE")
        self.assertEqual(compare.get("secondAnnotator"), "SECOND_ANNOTATOR_NOT_AVAILABLE")
        self.assertIsNone(compare.get("cohensKappa"))
        self.assertGreaterEqual(packet.get("sampleSize") or 0, 30)
        for item in packet.get("items") or []:
            self.assertIn(
                item.get("manualLabel"),
                {
                    "GENERAL_INPUT_PROCESSING",
                    "OTHER_PROGRAM_LOGIC",
                    "NOT_SUFFICIENTLY_DETERMINABLE",
                },
            )


if __name__ == "__main__":
    unittest.main()
