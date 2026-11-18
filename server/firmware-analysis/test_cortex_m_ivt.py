"""Tests for Cortex-M IVT parser and stock OEM tagging."""
from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import cortex_m_ivt
import stock_diff


class IvtTests(unittest.TestCase):
    def test_likely_cortex_m(self) -> None:
        # SP in SRAM, Reset Thumb in flash @ 0x08000101 → file off 0x100
        blob = bytearray(512)
        struct.pack_into("<I", blob, 0, 0x20020000)
        struct.pack_into("<I", blob, 4, 0x08000101)
        out = cortex_m_ivt.parse_ivt(bytes(blob))
        self.assertTrue(out["likely"])
        self.assertEqual(out["resetFileOffset"], 0x100)
        self.assertTrue(out["resetThumb"])

    def test_unlikely_noise(self) -> None:
        out = cortex_m_ivt.parse_ivt(b"\xff" * 64)
        self.assertTrue(out["ok"])
        self.assertFalse(out["likely"])


class StockOemTests(unittest.TestCase):
    def test_case_source_ignored_in_compare(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", Path(td)):
                stock = b"OEMREF" + b"\x00" * 40
                stock_diff.register_stock_file(
                    stock,
                    label="case upload",
                    model="zt3",
                    controller_type="VCU",
                    version="1",
                    source="case",
                )
                out = stock_diff.compare_to_stock(stock, models=["zt3"])
                self.assertEqual(out["outcome"], "noReference")
                self.assertIn("oem/serial", out["note"].lower())

    def test_oem_trusted(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", Path(td)):
                stock = b"OEMREF" + b"\x00" * 40
                ref = stock_diff.register_stock_file(
                    stock,
                    label="OEM",
                    model="zt3",
                    controller_type="VCU",
                    version="1",
                    source="oem",
                    region="DE",
                )
                self.assertTrue(ref["trusted"])
                self.assertEqual(ref["source"], "oem")
                out = stock_diff.compare_to_stock(stock, models=["zt3"])
                self.assertEqual(out["outcome"], "identical")
                self.assertEqual(out["referenceSource"], "oem")


if __name__ == "__main__":
    unittest.main()
