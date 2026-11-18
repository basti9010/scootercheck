"""Phase-2 function analysis / diff / LLM verify unit tests."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import function_diff as fd
import function_analysis as fa
import llm_verify


def _fn(addr: str, name: str, size: int, blocks: int, edges: int, fp: str, calls=None):
    return {
        "address": addr,
        "name": name,
        "size": size,
        "basicBlocks": blocks,
        "cfgEdges": edges,
        "calls": calls or [],
        "calledBy": [],
        "constants": [],
        "strings": [],
        "fingerprint": fp,
        "confidence": "medium",
    }


class FunctionDiffTests(unittest.TestCase):
    def test_identical_functions(self) -> None:
        f = _fn("0x08001000", "FUN_a", 64, 4, 5, "aaa111")
        a = {"ok": True, "functions": [f]}
        b = {"ok": True, "functions": [dict(f)]}
        out = fd.compare_function_analyses(a, b)
        self.assertEqual(out["summary"]["identical"], 1)
        self.assertEqual(out["pairs"][0]["status"], fd.STATUS_IDENTICAL)

    def test_structurally_changed(self) -> None:
        a = {
            "ok": True,
            "functions": [_fn("0x08001000", "FUN_a", 64, 4, 5, "aaa111", calls=["x"])],
        }
        b = {
            "ok": True,
            "functions": [_fn("0x08001000", "FUN_a", 96, 8, 10, "bbb222", calls=["y"])],
        }
        out = fd.compare_function_analyses(a, b)
        self.assertEqual(out["summary"]["structurallyChanged"], 1)
        self.assertEqual(out["pairs"][0]["status"], fd.STATUS_CHANGED)

    def test_added_and_removed(self) -> None:
        a = {"ok": True, "functions": [_fn("0x1", "FUN_new", 10, 1, 1, "n1")]}
        b = {"ok": True, "functions": [_fn("0x2", "FUN_old", 10, 1, 1, "o1")]}
        out = fd.compare_function_analyses(a, b)
        self.assertEqual(out["summary"]["added"], 1)
        self.assertEqual(out["summary"]["removed"], 1)

    def test_uncomparable_missing_reference(self) -> None:
        a = {"ok": True, "functions": [_fn("0x1", "FUN_a", 10, 1, 1, "x")]}
        out = fd.compare_function_analyses(a, None)
        self.assertEqual(out["summary"].get("overall"), fd.STATUS_UNCOMPARABLE)
        self.assertTrue(any("Referenz" in x or "Referenz" in x for x in out["analysisLimitations"]))

    def test_empty_function_lists(self) -> None:
        out = fd.compare_function_analyses({"ok": True, "functions": []}, {"ok": True, "functions": []})
        self.assertEqual(out["summary"].get("overall"), fd.STATUS_UNCOMPARABLE)

    def test_bad_ghidra_export(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "bad.json"
            p.write_text("{not-json", encoding="utf-8")
            loaded = fa.load_function_analysis(p)
            self.assertFalse(loaded["ok"])
            out = fd.compare_function_analyses(loaded, {"ok": True, "functions": []})
            self.assertIn("Subject", out["notes"][0])

    def test_poll_summary_truncates(self) -> None:
        fns = [_fn(f"0x{i:08x}", f"FUN_{i}", 8, 1, 1, f"fp{i}") for i in range(100)]
        full = {"ok": True, "functions": fns, "functionCount": 100, "notes": []}
        summary = fa.summarize_for_poll(full)
        self.assertLessEqual(len(summary["sampleFunctions"]), fa.MAX_SUMMARY_FUNCTIONS)
        self.assertNotIn("functions", summary)  # default poll omits full list

    def test_api_backward_compatible_keys(self) -> None:
        # Existing clients ignore unknown keys; summary must still have stockDiff-style freedom.
        diff = fd.compare_function_analyses(
            {"ok": True, "functions": [_fn("0x1", "A", 1, 1, 1, "x")]},
            {"ok": True, "functions": [_fn("0x1", "A", 1, 1, 1, "x")]},
        )
        poll = fd.summarize_diff_for_poll(diff)
        for key in ("ok", "summary", "analysisLimitations", "notes"):
            self.assertIn(key, poll)
        self.assertIn("overall", poll["summary"])
        self.assertEqual(poll["summary"]["overall"], fd.STATUS_IDENTICAL)


class LlmVerifyTests(unittest.TestCase):
    def test_valid_function_claim(self) -> None:
        fa_blob = {
            "ok": True,
            "functions": [_fn("0x08001234", "FUN_08001234", 32, 2, 2, "z")],
        }
        result = {
            "comboSummaries": ["Hinweis in FUN_08001234 @ 0x08001234"],
            "modeTransitions": [],
            "inputHints": [],
            "notes": [],
            "sources": ["serverLLM"],
        }
        out = llm_verify.verify_enrichment(result, function_analysis=fa_blob, plaintext_size=0x10000)
        self.assertEqual(len(out["comboSummaries"]), 1)
        self.assertGreaterEqual(out["llmVerification"]["verified"], 1)

    def test_invalid_address_dropped(self) -> None:
        fa_blob = {"ok": True, "functions": [_fn("0x08001000", "FUN_08001000", 8, 1, 1, "a")]}
        result = {
            "comboSummaries": ["Rätsel bei FUN_deadbeef @ 0xDEADBEEF"],
            "modeTransitions": [
                {
                    "id": "t1",
                    "title": "x",
                    "trigger": "y",
                    "effect": "z",
                    "evidence": "FUN_missing @ 0xFFFFFFFF",
                    "source": "serverLLM",
                    "confidence": "low",
                }
            ],
            "inputHints": [],
            "notes": [],
        }
        out = llm_verify.verify_enrichment(result, function_analysis=fa_blob, plaintext_size=0x1000)
        self.assertEqual(out["comboSummaries"], [])
        self.assertEqual(out["modeTransitions"], [])
        self.assertGreaterEqual(out["llmVerification"]["dropped"], 1)

    def test_timeout_style_empty_export(self) -> None:
        # Simulates aborted/empty export after timeout — compare stays honest.
        out = fd.compare_function_analyses(
            {"ok": False, "functions": [], "notes": ["timeout"]},
            {"ok": True, "functions": [_fn("0x1", "A", 1, 1, 1, "x")]},
        )
        self.assertEqual(out["summary"].get("overall"), fd.STATUS_UNCOMPARABLE)


class CallGraphLoadTests(unittest.TestCase):
    def test_load_callgraph(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "cg.json"
            p.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "edges": [
                            {
                                "from": "0x1",
                                "fromName": "A",
                                "to": "0x2",
                                "toName": "B",
                                "kind": "direct",
                                "evidence": "static",
                            }
                        ],
                        "edgeCount": 1,
                        "heuristicCount": 0,
                        "unresolvedCount": 0,
                    }
                ),
                encoding="utf-8",
            )
            loaded = fa.load_call_graph(p)
            self.assertTrue(loaded["ok"])
            self.assertEqual(loaded["edgeCount"], 1)
            poll = fa.summarize_call_graph_for_poll(loaded)
            self.assertEqual(len(poll["sampleEdges"]), 1)


if __name__ == "__main__":
    unittest.main()
