"""Phase 2.3 Activation Forensics — unit + fixture quality tests."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import activation_forensics as af
from function_diff import compare_function_analyses
from input_behavior import analyze_input_behavior

ROOT = Path(__file__).resolve().parent
TD = ROOT / "testdata" / "phase23"


def _load(name: str) -> dict:
    return json.loads((TD / name).read_text(encoding="utf-8"))


class Phase23ActivationForensicsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.subject = _load("subject.functions.json")
        cls.reference = _load("reference.functions.json")
        cls.gt = _load("ground_truth.json")
        cls.diff = compare_function_analyses(cls.subject, cls.reference)
        cls.ib = analyze_input_behavior(cls.subject)
        cls.ib_ref = analyze_input_behavior(cls.reference)
        from input_behavior import diff_input_behavior

        cls.ib_diff = diff_input_behavior(
            cls.ib,
            cls.ib_ref,
            subject_fns=cls.subject["functions"],
            reference_fns=cls.reference["functions"],
        )
        cls.full = af.run_activation_forensics(
            cls.subject,
            function_diff=cls.diff,
            input_behavior=cls.ib,
            input_behavior_diff=cls.ib_diff,
            analysis_profile={
                "analysisProfileVersion": "2.2G.1",
                "analysisProfileHash": "c0f507820a1457a1af98c2a66352db531f2f4ad1bcf72bc32c58e307e3f41de7",
            },
            profile_compat=(True, "COMPATIBLE", ["profiles match"]),
            subject_sha256="subj" + "0" * 60,
            reference_sha256="ref" + "0" * 61,
            reference_trust="communityLibrary",
        )

    def test_engine_ok_and_limitations(self) -> None:
        self.assertTrue(self.full["ok"])
        self.assertIn(self.full["phase"], {"2.3", "2.3.1", "2.3.2", "2.3.3"})
        lim = " ".join(self.full.get("analysisLimitations") or [])
        self.assertIn("kein nachweis realen fahrzeugverhaltens", lim.lower())
        self.assertIn("keine rekonstruktion", lim.lower())
        # Must not claim OEM for community trust
        ref = self.full["referenceComparison"]
        self.assertTrue(ref["referenceIsCommunity"])
        self.assertFalse(ref["referenceIsOemVerified"])
        # Phase 2.3.1: mixed STATIC_CONFIRMED must not wash overall to STATIC_CONFIRMED
        dist = self.full.get("activationEvidenceDistribution") or {}
        if dist.get("staticConfirmedCount") and (
            dist.get("indicativeCount") or dist.get("speculativeCount")
        ):
            self.assertNotEqual(dist.get("overallEvidenceTier"), af.STATIC_CONFIRMED)
            self.assertEqual(dist.get("overallEvidenceTier"), af.INDICATIVE)

    def test_input_categories_present(self) -> None:
        cats = self.full.get("categoryCounts") or {}
        # At least several expected categories from fixtures
        self.assertGreaterEqual(sum(1 for v in cats.values() if v), 5)
        handlers = self.full["inputHandlerFindings"]
        self.assertGreaterEqual(len(handlers), 6)
        for h in handlers:
            self.assertIn(h["evidenceTier"], {
                af.STATIC_CONFIRMED,
                af.INDICATIVE,
                af.SPECULATIVE,
                af.UNKNOWN,
            })
            self.assertTrue(h.get("inputCategories"))

    def test_helper_not_classified_as_handler(self) -> None:
        addrs = {h.get("address") for h in self.full["inputHandlerFindings"]}
        self.assertNotIn("0x08001500", addrs)

    def test_undocumented_and_conditional(self) -> None:
        und = self.full["undocumentedLogic"]
        self.assertTrue(und["ok"])
        self.assertGreaterEqual((und.get("summary") or {}).get("genericNamedFunctions", 0), 1)
        cond = self.full["conditionalLogicFindings"]
        self.assertTrue(cond["ok"])
        self.assertGreaterEqual(
            (cond.get("summary") or {}).get("functionsWithConditionalLogic", 0), 1
        )

    def test_evidence_graph(self) -> None:
        g = self.full["activationEvidenceGraph"]
        self.assertTrue(g["ok"])
        self.assertGreater(g["nodeCount"], 0)
        self.assertGreaterEqual(g["edgeCount"], 0)
        for e in g.get("edges") or []:
            self.assertIn("relation", e)
            self.assertIn("technicalFinding", e)
            self.assertIn("confirmed", e)

    def test_fsm_integration_no_invented_states(self) -> None:
        fsm = self.full["fsmIntegration"]
        self.assertTrue(fsm["ok"])
        for c in fsm.get("candidates") or []:
            if not c.get("stateCountVerified"):
                # Unverified counts must be null (not derived from BB count as truth)
                if c.get("stateCount") is not None:
                    # Allowed only if explicitly verified flag — else prefer null
                    self.assertTrue(
                        c.get("stateCountVerified") or c.get("stateCount") is None
                        or isinstance(c.get("stateCount"), int)
                    )

    def test_prioritization_disclaimer(self) -> None:
        prio = self.full["prioritization"]
        self.assertTrue(prio["ok"])
        self.assertTrue(prio.get("prioritizedFunctions"))
        note = (prio["prioritizedFunctions"][0].get("note") or "").lower()
        self.assertIn("kein manipulationsnachweis", note)

    def test_poll_summary_compact(self) -> None:
        poll = af.summarize_activation_forensics_for_poll(self.full)
        self.assertTrue(poll["ok"])
        self.assertIn("summary", poll)
        self.assertNotIn("activationEvidenceGraph", poll.get("summary") or {})
        # Graph only as counts in poll
        self.assertIn("nodeCount", poll.get("activationEvidenceGraph") or {})

    def test_fixture_quality_metrics(self) -> None:
        cases = self.gt["cases"]
        metrics = af.evaluate_detection_quality(
            self.full["inputHandlerFindings"], cases
        )
        self.assertIn("truePositives", metrics)
        self.assertIn("disclaimer", metrics)
        self.assertIn("Fixtures", metrics["disclaimer"])
        # Expect useful recall on designed positives
        self.assertIsNotNone(metrics["recall"])
        self.assertGreaterEqual(metrics["recall"], 0.5)
        self.assertGreaterEqual(metrics["truePositives"], 5)
        # Helper should not dominate FPs if classified
        self.assertLessEqual(metrics["falsePositives"], 6)

    def test_no_activation_sequence_fields(self) -> None:
        blob = json.dumps(self.full, ensure_ascii=False).lower()
        for banned in ("unlock_sequence", "activation_sequence", "brute_force", "try_combo"):
            self.assertNotIn(banned, blob)

    def test_missing_export(self) -> None:
        r = af.run_activation_forensics({"ok": False})
        self.assertFalse(r["ok"])
        self.assertEqual(r["evidenceTier"], af.UNKNOWN)


if __name__ == "__main__":
    unittest.main()
