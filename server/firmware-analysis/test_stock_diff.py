"""Unit tests for stock firmware byte-diff."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import stock_diff


class StockDiffTests(unittest.TestCase):
    def test_identical_and_different(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", root):
                stock = b"\x00" * 100 + b"STOCK" + b"\x00" * 50
                stock_diff.register_stock_file(
                    stock,
                    label="ZT3 VCU 1.2.1 Stock",
                    model="zt3",
                    controller_type="VCU",
                    version="1.2.1",
                )
                same = stock_diff.compare_to_stock(stock, models=["zt3"], controller_type="VCU")
                self.assertEqual(same["outcome"], "identical")
                self.assertEqual(same["differingBytes"], 0)

                tweaked = bytearray(stock)
                tweaked[10] = 0xFF
                tweaked[11] = 0xEE
                diff = stock_diff.compare_to_stock(bytes(tweaked), models=["zt3"], controller_type="VCU")
                self.assertEqual(diff["outcome"], "different")
                self.assertGreaterEqual(diff["differingBytes"], 2)
                self.assertEqual(diff["firstDiffOffset"], 10)

    def test_no_reference(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", Path(td)):
                out = stock_diff.compare_to_stock(b"\x01\x02\x03", models=["zt3"])
                self.assertEqual(out["outcome"], "noReference")

    def test_list_and_delete(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", Path(td)):
                ref = stock_diff.register_stock_file(
                    b"abc123",
                    label="t",
                    model="g3",
                    controller_type="VCU",
                    version="1.0.0",
                )
                self.assertEqual(len(stock_diff.list_stock_refs()), 1)
                self.assertTrue(stock_diff.delete_stock_ref(ref["id"]))
                self.assertEqual(len(stock_diff.list_stock_refs()), 0)


if __name__ == "__main__":
    unittest.main()
