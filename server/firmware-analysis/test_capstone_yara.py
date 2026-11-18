"""Tests for Capstone + YARA helpers (Capstone/YARA optional at runtime)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import yara_scan


class YaraScanTests(unittest.TestCase):
    def test_scan_detects_legal_and_open(self) -> None:
        if not yara_scan.yara_configured():
            self.skipTest("yara-python not installed")
        # LE bytes: 0x1600 + 0x6300
        blob = b"\x00" * 32 + b"\x00\x16" + b"\x00" * 8 + b"\x00\x63" + b"\x00" * 32
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "t.bin"
            p.write_bytes(blob)
            out = yara_scan.scan_firmware(p)
        self.assertTrue(out["ok"])
        rules = {m["rule"] for m in out["matches"]}
        self.assertIn("Ninebot_Legal_And_Open_Together", rules)

    def test_merge_adds_yara_not_combo(self) -> None:
        result = {"notes": [], "sources": [], "comboSummaries": [], "quality": {"summary": "x"}}
        yr = {
            "ok": True,
            "matches": [
                {
                    "rule": "Ninebot_Legal_And_Open_Together",
                    "description": "legal+open",
                    "confidence": "high",
                    "tags": [],
                    "strings": [],
                }
            ],
            "notes": ["yara=ok"],
        }
        out = yara_scan.merge_yara_into_result(result, yr)
        self.assertIn("serverYara", out["sources"])
        self.assertEqual(out["comboSummaries"], [])
        self.assertTrue(any("yara:Ninebot_Legal_And_Open_Together" in n for n in out["notes"]))


class CapstoneMergeTests(unittest.TestCase):
    def test_merge_capstone(self) -> None:
        import capstone_extract

        result = {
            "speedLimits": [],
            "notes": [],
            "sources": [],
            "quality": {"hasDeterministicBasis": False, "summary": "x"},
        }
        cs = {
            "ok": True,
            "speeds": [
                {
                    "id": "cs-1",
                    "kmh": 22.0,
                    "packedU16": 0x1600,
                    "role": "legalCap",
                    "evidence": "t",
                    "source": "serverCapstone",
                    "confidence": "high",
                }
            ],
            "notes": ["capstone=ok"],
        }
        out = capstone_extract.merge_capstone_into_result(result, cs)
        self.assertIn("serverCapstone", out["sources"])
        self.assertEqual(out["speedLimits"][0]["kmh"], 22.0)


if __name__ == "__main__":
    unittest.main()
