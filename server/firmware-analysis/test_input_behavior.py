"""Phase 2.2C input behavior + state machine tests."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

import input_behavior as ib

FIXTURE = Path(__file__).resolve().parent / "testdata" / "thumb_validation" / "meta"


def _fn(**kwargs):
    base = {
        "address": "08000000",
        "name": "FUN_x",
        "size": 16,
        "basicBlocks": 3,
        "cfgEdges": 4,
        "calls": [],
        "calledBy": [],
        "constants": [],
        "strings": [],
        "mnemonics": ["push", "cmp", "beq", "pop"],
        "fingerprint": "deadbeef",
        "confidence": "medium",
    }
    base.update(kwargs)
    return base


class InputBehaviorTests(unittest.TestCase):
    def test_simple_input_processing(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(
                    name="process_input",
                    address="08000048",
                    calls=["compare_and_branch"],
                    calledBy=["reset_handler"],
                    basicBlocks=3,
                    cfgEdges=4,
                    fingerprint="pi1",
                )
            ],
        }
        out = ib.analyze_input_behavior(fa)
        self.assertTrue(out["ok"])
        self.assertGreaterEqual(out["summary"]["inputRelevantCount"], 1)
        names = [f["name"] for f in out["inputFunctions"]]
        self.assertIn("process_input", names)
        self.assertIn(
            out["evidenceTier"],
            {ib.EVIDENCE_CONFIRMED, ib.EVIDENCE_CONFIRMED_LEGACY, ib.EVIDENCE_INDICATIVE},
        )

    def test_string_alone_insufficient(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(name="FUN_08001234", strings=["button"], basicBlocks=1, cfgEdges=0, fingerprint="s1")
            ],
        }
        out = ib.analyze_input_behavior(fa)
        self.assertEqual(out["summary"]["inputRelevantCount"], 0)

    def test_different_input_events(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(name="handle_button_event", calls=["set_state"], fingerprint="b1"),
                _fn(name="ble_message_dispatch", calls=["queue_push"], fingerprint="b2"),
            ],
        }
        out = ib.analyze_input_behavior(fa)
        cats = out.get("categories") or {}
        self.assertTrue(cats.get("button_or_key") or cats.get("input_callback"))
        self.assertTrue(cats.get("ble_message") or cats.get("event_queue"))

    def test_state_variable_and_conditional(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(
                    name="update_mode_state",
                    basicBlocks=5,
                    cfgEdges=8,
                    mnemonics=["push", "cmp", "beq", "bne", "strb", "pop"],
                    calls=["process_input"],
                    fingerprint="st1",
                )
            ],
        }
        out = ib.analyze_input_behavior(fa)
        sm = out["stateMachineAnalysis"]
        self.assertGreaterEqual(sm["stateMachineCount"], 1)
        m0 = sm["stateMachines"][0]
        # Phase 2.2D: no BB-derived state counts
        self.assertIsNone(m0.get("estimatedStates"))
        self.assertIsNone(m0.get("stateCount"))
        self.assertIn("uncertainty", m0)

    def test_simple_fsm_three_states(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(
                    name="process_input",
                    basicBlocks=3,
                    cfgEdges=4,
                    mnemonics=["cmp", "beq", "bne", "b"],
                    fingerprint="fsm1",
                    calls=["set_state"],
                )
            ],
        }
        out = ib.analyze_input_behavior(fa)
        sm = out["stateMachineAnalysis"]
        self.assertGreaterEqual(sm["stateMachineCount"], 1)
        self.assertIsNone(sm.get("totalEstimatedStates"))

    def test_missing_function_export(self) -> None:
        out = ib.analyze_input_behavior(None)
        self.assertFalse(out["ok"])

    def test_bad_export(self) -> None:
        out = ib.analyze_input_behavior({"ok": False, "functions": []})
        self.assertFalse(out["ok"])

    def test_fixture_process_input(self) -> None:
        ver_a = json.loads((FIXTURE / "version_a.functions.json").read_text(encoding="utf-8"))
        ver_a["ok"] = True
        out = ib.analyze_input_behavior(ver_a)
        names = [f["name"] for f in out["inputFunctions"]]
        self.assertIn("process_input", names)
        # compare_and_branch is dense CFG — may appear as state-machine candidate
        sm = out["stateMachineAnalysis"]
        self.assertGreaterEqual(sm["stateMachineCount"], 1)

    def test_firmware_version_diff(self) -> None:
        ver_a = json.loads((FIXTURE / "version_a.functions.json").read_text(encoding="utf-8"))
        ver_b = json.loads((FIXTURE / "version_b.functions.json").read_text(encoding="utf-8"))
        ver_a["ok"] = True
        ver_b["ok"] = True
        a = ib.analyze_input_behavior(ver_a)
        b = ib.analyze_input_behavior(ver_b)
        diff = ib.diff_input_behavior(
            b,
            a,
            subject_fns=ver_b["functions"],
            reference_fns=ver_a["functions"],
        )
        self.assertTrue(diff["ok"])
        self.assertIn("summary", diff)
        # process_input exists in both → matched as identical or structurally changed
        statuses = {
            (p.get("subject") or p.get("reference") or {}).get("name"): p.get("status")
            for p in diff["pairs"]
        }
        self.assertIn(statuses.get("process_input"), {"IDENTISCH", "STRUKTURELL_VERAENDERT"})

    def test_ambiguous_state_transitions_marked(self) -> None:
        fa = {
            "ok": True,
            "functions": [
                _fn(
                    name="FUN_0800abcd",
                    basicBlocks=4,
                    cfgEdges=5,
                    mnemonics=["b", "beq"],
                    fingerprint="weak",
                )
            ],
        }
        out = ib.analyze_input_behavior(fa)
        # Generic branchy FUN_* without state naming → no FSM claim
        self.assertEqual(out["stateMachineAnalysis"]["stateMachineCount"], 0)


if __name__ == "__main__":
    unittest.main()
