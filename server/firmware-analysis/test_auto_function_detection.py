"""Evaluate automatic Thumb function detection against documented ground truth.

Does not require Ghidra — scores exported function JSON (or runs identify-only checks).
When GHIDRA is configured, optionally runs headless WITHOUT CreateKnownThumbFunctions.
"""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

from firmware_identify import identify_firmware_image
from function_analysis import load_function_analysis
from function_diff import compare_function_analyses
from ghidra_decompile import ghidra_configured, run_ghidra_decompile

ROOT = Path(__file__).resolve().parent
FIX = ROOT / "testdata" / "thumb_validation"
GT_PATH = FIX / "meta" / "ground_truth.json"


def _norm_addr(a: str | int) -> str:
    if isinstance(a, int):
        return f"0x{a:08x}"
    s = str(a).lower().replace("0x", "")
    return f"0x{int(s, 16):08x}"


def _score(detected_addrs: set[str], truth_addrs: set[str]) -> dict:
    tp = detected_addrs & truth_addrs
    fp = detected_addrs - truth_addrs
    fn = truth_addrs - detected_addrs
    precision = (len(tp) / len(detected_addrs)) if detected_addrs else 0.0
    recall = (len(tp) / len(truth_addrs)) if truth_addrs else 0.0
    return {
        "truePositives": sorted(tp),
        "falsePositives": sorted(fp),
        "falseNegatives": sorted(fn),
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "detectedCount": len(detected_addrs),
        "truthCount": len(truth_addrs),
    }


class AutoFunctionDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not GT_PATH.is_file():
            raise unittest.SkipTest("ground_truth.json missing")
        cls.gt = json.loads(GT_PATH.read_text(encoding="utf-8"))

    def test_identify_version_a_before_ghidra(self) -> None:
        path = FIX / "bin" / "version_a.bin"
        out = identify_firmware_image(path)
        self.assertTrue(out["ok"])
        self.assertEqual(out["baseAddr"].lower(), "0x08000000")
        self.assertTrue(out["thumbLikely"])
        self.assertFalse(out["architectureUnknown"])
        reset = next(e for e in out["entryPoints"] if e.get("name") == "reset")
        self.assertEqual(_norm_addr(reset["address"]), _norm_addr(self.gt["version_a"]["functions"]["reset_handler"]))

    def test_score_fixture_export_against_ground_truth(self) -> None:
        """If a prior export exists under meta/, score it; else skip."""
        export = FIX / "meta" / "version_a.functions.json"
        if not export.is_file():
            self.skipTest("no prior export fixture")
        loaded = load_function_analysis(export)
        truth = {_norm_addr(v) for v in self.gt["version_a"]["functions"].values()}
        detected = set()
        for fn in loaded.get("functions") or []:
            addr = fn.get("address") or fn.get("entry") or fn.get("addr")
            if addr:
                detected.add(_norm_addr(addr))
        score = _score(detected, truth)
        # Fixture may have been produced WITH CreateKnownThumbFunctions — expect high recall.
        self.assertGreaterEqual(score["recall"], 0.5, score)

    @unittest.skipUnless(ghidra_configured(), "Ghidra headless not configured")
    def test_ghidra_auto_detect_without_known_script(self) -> None:
        timeout = int(os.environ.get("GHIDRA_TEST_TIMEOUT_SEC", "300") or "300")
        path = FIX / "bin" / "version_a.bin"
        with tempfile.TemporaryDirectory(prefix="auto-fn-") as td:
            td_path = Path(td)
            out_c = td_path / "a.dec.c"
            fj = td_path / "a.functions.json"
            cg = td_path / "a.callgraph.json"
            ok, msg = run_ghidra_decompile(
                path,
                out_c,
                processor="ARM:LE:32:Cortex",
                base_addr="0x08000000",
                timeout_sec=timeout,
                functions_json=fj,
                callgraph_json=cg,
                seed_ivt_entry_points=True,
                auto_identify=True,
            )
            self.assertTrue(ok, msg)
            loaded = load_function_analysis(fj)
            truth = {_norm_addr(v) for v in self.gt["version_a"]["functions"].values()}
            detected = set()
            for fn in loaded.get("functions") or []:
                addr = fn.get("address") or fn.get("entry") or fn.get("addr")
                if addr:
                    detected.add(_norm_addr(addr))
            score = _score(detected, truth)
            # Must beat the historical "1 function without helper script" baseline.
            self.assertGreaterEqual(score["detectedCount"], 2, score)
            self.assertGreaterEqual(score["recall"], 0.5, score)
            # Persist metrics for the report artifact
            (td_path / "metrics.json").write_text(json.dumps(score, indent=2), encoding="utf-8")
            print("AUTO_DETECT_METRICS", json.dumps(score))

    @unittest.skipUnless(ghidra_configured(), "Ghidra headless not configured")
    def test_function_diff_after_auto_detect(self) -> None:
        timeout = int(os.environ.get("GHIDRA_TEST_TIMEOUT_SEC", "300") or "300")
        with tempfile.TemporaryDirectory(prefix="auto-diff-") as td:
            td_path = Path(td)
            loaded = []
            for name in ("version_a", "version_b"):
                out_c = td_path / f"{name}.dec.c"
                fj = td_path / f"{name}.functions.json"
                ok, msg = run_ghidra_decompile(
                    FIX / "bin" / f"{name}.bin",
                    out_c,
                    timeout_sec=timeout,
                    functions_json=fj,
                    callgraph_json=td_path / f"{name}.callgraph.json",
                    seed_ivt_entry_points=True,
                    auto_identify=True,
                )
                self.assertTrue(ok, msg)
                loaded.append(load_function_analysis(fj))
            diff = compare_function_analyses(loaded[0], loaded[1])
            self.assertIn("summary", diff)
            # With real function discovery, should not be empty NICHT_VERGLEICHBAR solely from 0 funcs
            if (loaded[0].get("functionCount") or 0) >= 2 and (loaded[1].get("functionCount") or 0) >= 2:
                self.assertNotEqual(diff["summary"].get("overall"), "NICHT_VERGLEICHBAR")


if __name__ == "__main__":
    unittest.main()
