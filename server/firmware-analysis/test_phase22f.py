"""Phase 2.2F: callgraph quality, BLE container, catalog batch, FSM runtime."""
from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import ble_container as ble
import callgraph_quality as cq
import catalog_batch as cb
import fsm_runtime as fr

P22F = Path(__file__).resolve().parent / "testdata" / "phase22f"


class CallgraphQualityTests(unittest.TestCase):
    def test_ground_truth_cases(self) -> None:
        gt = json.loads((P22F / "callgraph_ground_truth.json").read_text(encoding="utf-8"))
        tp = fp = fn = 0
        for case in gt["cases"]:
            if case.get("edge") is None:
                continue
            got = cq.classify_edge(case["edge"])
            exp = case["expect"]
            if got == exp:
                tp += 1
            else:
                fp += 1
                fn += 1
                self.fail(f"{case['id']}: got {got} expected {exp}")
        prec = tp / max(tp + fp, 1)
        rec = tp / max(tp + fn, 1)
        self.assertEqual(prec, 1.0)
        self.assertEqual(rec, 1.0)

    def test_legacy_unresolved_jumps_not_counted_as_unresolved_calls(self) -> None:
        legacy = {
            "ok": True,
            "edges": [
                {"from": "1", "to": "2", "toName": "f", "kind": "direct", "evidence": "static"},
                {"from": "1", "to": "1+4", "toName": None, "kind": "jump", "evidence": "unresolved"},
                {"from": "1", "to": "99", "toName": None, "kind": "call", "evidence": "unresolved"},
            ],
            "edgeCount": 3,
            "unresolvedCount": 2,
        }
        q = cq.analyze_callgraph_quality(legacy)
        self.assertEqual(q["directCalls"], 1)
        self.assertEqual(q["unresolvedCalls"], 1)
        self.assertEqual(q["unknownControlFlow"], 1)
        self.assertEqual(q["internalBranches"], 0)

    def test_embedded_quality_preferred(self) -> None:
        cg = {
            "ok": True,
            "edges": [],
            "edgeCount": 10,
            "callGraphQuality": {
                "directCalls": 4,
                "indirectCalls": 1,
                "internalBranches": 3,
                "tailCalls": 1,
                "unresolvedCalls": 1,
                "unknownControlFlow": 0,
            },
        }
        q = cq.analyze_callgraph_quality(cg)
        self.assertEqual(q["internalBranches"], 3)
        self.assertEqual(q["unresolvedCalls"], 1)
        self.assertEqual(q["source"], "ghidra_export")


class BleContainerTests(unittest.TestCase):
    def _raw4tft(self, payload: bytes, header_size: int = 0x400) -> bytes:
        header = bytearray(header_size)
        header[0:8] = ble.RAW4TFT_MAGIC
        struct.pack_into("<I", header, 12, len(payload))
        struct.pack_into("<I", header, 0x18, header_size)
        return bytes(header) + payload

    def test_raw4tft_extract(self) -> None:
        # Minimal Cortex-M IVT payload
        payload = bytearray(512)
        struct.pack_into("<II", payload, 0, 0x20001000, 0x08000101)
        blob = self._raw4tft(bytes(payload))
        out = ble.identify_ble_container(blob, original_name="x_BLE_0.1.bin")
        self.assertTrue(out["containerRecognized"])
        self.assertEqual(out["format"], "RAW4TFT")
        self.assertTrue(out["imageExtractable"])
        self.assertEqual(out["components"][0]["offset"], 0x400)
        self.assertEqual(len(out["components"][0]["sha256"]), 64)

    def test_no_filename_forced_arch(self) -> None:
        # High-entropy-ish payload without IVT
        payload = bytes([i % 256 for i in range(512)])
        blob = self._raw4tft(payload)
        out = ble.identify_ble_container(blob, original_name="something_BLE.bin")
        self.assertTrue(out["containerRecognized"])
        # Without IVT must not invent STM32 arch certainty
        if not out.get("processorRecognized"):
            self.assertTrue(out.get("architectureUnknown") or out["status"] in {
                ble.ARCHITECTURE_UNKNOWN,
                ble.IMAGE_EXTRACTABLE,
                ble.CONTAINER_RECOGNIZED,
            })

    def test_non_container(self) -> None:
        out = ble.identify_ble_container(b"\x00" * 1000)
        self.assertEqual(out["status"], ble.FORMAT_UNSUPPORTED)


