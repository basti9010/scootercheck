"""Tests for board pinouts, limit back-slice, and input probe merge."""
from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import board_pinouts
import input_probe
import limit_slice


class BoardPinoutTests(unittest.TestCase):
    def test_resolve_zt3(self) -> None:
        b = board_pinouts.resolve_board(models=["zt3"], controller_type="VCU", filename="ZT3_VCU_AT32.zip")
        self.assertIsNotNone(b)
        assert b is not None
        self.assertEqual(b["id"], "zt3-vcu-at32")
        self.assertIn("Gas", b["defaultComboHypothesis"])


class LimitSliceTests(unittest.TestCase):
    def test_slice_on_speed_blob(self) -> None:
        # Thumb NOPs + packed 0x1600 (22) and 0x2800 (40)
        blob = bytearray(256)
        # cmp r0, r1 ; b xx style filler then immediates as data
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
        self.assertTrue(any("Board-Heuristik" in c for c in out["combos"]))
        self.assertIn("throttle", out.get("roleHits") or [])


class InputProbeMergeTests(unittest.TestCase):
    def test_merge_adds_combo(self) -> None:
        result = {"notes": [], "comboSummaries": [], "modeTransitions": [], "sources": [], "quality": {"summary": "x"}}
        probe = {
            "ok": True,
            "notes": ["input_probe=ok"],
            "probes": [{"sensitive": True}],
            "combos": ["Input-Probe: Hypothese"],
            "transitions": [
                {
                    "id": "probe-tr-dual-input",
                    "title": "Eingangs-Probe",
                    "trigger": "Gas+Bremse",
                    "effect": "delta",
                    "evidence": "x",
                    "source": "serverEmulation",
                    "confidence": "low",
                }
            ],
            "sensitiveSites": 1,
        }
        out = input_probe.merge_into_result(result, probe)
        self.assertIn("Input-Probe: Hypothese", out["comboSummaries"])
        self.assertIn("serverEmulation", out["sources"])


if __name__ == "__main__":
    unittest.main()
