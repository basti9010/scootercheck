"""Ghidra headless integration tests (Phase 2.1).

Skipped automatically when analyzeHeadless is not configured.
Uses tiny synthetic ARM/Thumb-like blobs only — never touches stock-fw.
"""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from function_diff import compare_function_analyses, STATUS_CHANGED, STATUS_IDENTICAL
from function_analysis import load_call_graph, load_function_analysis
from ghidra_decompile import ghidra_configured, run_ghidra_decompile


def _tiny_arm_blob(variant: int = 0) -> bytes:
    """Minimal padded blob — may yield 0 functions; still exercises headless import."""
    # Simple repeating pattern with a few Thumb-ish opcodes; Ghidra may or may not
    # create functions without IVT — test asserts pipeline resilience either way.
    base = bytes([0x00, 0xBF, 0x70, 0x47, 0x00, 0xBF, 0x70, 0x47])  # nop; bx lr
    pad = bytes([(i + variant) % 256 for i in range(256)])
    return base * 8 + pad + bytes([variant & 0xFF]) * 16


@unittest.skipUnless(ghidra_configured(), "Ghidra headless not configured (GHIDRA_HOME/GHIDRA_HEADLESS)")
class GhidraIntegrationTests(unittest.TestCase):
    def test_headless_export_pipeline(self) -> None:
        timeout = int(os.environ.get("GHIDRA_TEST_TIMEOUT_SEC", "180") or "180")
        with tempfile.TemporaryDirectory(prefix="ghidra-it-") as td:
            td_path = Path(td)
            bin_path = td_path / "tiny.bin"
            bin_path.write_bytes(_tiny_arm_blob(0))
            out_c = td_path / "out.dec.c"
            functions_json = td_path / "out.functions.json"
            callgraph_json = td_path / "out.callgraph.json"
            ok, msg = run_ghidra_decompile(
                bin_path,
                out_c,
                processor="ARM:LE:32:Cortex",
                base_addr="0x08000000",
                timeout_sec=timeout,
                functions_json=functions_json,
                callgraph_json=callgraph_json,
            )
            self.assertTrue(ok, msg)
            self.assertTrue(out_c.is_file() and out_c.stat().st_size > 0)
            # Phase-2 exports are best-effort; if present they must be valid JSON.
            if functions_json.is_file() and functions_json.stat().st_size > 0:
                data = json.loads(functions_json.read_text(encoding="utf-8"))
                self.assertIn("functions", data)
                loaded = load_function_analysis(functions_json)
                self.assertTrue(loaded["ok"])
                if loaded.get("processor"):
                    self.assertIn("ARM", str(loaded["processor"]))
            if callgraph_json.is_file() and callgraph_json.stat().st_size > 0:
                cg = load_call_graph(callgraph_json)
                self.assertTrue(cg["ok"])

    def test_function_diff_on_two_variants(self) -> None:
        timeout = int(os.environ.get("GHIDRA_TEST_TIMEOUT_SEC", "180") or "180")
        with tempfile.TemporaryDirectory(prefix="ghidra-it2-") as td:
            td_path = Path(td)
            results = []
            for i in (0, 1):
                bin_path = td_path / f"v{i}.bin"
                bin_path.write_bytes(_tiny_arm_blob(i))
                out_c = td_path / f"v{i}.dec.c"
                fj = td_path / f"v{i}.functions.json"
                ok, msg = run_ghidra_decompile(
                    bin_path,
                    out_c,
                    timeout_sec=timeout,
                    functions_json=fj,
                    callgraph_json=td_path / f"v{i}.callgraph.json",
                )
                self.assertTrue(ok, msg)
                results.append(load_function_analysis(fj if fj.is_file() else None))
            diff = compare_function_analyses(results[0], results[1])
            # Either both empty → NICHT_VERGLEICHBAR, or a structured summary exists.
            self.assertIn("summary", diff)
            self.assertTrue(any("Manipulationsnachweis" in x for x in diff.get("analysisLimitations") or []))
            # If both have the same synthetic fingerprint set, identical is fine.
            if (results[0].get("functionCount") or 0) == 0 and (results[1].get("functionCount") or 0) == 0:
                self.assertEqual(diff["summary"].get("overall"), "NICHT_VERGLEICHBAR")


class GhidraIntegrationSkippedMarkerTests(unittest.TestCase):
    def test_documents_skip_when_unavailable(self) -> None:
        if ghidra_configured():
            self.skipTest("Ghidra available — real integration tests run above")
        self.assertFalse(ghidra_configured())


if __name__ == "__main__":
    unittest.main()
