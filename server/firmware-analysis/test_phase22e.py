"""Phase 2.2E: inventory, analyzability, FSM validation, scalable matching, completeness."""
from __future__ import annotations

import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import analysis_completeness as ac
import function_matcher as fm
import input_behavior as ib
import reference_inventory as ri

P22E = Path(__file__).resolve().parent / "testdata" / "phase22e"
FSM = P22E / "fsm"
INV = P22E / "inventory"


class ReferenceInventoryTests(unittest.TestCase):
    def test_assess_ivt_ready(self) -> None:
        # Minimal Cortex-M IVT: SP in SRAM, Reset thumb in flash
        import struct

        blob = bytearray(512)
        struct.pack_into("<II", blob, 0, 0x20001000, 0x08000101)
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "vcu.bin"
            p.write_bytes(bytes(blob))
            out = ri.assess_analyzability(p)
            self.assertEqual(out["status"], ri.READY_FOR_ANALYSIS)
            self.assertTrue(out["ivtLikely"])

    def test_assess_no_ivt_architecture_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "ble.bin"
            p.write_bytes(b"\xff" * 300_000)
            out = ri.assess_analyzability(p, ref={"controllerType": "BLE"})
            self.assertEqual(out["status"], ri.ARCHITECTURE_UNKNOWN)

    def test_inventory_snapshot_counts(self) -> None:
        snap = json.loads((INV / "stock_fw_inventory_snapshot.json").read_text(encoding="utf-8"))
        self.assertEqual(snap["count"], 42)
        self.assertEqual(len(snap["references"]), 42)

    def test_inventory_with_temp_manifest(self) -> None:
        import struct

        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            blob = bytearray(1024)
            struct.pack_into("<II", blob, 0, 0x20001000, 0x08000101)
            name = "test_vcu.bin"
            (root / name).write_bytes(bytes(blob))
            sha = __import__("hashlib").sha256(bytes(blob)).hexdigest()
            man = [
                {
                    "id": "t1",
                    "label": "test",
                    "model": "g3",
                    "controllerType": "VCU",
                    "version": "1.0",
                    "source": "oem",
                    "file": name,
                    "sha256": sha,
                    "byteCount": len(blob),
                }
            ]
            (root / "manifest.json").write_text(json.dumps(man), encoding="utf-8")
            with mock.patch.object(ri, "STOCK_FW_DIR", root), mock.patch.object(
                ri, "load_catalog_meta", lambda _s: None
            ):
                # _load_refs uses stock_diff.STOCK_FW_DIR — patch that too
                import stock_diff as sd

                with mock.patch.object(sd, "STOCK_FW_DIR", root):
                    out = ri.inventory_references(root=root, include_file_probe=True)
            self.assertEqual(out["referenceCount"], 1)
            self.assertEqual(out["references"][0]["analyzabilityStatus"], ri.READY_FOR_ANALYSIS)
            # oem source must not become manufacturerVerified automatically
            self.assertEqual(out["references"][0]["referenceTrust"], "communityLibrary")


class CompletenessTests(unittest.TestCase):
    def test_full_vs_truncated(self) -> None:
        full = ac.assess_analysis_completeness(
            function_analysis={"ok": True, "functionCount": 10, "functions": [{}] * 10, "truncated": False}
        )
        self.assertEqual(full["analysisCompleteness"], ac.FULL_ANALYSIS)
        self.assertTrue(full["firmwareAnalysisCoverage"]["unknownTrueFunctionTotal"])
        self.assertIsNone(full["firmwareAnalysisCoverage"]["trueFunctionTotal"])

        trunc = ac.assess_analysis_completeness(
            function_analysis={
                "ok": True,
                "functionCount": 2500,
                "functions": [{}] * 10,
                "truncated": True,
                "truncatedSkipped": 100,
            }
        )
        self.assertEqual(trunc["analysisCompleteness"], ac.TRUNCATED)

    def test_not_supported(self) -> None:
        out = ac.assess_analysis_completeness(analyzability_status="ARCHITECTURE_UNKNOWN")
        self.assertEqual(out["analysisCompleteness"], ac.NOT_SUPPORTED)


