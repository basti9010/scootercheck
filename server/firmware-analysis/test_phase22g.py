"""Phase 2.2G: analysis profile, reproducibility helpers, BLE confidence, FSM multi-step."""
from __future__ import annotations

import json
import struct
import unittest
from pathlib import Path
from unittest import mock

import analysis_profile as ap
import ble_container as ble
import fsm_runtime as fr
import ghidra_reproducibility as gr
import reference_catalog as rc


class AnalysisProfileTests(unittest.TestCase):
    def test_profile_hash_stable(self) -> None:
        a = ap.build_analysis_profile(processor="ARM:LE:32:Cortex", loader_base="0x08000000", seed_ivt=True)
        b = ap.build_analysis_profile(processor="ARM:LE:32:Cortex", loader_base="0x08000000", seed_ivt=True)
        self.assertEqual(a["analysisProfileHash"], b["analysisProfileHash"])
        self.assertEqual(a["analysisProfileVersion"], "2.2G.1")
        self.assertIn("SeedCortexMEntryPoints.java", a["enabledPreScripts"])

    def test_profile_hash_changes_with_seed(self) -> None:
        a = ap.build_analysis_profile(seed_ivt=True)
        b = ap.build_analysis_profile(seed_ivt=False)
        self.assertNotEqual(a["analysisProfileHash"], b["analysisProfileHash"])

    def test_phase22h2_runtime_soft_fields_excluded_from_hash(self) -> None:
        """ghidraVersion / timeout / heap must not flip the semantic profile hash.

        Explains Phase 2.2H (null ghidra) vs 2.2H.1 (ghidra 12.2) hash drift.
        """
        a = ap.build_analysis_profile(ghidra_version=None, timeout_sec=600, memory_limit="2g")
        b = ap.build_analysis_profile(ghidra_version="12.2", timeout_sec=900, memory_limit="4g")
        self.assertEqual(a["analysisProfileHash"], b["analysisProfileHash"])
        self.assertEqual(a["ghidraVersion"], None)
        self.assertEqual(b["ghidraVersion"], "12.2")
        self.assertIn("runtimeConfig", b)
        self.assertEqual(b["runtimeConfig"]["ghidraVersion"], "12.2")
        # Semantic hash (runtime soft fields excluded). Distinct from pre-2.2H.2
        # hashes that embedded ghidraVersion=null (8a4c…) or "12.2" (1d0a…).
        self.assertEqual(
            a["analysisProfileHash"],
            "c0f507820a1457a1af98c2a66352db531f2f4ad1bcf72bc32c58e307e3f41de7",
        )
        self.assertNotEqual(
            a["analysisProfileHash"],
            "8a4c448ec9122549a18053fd210dfbb295be984ead0eb98c7e79c626bde0f50b",
        )
        self.assertNotEqual(
            a["analysisProfileHash"],
            "1d0aea6293aca111a858b0319a9661e8d5c5a0e5e06af517bd6b408a11819047",
        )

    def test_profiles_compatible_despite_legacy_stored_hash_drift(self) -> None:
        """Legacy stored hashes that embedded ghidraVersion still soft-compatible."""
        semantic = ap.build_analysis_profile(ghidra_version="12.2")
        legacy_null = dict(semantic)
        legacy_null["ghidraVersion"] = None
        # Simulate pre-2.2H.2 stored hash that included null ghidraVersion.
        legacy_null["analysisProfileHash"] = (
            "8a4c448ec9122549a18053fd210dfbb295be984ead0eb98c7e79c626bde0f50b"
        )
        legacy_12 = dict(semantic)
        legacy_12["analysisProfileHash"] = (
            "1d0aea6293aca111a858b0319a9661e8d5c5a0e5e06af517bd6b408a11819047"
        )
        ok, status, reasons = ap.profiles_compatible(legacy_null, legacy_12)
        self.assertTrue(ok)
        self.assertIn(status, {"COMPATIBLE", "LEGACY_PARTIAL"})
        self.assertTrue(any("soft" in r or "semantic" in r or "stored" in r for r in reasons))

    def test_profiles_compatible_legacy(self) -> None:
        ok, status, reasons = ap.profiles_compatible(
            {"analyzerCompat": "2", "analysisProfileHash": "abc"},
            {"analyzerCompat": "2"},
        )
        self.assertTrue(ok)
        self.assertEqual(status, "LEGACY_PARTIAL")

    def test_profiles_incompatible_analyzer(self) -> None:
        ok, status, _ = ap.profiles_compatible(
            {"analyzerCompat": "2", "fingerprintVersion": "2", "analysisProfileHash": "a"},
            {"analyzerCompat": "1", "fingerprintVersion": "2", "analysisProfileHash": "a"},
        )
        self.assertFalse(ok)
        self.assertEqual(status, "INCOMPATIBLE")

    def test_phase22h2_semantic_hash_matrix(self) -> None:
        """Runtime soft fields vs semantic hard fields (release validation)."""
        base = ap.build_analysis_profile(ghidra_version="12.2", timeout_sec=600, memory_limit="2g")
        same_soft = ap.build_analysis_profile(ghidra_version="11.3.2", timeout_sec=1200, memory_limit="8g")
        self.assertEqual(base["analysisProfileHash"], same_soft["analysisProfileHash"])
        ok, status, reasons = ap.profiles_compatible(base, same_soft)
        self.assertTrue(ok)
        self.assertEqual(status, "COMPATIBLE")
        self.assertTrue(any("soft" in r for r in reasons))

        diff_loader = ap.build_analysis_profile(loader_base="0x00000000", ghidra_version="12.2")
        self.assertNotEqual(base["analysisProfileHash"], diff_loader["analysisProfileHash"])
        ok2, st2, _ = ap.profiles_compatible(base, diff_loader)
        self.assertFalse(ok2)
        self.assertEqual(st2, "INCOMPATIBLE")

        diff_proc = ap.build_analysis_profile(processor="ARM:LE:32:v8", ghidra_version="12.2")
        self.assertNotEqual(base["analysisProfileHash"], diff_proc["analysisProfileHash"])

        no_seed = ap.build_analysis_profile(seed_ivt=False, ghidra_version="12.2")
        self.assertNotEqual(base["analysisProfileHash"], no_seed["analysisProfileHash"])

        # Fingerprint / callgraph version bumps are semantic.
        bumped = dict(base)
        bumped["fingerprintVersion"] = "999"
        bumped["analysisProfileHash"] = ap.profile_hash(bumped)
        ok3, st3, _ = ap.profiles_compatible(base, bumped)
        self.assertFalse(ok3)
        self.assertEqual(st3, "INCOMPATIBLE")

        cg = dict(base)
        cg["callGraphSchemaVersion"] = 999
        cg["analysisProfileHash"] = ap.profile_hash(cg)
        ok4, st4, _ = ap.profiles_compatible(base, cg)
        self.assertFalse(ok4)
        self.assertEqual(st4, "INCOMPATIBLE")

        # Legacy catalog without profile hash remains partial-ok.
        ok5, st5, _ = ap.profiles_compatible(base, {"analyzerCompat": "2"})
        self.assertTrue(ok5)
        self.assertEqual(st5, "LEGACY_PARTIAL")


