"""Tests for Unicorn + angr_lite helpers."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import angr_lite
import unicorn_emulate


class AngrLiteTests(unittest.TestCase):
    def test_capstone_path_hints(self) -> None:
        # LE 0x1600 + padding
        blob = b"\x00" * 80 + b"\x00\x16" + b"\x00" * 80
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "t.bin"
            p.write_bytes(blob)
            with mock.patch.object(angr_lite, "angr_engine_available", return_value=False):
                out = angr_lite.analyze_firmware(p)
        self.assertTrue(out["ok"])
        self.assertTrue(any("angr_lite=ok" in n for n in out["notes"]))
        self.assertTrue(any("engine not installed" in n or "Capstone" in n for n in out["notes"]))

    def test_subprocess_timeout_note(self) -> None:
        with mock.patch.object(angr_lite, "_run_angr_subprocess", return_value={"ok": False, "error": "timeout>90s"}):
            with mock.patch.object(angr_lite, "angr_engine_available", return_value=True):
                blob = b"\x00" * 80 + b"\x00\x16" + b"\x00" * 80
                with tempfile.TemporaryDirectory() as td:
                    p = Path(td) / "t.bin"
                    p.write_bytes(blob)
                    out = angr_lite.analyze_firmware(p)
        self.assertTrue(any("angr=failed:timeout" in n for n in out["notes"]))

    def test_merge_adds_source(self) -> None:
        result = {"notes": [], "sources": [], "modeTransitions": [], "quality": {"summary": "x"}}
        ang = {
            "ok": True,
            "notes": ["angr_lite=ok"],
            "transitions": [
                {
                    "id": "t1",
                    "title": "Pfad",
                    "trigger": "cmp",
                    "effect": "22",
                    "evidence": "x",
                    "source": "serverAngr",
                    "confidence": "low",
                }
            ],
            "pathHints": [{"packed": 0x1600}],
        }
        out = angr_lite.merge_angr_into_result(result, ang)
        self.assertIn("serverAngr", out["sources"])
        self.assertEqual(len(out["modeTransitions"]), 1)


class UnicornTests(unittest.TestCase):
    def test_merge_unicorn(self) -> None:
        result = {
            "speedLimits": [],
            "notes": [],
            "sources": [],
            "quality": {"hasDeterministicBasis": False, "summary": "x"},
        }
        uni = {
            "ok": True,
            "speeds": [
                {
                    "id": "emu-1600",
                    "kmh": 22.0,
                    "packedU16": 0x1600,
                    "role": "legalCap",
                    "evidence": "Unicorn",
                    "source": "serverEmulation",
                    "confidence": "medium",
                }
            ],
            "notes": ["unicorn=ok"],
            "sites": [{"packed": 0x1600, "executed": True}],
        }
        out = unicorn_emulate.merge_unicorn_into_result(result, uni)
        self.assertIn("serverEmulation", out["sources"])
        self.assertEqual(out["speedLimits"][0]["kmh"], 22.0)

    def test_analyze_without_engine(self) -> None:
        with mock.patch.object(unicorn_emulate, "unicorn_configured", return_value=False):
            out = unicorn_emulate.analyze_firmware(Path("/tmp/nope.bin"))
        self.assertFalse(out["ok"])


if __name__ == "__main__":
    unittest.main()