class FsmPhase22eTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.syn = json.loads((FSM / "synthetic.functions.json").read_text(encoding="utf-8"))
        cls.gt = json.loads((FSM / "ground_truth.json").read_text(encoding="utf-8"))
        cls.out = ib.analyze_input_behavior(cls.syn)
        cls.by_name = {m["functionName"]: m for m in cls.out["stateMachineAnalysis"]["stateMachines"]}

    def test_branchy_math_not_fsm(self) -> None:
        self.assertNotIn("branchy_math", self.by_name)

    def test_two_state_transitions(self) -> None:
        m = self.by_name["fsm_two_state"]
        self.assertEqual(m["analysisQuality"], ib.FSM_TRANSITIONS)
        self.assertEqual(m["stateCount"], 2)
        self.assertTrue(m["stateCountVerified"])
        self.assertEqual(m["transitionCount"], 1)
        self.assertFalse(m["dynamicRuntimeVerified"])

    def test_three_state_transitions(self) -> None:
        m = self.by_name["fsm_three_state"]
        self.assertEqual(m["analysisQuality"], ib.FSM_TRANSITIONS)
        self.assertEqual(m["stateCount"], 3)
        self.assertEqual(m["transitionCount"], 3)

    def test_switch_case(self) -> None:
        m = self.by_name["fsm_switch"]
        self.assertEqual(m["analysisQuality"], ib.FSM_TRANSITIONS)
        self.assertEqual(m["stateCount"], 4)

    def test_metrics_precision_recall(self) -> None:
        """Precision/Recall only for measurable GT properties on synthetic fixtures."""
        expect_fsm = {
            "fsm_two_state",
            "fsm_three_state",
            "fsm_switch",
            "fsm_if_else",
            "fsm_global_state",
            "fsm_local_state",
            "fsm_on_test_event",
            "fsm_shared_reader",
            "fsm_shared_writer",
        }
        expect_not = {"branchy_math", "reset_handler"}
        # fsm_incomplete may appear as weak CANDIDATE — allowed by GT, not counted as FP
        found = set(self.by_name)
        tp = len(expect_fsm & found)
        fp = len(found & expect_not)
        fn = len(expect_fsm - found)
        prec = tp / max(tp + fp, 1)
        rec = tp / max(tp + fn, 1)
        self.assertEqual(fp, 0, f"false positives={found & expect_not}")
        self.assertGreaterEqual(prec, 0.9, f"tp={tp} fp={fp} fn={fn} found={found}")
        self.assertGreaterEqual(rec, 0.8, f"tp={tp} fp={fp} fn={fn} found={found}")
        # No invented runtime verification
        self.assertFalse(self.out["stateMachineAnalysis"]["stateMachineValidation"]["dynamicRuntimeVerified"])
        FsmPhase22eTests.metrics = {
            "precision": prec,
            "recall": rec,
            "tp": tp,
            "fp": fp,
            "fn": fn,
            "transitionsIdentified": self.out["stateMachineAnalysis"]["transitionsIdentifiedCount"],
        }


class ScalableMatchingTests(unittest.TestCase):
    def test_large_catalog_prefilter_and_truncation(self) -> None:
        # Build >2500 synthetic functions; matching must truncate and stay fast.
        def mk(i: int, *, fp: str | None = None) -> dict:
            return {
                "address": f"{i:08x}",
                "name": f"helper_{i}",
                "size": 8 + (i % 40),
                "basicBlocks": 1 + (i % 3),
                "cfgEdges": 1,
                "calls": [],
                "calledBy": [],
                "constants": [i % 7],
                "strings": [],
                "mnemonics": ["adds", "bx"],
                "fingerprint": fp or f"fp{i:08x}",
            }

        n = 2600
        refs = [mk(i) for i in range(n)]
        # Subject: shifted copies of first 100 + one unique
        subs = [mk(i, fp=f"fp{i:08x}") for i in range(100)]
        subs[0]["address"] = "deadbeef"
        t0 = time.perf_counter()
        out = fm.match_functions(subs + [mk(9999)], refs, max_functions=2500)
        elapsed = time.perf_counter() - t0
        self.assertTrue(out["summary"]["truncated"])
        self.assertLess(elapsed, 3.0, f"matching too slow: {elapsed:.2f}s")
        # Exact fingerprint matches among non-truncated prefix should be HIGH
        matched = [m for m in out["matches"] if m.get("matchConfidence") == fm.CONF_HIGH]
        self.assertGreaterEqual(len(matched), 50)

    def test_prefilter_keeps_identical_helpers_ambiguous(self) -> None:
        leaf = {
            "address": "1",
            "name": "dup_a",
            "size": 4,
            "basicBlocks": 1,
            "cfgEdges": 0,
            "calls": [],
            "calledBy": [],
            "constants": [],
            "strings": [],
            "mnemonics": ["adds", "bx"],
            "fingerprint": "samefp",
        }
        refs = [
            {**leaf, "address": "2", "name": "dup_b"},
            {**leaf, "address": "3", "name": "dup_c"},
        ]
        out = fm.match_functions([{**leaf, "address": "9"}], refs)
        self.assertGreaterEqual(out["summary"]["ambiguous"], 1)


if __name__ == "__main__":
    unittest.main()