class ReproducibilityNormalizeTests(unittest.TestCase):
    def test_order_independent_hash(self) -> None:
        a = {
            "functions": [
                {"address": "2", "name": "b", "size": 4, "basicBlocks": 1, "fingerprint": "x"},
                {"address": "1", "name": "a", "size": 8, "basicBlocks": 2, "fingerprint": "y"},
            ],
            "processor": "ARM:LE:32:Cortex",
        }
        b = {
            "functions": list(reversed(a["functions"])),
            "processor": "ARM:LE:32:Cortex",
            "analyzedAt": "VOLATILE",
        }
        ha = gr.semantic_hash(gr.normalize_function_export(a))
        hb = gr.semantic_hash(gr.normalize_function_export(b))
        self.assertEqual(ha, hb)

    def test_compare_runs_detects_diff(self) -> None:
        run1 = {
            "functions": {"functions": [{"address": "1", "size": 4}], "functionCount": 1},
            "callgraph": {"edges": [], "edgeCount": 0, "callGraphQuality": {"unresolvedCalls": 0}},
        }
        run2 = {
            "functions": {"functions": [{"address": "1", "size": 8}], "functionCount": 1},
            "callgraph": {"edges": [], "edgeCount": 0, "callGraphQuality": {"unresolvedCalls": 0}},
        }
        out = gr.compare_runs([run1, run1])
        self.assertTrue(out["reproducible"])
        out2 = gr.compare_runs([run1, run2])
        self.assertFalse(out2["reproducible"])


