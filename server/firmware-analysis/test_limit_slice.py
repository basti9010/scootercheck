"""Tests for board pinouts, limit back-slice, and input probe merge."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import board_pinouts
import combo_policy
import input_probe
import limit_slice


class BoardPinoutTests(unittest.TestCase):
    def test_resolve_zt3(self) -> None:
        b = board_pinouts.resolve_board(models=["zt3"], controller_type="VCU", filename="ZT3_VCU_AT32.zip")
        self.assertIsNotNone(b)
        assert b is not None
        self.assertEqual(b["id"], "zt3-vcu-at32")
        self.assertEqual(b.get("defaultComboHypothesis") or "", "")
        self.assertIn("AT32", b.get("notes") or "")


class LimitSliceTests(unittest.TestCase):
    def test_slice_on_speed_blob(self) -> None:
        blob = bytearray(256)
        blob[80] = 0x00
        blob[81] = 0x16
        blob[120] = 0x00
        blob[121] = 0x28
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "t.bin"
            p.write_bytes(bytes(blob))
            out = limit_slice.analyze(
                p,
                models=["zt3"],
                controller_type="VCU",
                filename="zt3_vcu_at32.bin",
                decompiled_text="throttle brake power boot",
            )
        self.assertTrue(out["ok"])
        self.assertEqual(out["combos"], [])
        self.assertNotIn("defaultComboHypothesis", (out.get("board") or {}))
        self.assertIn("throttle", out.get("roleHits") or [])
        self.assertTrue(any("cmpNear" in n or "limit_slice=ok" in n for n in out.get("notes") or []))


class InputProbeMergeTests(unittest.TestCase):
    def test_merge_keeps_notes_not_speculative_combos(self) -> None:
        result = {"notes": [], "comboSummaries": [], "modeTransitions": [], "sources": [], "quality": {"summary": "x"}}
        probe = {
            "ok": True,
            "notes": ["input_probe=ok", "input_probe=sensitive 1/1 — physische Tastenfolge nicht validiert"],
            "probes": [{"sensitive": True}],
            "combos": [],
            "transitions": [],
            "sensitiveSites": 1,
        }
        out = input_probe.merge_into_result(result, probe)
        self.assertEqual(out["comboSummaries"], [])
        self.assertIn("serverEmulation", out["sources"])
        sanitized = combo_policy.sanitize_result_combos(out)
        self.assertEqual(sanitized["comboSummaries"], [])


if __name__ == "__main__":
    unittest.main()