class CatalogBatchTests(unittest.TestCase):
    def test_batch_without_ghidra_reports_error(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(cb, "ghidra_configured", return_value=False):
                out = cb.run_catalog_batch(limit=2, batch_root=Path(td))
            self.assertFalse(out["ok"])
            self.assertIn("ghidra", (out.get("error") or "").lower())
            self.assertFalse(out.get("productiveCatalogsModified", True))

    def test_default_batch_root_isolated(self) -> None:
        root = cb.default_batch_root()
        self.assertTrue(str(root).startswith("/tmp") or "batch" in str(root).lower())
        self.assertNotIn("stock_fw", str(root).lower().replace("-", "_"))


class ApiCompatTests(unittest.TestCase):
    def test_poll_summary_keeps_legacy_fields(self) -> None:
        from function_analysis import summarize_call_graph_for_poll

        full = {
            "ok": True,
            "schemaVersion": 2,
            "edges": [
                {"from": "1", "to": "2", "toName": "f", "kind": "direct", "evidence": "static", "classification": "DIRECT_CALL"},
                {"from": "1", "to": "1+4", "kind": "jump", "evidence": "internal", "classification": "INTERNAL_BRANCH"},
            ],
            "edgeCount": 2,
            "unresolvedCount": 0,
            "callGraphQuality": {
                "directCalls": 1,
                "indirectCalls": 0,
                "internalBranches": 1,
                "tailCalls": 0,
                "unresolvedCalls": 0,
                "unknownControlFlow": 0,
            },
            "notes": [],
            "analysisLimitations": [],
        }
        poll = summarize_call_graph_for_poll(full)
        self.assertIn("edgeCount", poll)
        self.assertIn("unresolvedCount", poll)
        self.assertEqual(poll["callGraphQuality"]["internalBranches"], 1)
        self.assertEqual(poll["callGraphQuality"]["directCalls"], 1)


class FsmRuntimeTests(unittest.TestCase):
    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_two_state_transition_observed(self) -> None:
        prog = fr.build_two_state_program()
        out = fr.run_fsm_program(prog)
        self.assertTrue(out["ok"])
        self.assertEqual(out["finalState"], 1)
        self.assertTrue(out["observedTransitions"])
        self.assertEqual(out["evidenceTier"], fr.RUNTIME_TRANSITION_OBSERVED)
        self.assertTrue(out["dynamicRuntimeVerified"])
        self.assertTrue(
            any("fahrzeug" in x.lower() for x in out["analysisLimitations"]),
            out["analysisLimitations"],
        )

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_no_transition(self) -> None:
        prog = fr.build_no_transition_program()
        out = fr.run_fsm_program(prog)
        self.assertTrue(out["ok"])
        self.assertEqual(out["finalState"], 0)
        self.assertEqual(out["observedTransitions"], [])

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_suite_reproducible(self) -> None:
        a = fr.run_fsm_runtime_suite()
        b = fr.run_fsm_runtime_suite()
        self.assertEqual(a["runtimeTransitionsObserved"], b["runtimeTransitionsObserved"])
        self.assertTrue(a["dynamicRuntimeVerified"])
        self.assertTrue(a.get("threeStateReproducible"))
        self.assertTrue(b.get("threeStateReproducible"))

    def test_unavailable_marked_not_verifiable(self) -> None:
        with mock.patch.object(fr, "unicorn_fsm_available", return_value=False):
            out = fr.run_fsm_program(fr.build_two_state_program())
        self.assertFalse(out["ok"])
        self.assertEqual(out["evidenceTier"], fr.NOT_VERIFIABLE)
        self.assertFalse(out["dynamicRuntimeVerified"])


if __name__ == "__main__":
    unittest.main()
