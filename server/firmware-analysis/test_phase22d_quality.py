"""Phase 2.2D quality tests: reset_handler GT, FSM null counts, input FP reduction."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import function_diff as fd
import function_matcher as fm
import input_behavior as ib

THUMB = Path(__file__).resolve().parent / "testdata" / "thumb_validation" / "meta"
P22D = Path(__file__).resolve().parent / "testdata" / "phase22d"


class ResetHandlerGroundTruthTests(unittest.TestCase):
    def test_machine_bytes_identical(self) -> None:
        root = THUMB.parent
        a = (root / "bin" / "version_a.bin").read_bytes()
        b = (root / "bin" / "version_b.bin").read_bytes()
        # Body only (exclude relocated literal pool word after 12-byte body).
        self.assertEqual(a[0x68 : 0x68 + 12], b[0x74 : 0x74 + 12])

    def test_classification_identical_after_gt_fix(self) -> None:
        gt = json.loads((THUMB / "ground_truth.json").read_text(encoding="utf-8"))
        self.assertIn("reset_handler", gt["expectedDiff"]["identical_likely"])
        self.assertNotIn("reset_handler", gt["expectedDiff"]["structurally_changed"])

        ver_a = json.loads((THUMB / "version_a.functions.json").read_text(encoding="utf-8"))
        ver_b = json.loads((THUMB / "version_b.functions.json").read_text(encoding="utf-8"))
        ver_a["ok"] = True
        ver_b["ok"] = True
        out = fd.compare_function_analyses(ver_b, ver_a)
        by = {}
        for p in out["pairs"]:
            n = (p.get("subject") or p.get("reference") or {}).get("name")
            if n:
                by[n] = p["status"]
        self.assertEqual(by.get("reset_handler"), fd.STATUS_IDENTICAL)
        # Metrics with corrected GT
        exp = gt["expectedDiff"]
        tp = fp = fn = 0
        for name in exp["identical_likely"]:
            if by.get(name) == fd.STATUS_IDENTICAL:
                tp += 1
            else:
                fn += 1
        for name in exp["structurally_changed"]:
            if by.get(name) == fd.STATUS_CHANGED:
                tp += 1
            elif by.get(name) is None:
                fn += 1
            else:
                fp += 1
                fn += 1
        for name in exp["added"]:
            tp += by.get(name) == fd.STATUS_ADDED
            fn += by.get(name) != fd.STATUS_ADDED
        for name in exp["removed"]:
            tp += by.get(name) == fd.STATUS_REMOVED
            fn += by.get(name) != fd.STATUS_REMOVED
        prec = tp / max(tp + fp, 1)
        rec = tp / max(tp + fn, 1)
        self.assertEqual(prec, 1.0, f"by={by} tp={tp} fp={fp} fn={fn}")
        self.assertEqual(rec, 1.0, f"by={by} tp={tp} fp={fp} fn={fn}")
        ResetHandlerGroundTruthTests.metrics = {
            "precision": prec,
            "recall": rec,
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "by_name": by,
            "summary": out["summary"],
        }


class InputBehaviorQualityTests(unittest.TestCase):
    def test_helpers_not_classified(self) -> None:
        ver_a = json.loads((THUMB / "version_a.functions.json").read_text(encoding="utf-8"))
        ver_a["ok"] = True
        out = ib.analyze_input_behavior(ver_a)
        names = {f["name"] for f in out["inputFunctions"]}
        self.assertIn("process_input", names)
        for helper in ("add_values", "mul_values", "loop_accumulate", "reset_handler"):
            self.assertNotIn(helper, names)

    def test_reset_handler_denylisted(self) -> None:
        scored = ib.classify_input_function(
            {
                "address": "1",
                "name": "reset_handler",
                "size": 12,
                "basicBlocks": 2,
                "cfgEdges": 2,
                "calls": ["process_input"],
                "calledBy": [],
                "constants": [],
                "strings": [],
                "mnemonics": ["movs", "bl", "b"],
                "fingerprint": "rh",
            }
        )
        self.assertIsNone(scored)

    def test_string_alone_still_insufficient(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                {
                    "address": "1",
                    "name": "FUN_08001234",
                    "size": 8,
                    "basicBlocks": 1,
                    "cfgEdges": 0,
                    "calls": [],
                    "calledBy": [],
                    "constants": [],
                    "strings": ["button"],
                    "mnemonics": ["bx"],
                    "fingerprint": "x",
                }
            ],
        }
        out = ib.analyze_input_behavior(fa)
        self.assertEqual(out["summary"]["inputRelevantCount"], 0)

    def test_confirmed_static_label(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                {
                    "address": "1",
                    "name": "process_input",
                    "size": 20,
                    "basicBlocks": 3,
                    "cfgEdges": 4,
                    "calls": ["add_values"],
                    "calledBy": ["reset_handler"],
                    "constants": [],
                    "strings": [],
                    "mnemonics": ["push", "bl", "pop"],
                    "fingerprint": "pi",
                }
            ],
        }
        out = ib.analyze_input_behavior(fa)
        self.assertEqual(out["inputFunctions"][0]["evidenceTier"], ib.EVIDENCE_CONFIRMED)


class FsmQualityTests(unittest.TestCase):
    def test_no_bb_derived_state_counts(self) -> None:
        syn = json.loads((P22D / "synthetic.functions.json").read_text(encoding="utf-8"))
        out = ib.analyze_input_behavior(syn)
        sm = out["stateMachineAnalysis"]
        self.assertIsNone(sm.get("totalEstimatedStates"))
        self.assertIsNone(sm.get("totalEstimatedTransitions"))
        names = {m["functionName"]: m for m in sm["stateMachines"]}
        # branchy_math must NOT be an FSM candidate (no state/input naming)
        self.assertNotIn("branchy_math", names)
        # mode_fsm_tick should be candidate/structure with null counts
        self.assertIn("mode_fsm_tick", names)
        m = names["mode_fsm_tick"]
        self.assertIsNone(m.get("stateCount"))
        self.assertIsNone(m.get("estimatedStates"))
        self.assertIn(
            m.get("analysisQuality"),
            {ib.FSM_CANDIDATE, ib.FSM_STRUCTURE, ib.FSM_NOT_VERIFIABLE},
        )

    def test_multi_bb_without_state_signals_excluded(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                {
                    "address": "1",
                    "name": "branchy_math",
                    "size": 40,
                    "basicBlocks": 5,
                    "cfgEdges": 7,
                    "calls": [],
                    "calledBy": [],
                    "constants": [],
                    "strings": [],
                    "mnemonics": ["cmp", "blt", "adds", "b", "muls"],
                    "fingerprint": "bm",
                }
            ],
        }
        out = ib.analyze_input_behavior(fa)
        self.assertEqual(out["stateMachineAnalysis"]["stateMachineCount"], 0)


class Phase22dMatcherFixtureTests(unittest.TestCase):
    def test_shifted_address_and_ambiguous_helpers(self) -> None:
        syn = json.loads((P22D / "synthetic.functions.json").read_text(encoding="utf-8"))
        leaf = next(f for f in syn["functions"] if f["name"] == "helper_leaf")
        shifted = dict(leaf)
        shifted["address"] = "08002000"
        out = fm.match_functions([shifted], [leaf])
        matched = [m for m in out["matches"] if m.get("subject") and m.get("reference")]
        self.assertEqual(len(matched), 1)
        self.assertEqual(matched[0]["matchConfidence"], fm.CONF_HIGH)

        dup = next(f for f in syn["functions"] if f["name"] == "dup_b")
        refs = [f for f in syn["functions"] if f["fingerprint"] == dup["fingerprint"]]
        amb = fm.match_functions([dup], refs)
        self.assertGreaterEqual(amb["summary"]["ambiguous"], 1)


if __name__ == "__main__":
    unittest.main()
