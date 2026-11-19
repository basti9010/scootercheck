"""FunctionDiff against real Ghidra export fixtures (no headless required)."""
from __future__ import annotations

import unittest
from pathlib import Path

from function_analysis import load_function_analysis
from function_diff import (
    STATUS_ADDED,
    STATUS_CHANGED,
    STATUS_IDENTICAL,
    STATUS_REMOVED,
    compare_function_analyses,
)

FIX = Path(__file__).resolve().parent / "testdata" / "thumb_validation" / "meta"


@unittest.skipUnless(
    (FIX / "version_a.functions.json").is_file() and (FIX / "version_b.functions.json").is_file(),
    "fixtures missing",
)
class GhidraExportFixtureTests(unittest.TestCase):
    def test_function_diff_matches_ground_truth(self) -> None:
        a = load_function_analysis(FIX / "version_a.functions.json")
        b = load_function_analysis(FIX / "version_b.functions.json")
        self.assertTrue(a["ok"] and b["ok"])
        self.assertEqual(a.get("processor"), "ARM:LE:32:Cortex")
        diff = compare_function_analyses(b, a)
        by = {}
        for p in diff["pairs"]:
            sn = (p.get("subject") or {}).get("name")
            rn = (p.get("reference") or {}).get("name")
            if p["status"] == STATUS_REMOVED:
                by[rn] = p["status"]
            else:
                by[sn] = p["status"]
        self.assertEqual(by.get("mul_values"), STATUS_IDENTICAL)
        self.assertEqual(by.get("reset_handler"), STATUS_IDENTICAL)
        self.assertEqual(by.get("add_values"), STATUS_CHANGED)
        self.assertEqual(by.get("xor_values"), STATUS_ADDED)
        self.assertEqual(by.get("loop_accumulate"), STATUS_REMOVED)
        # mul fingerprint stable across different addresses
        fa = next(f for f in a["functions"] if f["name"] == "mul_values")
        fb = next(f for f in b["functions"] if f["name"] == "mul_values")
        self.assertEqual(fa["fingerprint"], fb["fingerprint"])
        self.assertNotEqual(fa["address"], fb["address"])


if __name__ == "__main__":
    unittest.main()
