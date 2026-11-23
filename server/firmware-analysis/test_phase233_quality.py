"""Phase 2.3.3 — quality metrics, expanded GT, detection A–G, pagination."""
from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest import mock

import activation_forensics as af
from semantic_dataflow import analyze_semantic_dataflow, compute_dataflow_quality_metrics, load_dataflow_export

ROOT = Path(__file__).resolve().parent
TD = ROOT / "testdata" / "phase233" / "fixtures"
REAL_F3 = ROOT / "testdata" / "phase232" / "real" / "f3_run1"
PRIOR_C_RECALL_FLOOR = 0.40


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _gt_cases(gt: dict, variant: str) -> list[dict]:
    addr_key = "addressD" if variant in ("D_shifted",) else "addressA"
    return [
        {
            "address": c[addr_key],
            "expectDetect": c["expectDetect"],
            "id": c["id"],
            "category": c.get("category"),
        }
        for c in gt["cases"]
    ]


class Phase233QualityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gt = _load(TD / "ground_truth.json")
        cls.variant_keys = [
            "A_named",
            "B_generic",
            "C_no_strings",
            "D_shifted",
            "E_anon_meta",
            "F_generic_no_signature",
            "G_partial_dataflow",
        ]
        cls.variants = {k: _load(TD / f"{k}.functions.json") for k in cls.variant_keys}
        cls.metrics_table: dict[str, dict] = {}

    def _run(self, export: dict, **kwargs) -> dict:
        return af.run_activation_forensics(export, reference_trust="communityLibrary", **kwargs)

    def test_ground_truth_size(self) -> None:
        ec = self.gt["expectCounts"]
        self.assertGreaterEqual(ec["total"], 40)
        self.assertGreaterEqual(ec["positives"], 15)
        self.assertGreaterEqual(ec["negatives"], 15)

    def test_metrics_across_variants_ag(self) -> None:
        neg_fp_budget = 2
        for name in self.variant_keys:
            export = self.variants[name]
            df_path = TD / f"{name}.dataflow.json"
            dataflow = load_dataflow_export(df_path) if df_path.is_file() else None
            r = self._run(export, dataflow_export=dataflow)
            cases = _gt_cases(self.gt, "D_shifted" if name == "D_shifted" else "A_named")
            m = af.evaluate_detection_quality(r["inputHandlerFindings"], cases)
            self.__class__.metrics_table[name] = m
            self.assertIn("specificity", m)
            if m["specificity"] is not None:
                self.assertGreaterEqual(m["specificity"], 0.0)
            if name in ("A_named", "B_generic") and m["precision"] is not None:
                self.assertGreaterEqual(m["precision"], 0.85, f"{name} precision {m}")
            neg_cases = [c for c in cases if not c["expectDetect"]]
            fp_on_neg = sum(
                1
                for c in neg_cases
                if any(
                    str(h.get("address") or "").lower() == str(c["address"]).lower()
                    for h in r["inputHandlerFindings"]
                )
            )
            self.assertLessEqual(fp_on_neg, neg_fp_budget, f"{name} FP={fp_on_neg}")

        c = self.metrics_table.get("C_no_strings") or {}
        if c.get("recall") is not None:
            self.assertGreaterEqual(
                c["recall"],
                PRIOR_C_RECALL_FLOOR,
                "C recall below prior floor — tradeoff: check FP=0 constraint in test_metrics",
            )

    def test_dataflow_quality_on_real_f3_if_present(self) -> None:
        fnp = REAL_F3 / "FIRM.functions.json"
        dfp = REAL_F3 / "FIRM.dataflow.json"
        if not fnp.is_file():
            self.skipTest("f3_run1 export missing")
        fa = _load(fnp)
        df = load_dataflow_export(dfp) if dfp.is_file() else None
        sdf = analyze_semantic_dataflow(fa, dataflow_export=df)
        qm = (sdf.get("summary") or {}).get("dataflowQualityMetrics") or {}
        if not qm:
            qm = compute_dataflow_quality_metrics(sdf)
        for key in (
            "dataflowExportCoverage",
            "parameterRecoveryCoverage",
            "memoryAccessCoverage",
            "dataReferenceCoverage",
            "unresolvedDataflowCount",
            "semanticConfidenceDistribution",
        ):
            self.assertIn(key, qm)

    def test_pagination_helper(self) -> None:
        items = [{"id": i} for i in range(120)]
        page, meta = af.slice_findings_for_page(items, offset=10, limit=25)
        self.assertEqual(len(page), 25)
        self.assertEqual(meta["offset"], 10)
        self.assertEqual(meta["totalFindings"], 120)
        self.assertEqual(meta["omittedFindings"], 120 - 10 - 25)
        wrapped = af.paginate_findings(items, offset=0, limit=5)
        self.assertEqual(len(wrapped["findings"]), 5)

    def test_manual_annotation_independence(self) -> None:
        ann = _load(ROOT / "testdata" / "phase233" / "manual" / "annotation.json")
        self.assertEqual(ann.get("independence"), "SINGLE_ANNOTATOR_NOT_BLIND")
        self.assertGreaterEqual(ann.get("sampleSize", 0), 30)

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.metrics_table:
            print("\n--- Phase 2.3.3 A–G detection metrics ---")
            for k, m in sorted(cls.metrics_table.items()):
                print(
                    k,
                    "P",
                    m.get("precision"),
                    "R",
                    m.get("recall"),
                    "Spec",
                    m.get("specificity"),
                    "TP",
                    m.get("truePositives"),
                    "FP",
                    m.get("falsePositives"),
                )


if __name__ == "__main__":
    unittest.main()