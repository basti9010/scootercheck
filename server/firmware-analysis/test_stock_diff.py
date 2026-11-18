"""Unit tests for stock firmware byte-diff."""
from __future__ import annotations

import json
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
                    source="oem",
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

    def test_far_match_becomes_no_reference(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", root):
                stock = b"\x00" * 200
                stock_diff.register_stock_file(
                    stock,
                    label="ZT3 VCU Stock",
                    model="zt3",
                    controller_type="VCU",
                    version="1.0",
                    source="oem",
                )
                far = b"\xff" * 200
                out = stock_diff.compare_to_stock(far, models=["zt3"], controller_type="VCU")
                self.assertEqual(out["outcome"], "noReference")
                self.assertIn("zu stark ab", out["note"])
                self.assertGreater(out.get("percentDifferent") or 0, 25)

    def test_strict_no_cross_model_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", root):
                stock = b"\x00" * 80 + b"G3STOCK" + b"\x00" * 40
                stock_diff.register_stock_file(
                    stock,
                    label="G3 VCU Stock",
                    model="g3",
                    controller_type="VCU",
                    version="1.5.15",
                    source="oem",
                )
                # ZT3 must not silently compare against G3 OEM
                out = stock_diff.compare_to_stock(
                    b"\xff" * len(stock),
                    models=["zt3"],
                    controller_type="VCU",
                )
                self.assertEqual(out["outcome"], "noReference")
                self.assertIn("Kein Cross-Model-Fallback", out["note"])
                self.assertEqual(out.get("candidateRefCount"), 0)

    def test_multi_model_alias_and_region_flags(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", root):
                # Embed panic + limit markers so region tagging can fire
                base = bytearray(b"\x00" * 200)
                base[40:45] = b"panic"
                base[100:105] = b"speed"
                base[120:124] = bytes([25, 0, 0, 0])
                stock = bytes(base)
                ref = stock_diff.register_stock_file(
                    stock,
                    label="Rexzy67 Stock f3/g3 VCU 1.0",
                    model="f3",
                    controller_type="VCU",
                    version="1.0",
                    source="oem",
                    notes="models=f3,g3",
                )
                # Simulate multi-model alias as on Hetzner
                man = root / "manifest.json"
                entries = json.loads(man.read_text(encoding="utf-8"))
                for e in entries:
                    if e.get("sha256") == ref["sha256"]:
                        e["models"] = ["f3", "g3"]
                man.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")

                tweaked = bytearray(stock)
                tweaked[42] = 0x41  # inside "panic"
                tweaked[102] = 0x42  # inside "speed"
                diff = stock_diff.compare_to_stock(
                    bytes(tweaked),
                    models=["g3"],
                    controller_type="VCU",
                )
                self.assertEqual(diff["outcome"], "different")
                self.assertGreaterEqual(diff["differingBytes"], 2)
                self.assertTrue(diff.get("panicRegionAffected"))
                self.assertTrue(diff.get("limitRegionAffected"))
                self.assertIn("g3", diff.get("matchedModels") or [])

    def test_list_and_delete(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(stock_diff, "STOCK_FW_DIR", Path(td)):
                ref = stock_diff.register_stock_file(
                    b"abc123",
                    label="t",
                    model="g3",
                    controller_type="VCU",
                    version="1.0.0",
                    source="serial",
                )
                self.assertEqual(len(stock_diff.list_stock_refs()), 1)
                self.assertTrue(stock_diff.delete_stock_ref(ref["id"]))
                self.assertEqual(len(stock_diff.list_stock_refs()), 0)


if __name__ == "__main__":
    unittest.main()
