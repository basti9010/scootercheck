"""Unit tests for radare2 extract helpers (mocked subprocess)."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import r2_extract


class R2ParseTests(unittest.TestCase):
    def test_parse_speed_hits(self) -> None:
        out = """
0x08001234 hit0_0 0016
0x08004567 hit1_0 0063
garbage
0x08009999 hit2_0 0016
"""
        speeds = r2_extract._parse_speed_hits(out)
        packed = {s["packedU16"] for s in speeds}
        self.assertIn(0x1600, packed)
        self.assertIn(0x6300, packed)
        self.assertEqual(len(speeds), 2)

    def test_merge_adds_source(self) -> None:
        result = {
            "speedLimits": [],
            "notes": [],
            "sources": ["serverDecompile"],
            "quality": {"hasDeterministicBasis": False, "summary": "x"},
        }
        r2 = {
            "ok": True,
            "speeds": [
                {
                    "id": "r2-1600",
                    "kmh": 22.0,
                    "packedU16": 0x1600,
                    "role": "legalCap",
                    "evidence": "r2",
                    "source": "serverR2",
                    "confidence": "high",
                }
            ],
            "notes": ["r2=ok"],
            "stringsSample": ["ascii speed_limit"],
        }
        out = r2_extract.merge_r2_into_result(result, r2)
        self.assertIn("serverR2", out["sources"])
        self.assertEqual(out["speedLimits"][0]["kmh"], 22.0)
        self.assertEqual(out["r2StringsSample"], ["ascii speed_limit"])


class R2AnalyzeMockTests(unittest.TestCase):
    def test_analyze_uses_r2_output(self) -> None:
        fake = "0x08001000 hit0_0 0016\n0x08002000 12 13 ascii throttle_adc\n"
        with tempfile.TemporaryDirectory() as td:
            bin_path = Path(td) / "f.bin"
            bin_path.write_bytes(b"\x00\x16" + b"\x00" * 64)
            with mock.patch.object(r2_extract, "r2_configured", return_value=True):
                with mock.patch("r2_extract.subprocess.run") as run:
                    run.return_value = mock.Mock(stdout=fake, stderr="", returncode=0)
                    info = r2_extract.analyze_firmware(bin_path)
            self.assertTrue(info["ok"])
            self.assertEqual(info["speeds"][0]["packedU16"], 0x1600)


if __name__ == "__main__":
    unittest.main()