class BleArchitectureConfidenceTests(unittest.TestCase):
    def _raw4tft(self, payload: bytes, header_size: int = 0x400) -> bytes:
        header = bytearray(header_size)
        header[0:8] = ble.RAW4TFT_MAGIC
        struct.pack_into("<I", header, 12, len(payload))
        struct.pack_into("<I", header, 0x18, header_size)
        return bytes(header) + payload

    def test_unknown_without_ivt(self) -> None:
        payload = bytes([i % 256 for i in range(2048)])
        out = ble.identify_ble_container(self._raw4tft(payload))
        self.assertEqual(out["architectureConfidence"], ble.ARCHITECTURE_UNKNOWN)
        self.assertFalse(out.get("ghidraImportAllowed"))

    def test_confirmed_stm32_ivt_at_payload_start(self) -> None:
        payload = bytearray(1024)
        struct.pack_into("<II", payload, 0, 0x20001000, 0x08000101)
        out = ble.identify_ble_container(self._raw4tft(bytes(payload)))
        self.assertEqual(out["architectureConfidence"], ble.ARCHITECTURE_CONFIRMED)
        self.assertTrue(out.get("ghidraImportAllowed"))
        self.assertTrue(out.get("architectureEvidence"))

    def test_ivt_at_nonzero_offset(self) -> None:
        payload = bytearray(0x500)
        struct.pack_into("<II", payload, 0x400, 0x20001000, 0x08000101)
        out = ble.identify_ble_container(self._raw4tft(bytes(payload)))
        self.assertIn(
            out["architectureConfidence"],
            {ble.ARCHITECTURE_LIKELY, ble.ARCHITECTURE_POSSIBLE, ble.ARCHITECTURE_CONFIRMED},
        )
        self.assertEqual(out["ivt"]["payloadRelativeOffset"], 0x400)


class CatalogCompatTests(unittest.TestCase):
    def test_legacy_catalog_partial(self) -> None:
        meta = {
            "status": "ok",
            "analyzerCompat": "2",
            "controllerType": "VCU",
            "processor": "ARM:LE:32:Cortex",
        }
        ok, reasons = rc.catalog_compatible_with_subject(
            meta,
            controller_type="VCU",
            processor="ARM:LE:32:Cortex",
            subject_profile=ap.build_analysis_profile(),
        )
        self.assertTrue(ok)
        self.assertTrue(any("LEGACY" in r or "legacy" in r.lower() for r in reasons))


class FsmMultiStepTests(unittest.TestCase):
    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_three_state_two_transitions(self) -> None:
        out = fr.run_fsm_program(fr.build_three_state_program())
        self.assertTrue(out["ok"])
        self.assertEqual(out["finalState"], 2)
        self.assertEqual(len(out["observedTransitions"]), 2)
        self.assertEqual(out["evidenceTier"], fr.RUNTIME_TRANSITION_OBSERVED)

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_timeout_not_counted_as_transition(self) -> None:
        loop = {
            "name": "spin_only",
            "code": bytes.fromhex("fee7"),
            "entryOffset": 0,
            "stateAddress": fr.SRAM_BASE + 0x120,
            "initialState": 0,
            "eventValue": 0,
            "expectedFinalState": 0,
            "expectedTransitions": [],
            "maxInsnsPerStep": 16,
            "thumb": True,
        }
        out = fr.run_fsm_program(loop)
        self.assertEqual(out["observedTransitions"], [])
        self.assertNotEqual(out["evidenceTier"], fr.RUNTIME_TRANSITION_OBSERVED)

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_missing_memory_not_verifiable(self) -> None:
        p = fr.build_two_state_program()
        p["name"] = "missing_memory"
        p["stateAddress"] = 0x30000000
        out = fr.run_fsm_program(p)
        self.assertEqual(out["evidenceTier"], fr.NOT_VERIFIABLE)
        self.assertFalse(out["dynamicRuntimeVerified"])

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn not installed")
    def test_suite_three_state_reproducible(self) -> None:
        s = fr.run_fsm_runtime_suite()
        self.assertTrue(s["threeStateReproducible"])
        self.assertGreaterEqual(s["runtimeTransitionsObserved"], 3)


if __name__ == "__main__":
    unittest.main()
