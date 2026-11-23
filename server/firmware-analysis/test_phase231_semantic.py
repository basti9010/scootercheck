"""Phase 2.3.1 — semantic dataflow, name-independent detection, evidence quality."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import activation_forensics as af
from semantic_dataflow import analyze_semantic_dataflow, load_dataflow_export

ROOT = Path(__file__).resolve().parent
TD = ROOT / "testdata" / "phase231" / "fixtures"
REAL = ROOT / "testdata" / "phase231" / "real"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class Phase231SemanticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gt = _load(TD / "ground_truth.json")
        cls.named = _load(TD / "A_named.functions.json")
        cls.generic = _load(TD / "B_generic_names.functions.json")
        cls.no_strings = _load(TD / "C_no_strings.functions.json")
        cls.shifted = _load(TD / "D_shifted_addr.functions.json")
        cls.extra = _load(TD / "E_extra_cases.functions.json")

    def _run(self, export: dict, **kwargs) -> dict:
        return af.run_activation_forensics(export, reference_trust="communityLibrary", **kwargs)

    def test_semantic_dataflow_derived(self) -> None:
        sdf = analyze_semantic_dataflow(self.named)
        self.assertTrue(sdf["ok"])
        self.assertGreaterEqual((sdf.get("summary") or {}).get("functionCount", 0), 5)
        self.assertGreater((sdf.get("summary") or {}).get("withMemoryReads", 0), 0)
        # Without export → derived / partial
        self.assertGreaterEqual((sdf.get("summary") or {}).get("derivedOnly", 0), 1)

    def test_bad_and_missing_dataflow(self) -> None:
        bad = load_dataflow_export(TD / "H_bad_dataflow.json")
        # File exists but may be ok with weird functions — engine must not crash.
        sdf = analyze_semantic_dataflow(
            _load(TD / "G_missing_dataflow.functions.json"),
            dataflow_export=bad if bad.get("ok") else {"ok": False, "functions": []},
        )
        self.assertIn("ok", sdf)
        incomplete = self._run(_load(TD / "F_incomplete_export.functions.json"))
        self.assertTrue(incomplete["ok"])
        unk = self._run(_load(TD / "I_unknown_arch.functions.json"))
        self.assertTrue(unk["ok"])

    def test_named_vs_generic_vs_no_strings(self) -> None:
        a = self._run(self.named)
        b = self._run(self.generic)
        c = self._run(self.no_strings)
        self.assertGreaterEqual(a["summary"]["inputHandlerCount"], 5)
        # Name/string removal must not collapse structural multi-signal detection to zero.
        self.assertGreaterEqual(b["summary"]["inputHandlerCount"], 3)
        self.assertGreaterEqual(c["summary"]["inputHandlerCount"], 3)
        m_a = af.evaluate_detection_quality(a["inputHandlerFindings"], self.gt["cases_named"])
        m_b = af.evaluate_detection_quality(b["inputHandlerFindings"], self.gt["cases_generic"])
        m_c = af.evaluate_detection_quality(c["inputHandlerFindings"], self.gt["cases_no_strings"])
        self.assertGreaterEqual(m_a["recall"] or 0, 0.5)
        self.assertGreaterEqual(m_b["recall"] or 0, 0.4)
        self.assertGreaterEqual(m_c["recall"] or 0, 0.4)
        # Anonymization may lower recall vs named — document, do not invent equality.
        self.assertLessEqual(m_c["recall"] or 0, (m_a["recall"] or 0) + 0.05)
        for r in (a, b, c):
            dist = r["activationEvidenceDistribution"]
            if dist.get("staticConfirmedCount") and (
                dist.get("indicativeCount") or dist.get("speculativeCount")
            ):
                self.assertEqual(dist["overallEvidenceTier"], af.INDICATIVE)

    def test_shifted_addresses(self) -> None:
        d = self._run(self.shifted)
        m = af.evaluate_detection_quality(d["inputHandlerFindings"], self.gt["cases_shifted"])
        self.assertGreaterEqual(m["truePositives"], 1)
        # Helper must remain undetected after address shift.
        addrs = {h.get("address") for h in d["inputHandlerFindings"]}
        self.assertNotIn("0x08002500", addrs)
        self.assertLessEqual(m["falsePositives"], 2)

    def test_extra_cases_precision(self) -> None:
        e = self._run(self.extra)
        m = af.evaluate_detection_quality(e["inputHandlerFindings"], self.gt["cases_extra"])
        self.assertIn("precision", m)
        # Compare-only / memory-only / compute must not flood FPs.
        self.assertLessEqual(m["falsePositives"], 3)
        # At least one of param/mmio/state should be detected.
        self.assertGreaterEqual(m["truePositives"], 1)

    def test_conditional_quality_not_gate_from_branches_alone(self) -> None:
        # Dense compare-only function must not be FEATURE_GATE_CANDIDATE.
        fn = next(f for f in self.extra["functions"] if f["address"] == "0x08002180")
        h = af.classify_activation_handler(fn)
        self.assertIsNone(h)
        q = af.classify_conditional_quality(
            af._structural_signals(fn, None), []
        )
        self.assertEqual(q, af.CONDITIONAL_LOGIC_ONLY)

    def test_feature_gate_requires_input_linkage(self) -> None:
        # state store + compares without input categories → STATE or CONDITIONAL only
        fn = {
            "address": "0x08009999",
            "name": "FUN_08009999",
            "basicBlocks": 3,
            "cfgEdges": 4,
            "mnemonics": ["ldr", "cmp", "bne", "str", "bx"],
            "calls": [],
            "calledBy": [],
            "constants": [],
            "strings": [],
        }
        sig = af._structural_signals(fn, None)
        self.assertEqual(
            af.classify_conditional_quality(sig, []),
            af.STATE_RELATED_CONDITIONAL_LOGIC
            if sig["hasStateStorePattern"]
            else af.CONDITIONAL_LOGIC_ONLY,
        )
        self.assertNotEqual(
            af.classify_conditional_quality(sig, []),
            af.FEATURE_GATE_CANDIDATE,
        )

    def test_evidence_graph_edges_require_evidence(self) -> None:
        a = self._run(self.named)
        g = a["activationEvidenceGraph"]
        self.assertTrue(g["ok"])
        q = g.get("quality") or {}
        self.assertIn("confirmedEdgeCount", q)
        for e in g.get("edges") or []:
            self.assertTrue(e.get("technicalFinding"))
            self.assertIn(e.get("relation"), {
                af.REL_CALLS,
                af.REL_REFERENCES,
                af.REL_PROCESSES_INPUT,
                af.REL_UPDATES_STATE,
                af.REL_STRUCTURALLY_DIFFERS,
                af.REL_BELONGS_TO_GROUP,
            })

    def test_poll_includes_quality_fields(self) -> None:
        a = self._run(self.named)
        poll = af.summarize_activation_forensics_for_poll(a)
        self.assertIn("activationEvidenceDistribution", poll)
        self.assertIn("semanticDataFlow", poll)
        self.assertIn("inputDetectionQuality", poll)
        self.assertIn("evidenceGraphQuality", poll)
        # No huge function lists in poll semantic summary
        sdf = poll.get("semanticDataFlow") or {}
        self.assertNotIn("functions", sdf)

    def test_no_activation_sequences(self) -> None:
        blob = json.dumps(self._run(self.named), ensure_ascii=False).lower()
        for banned in ("unlock_sequence", "activation_sequence", "brute_force", "try_combo"):
            self.assertNotIn(banned, blob)


@unittest.skipUnless(REAL.is_dir() and any(REAL.glob("*.functions.json")), "real exports absent")
class Phase231RealFirmwareNegativeControl(unittest.TestCase):
    def _af(self, stem: str, sha: str) -> dict:
        fa = _load(REAL / f"{stem}.functions.json")
        fa["ok"] = True
        cg = _load(REAL / f"{stem}.callgraph.json")
        cg["ok"] = cg.get("ok", True)
        return af.run_activation_forensics(
            fa,
            call_graph=cg,
            subject_sha256=sha,
            reference_trust="communityLibrary",
            negative_control=True,
        )

    def test_f3_negative_control(self) -> None:
        sha = "895e06427e167ac5bc4f5e1539e68c78cc433448856a199c201d1159a35badc4"
        r = self._af("f3_vcu_1.5.8", sha)
        self.assertTrue(r["ok"])
        self.assertTrue(r["summary"].get("negativeControl"))
        self.assertIn("Kontrollprüfung", " ".join(r.get("analysisLimitations") or []))
        # No FEATURE_GATE flood on stock reference without semantic names.
        fg = (r["conditionalLogicFindings"].get("summary") or {}).get("featureGateCandidates", 0)
        self.assertEqual(fg, 0)
        # Overall must not claim STATIC_CONFIRMED certainty for FUN_*-only stock.
        self.assertNotEqual(r["evidenceTier"], af.STATIC_CONFIRMED)
        # Precision/Recall intentionally omitted for real firmware.
        self.assertIn("Keine Precision", (r.get("inputDetectionQuality") or {}).get("note", ""))

    def test_g3_negative_control(self) -> None:
        sha = "1f1e05eb79ab0bebdd0c016345f9cd9c25364bc1e7e46162414fba1f2093b108"
        r = self._af("g3_vcu_1.5.13", sha)
        self.assertTrue(r["ok"])
        fg = (r["conditionalLogicFindings"].get("summary") or {}).get("featureGateCandidates", 0)
        self.assertEqual(fg, 0)
        self.assertNotEqual(r["evidenceTier"], af.STATIC_CONFIRMED)


if __name__ == "__main__":
    unittest.main()
