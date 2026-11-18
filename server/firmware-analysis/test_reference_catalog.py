"""Phase 2.1 reference function catalog unit tests."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import reference_catalog as rc
import function_diff as fd


class ReferenceCatalogTests(unittest.TestCase):
    def test_sha_paths_and_load_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(rc, "STOCK_FW_DIR", Path(td)), mock.patch.object(
                rc, "catalogs_root", lambda: Path(td) / "catalogs"
            ):
                sha = "a" * 64
                paths = rc.catalog_paths(sha)
                paths["functions"].write_text(
                    json.dumps(
                        {
                            "schemaVersion": 1,
                            "functions": [
                                {
                                    "address": "0x1",
                                    "name": "FUN_1",
                                    "size": 8,
                                    "basicBlocks": 1,
                                    "cfgEdges": 1,
                                    "fingerprint": "fp1",
                                }
                            ],
                            "functionCount": 1,
                        }
                    ),
                    encoding="utf-8",
                )
                meta = {
                    "schemaVersion": 1,
                    "status": "ok",
                    "firmwareSHA256": sha,
                    "analyzerCompat": rc.ANALYZER_COMPAT,
                    "referenceId": "ref1",
                    "model": "g3",
                    "controllerType": "VCU",
                    "processor": "ARM:LE:32:Cortex",
                    "functionCount": 1,
                    "referenceTrust": "communityLibrary",
                }
                paths["meta"].write_text(json.dumps(meta), encoding="utf-8")
                loaded = rc.load_catalog_functions(sha)
                self.assertIsNotNone(loaded)
                assert loaded is not None
                self.assertTrue(loaded["ok"])
                self.assertEqual(loaded["catalogMeta"]["referenceId"], "ref1")

    def test_incompatible_analyzer_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(rc, "catalogs_root", lambda: Path(td) / "catalogs"):
                sha = "b" * 64
                paths = rc.catalog_paths(sha)
                paths["functions"].write_text(
                    json.dumps({"functions": [{"name": "A", "size": 1}], "functionCount": 1}),
                    encoding="utf-8",
                )
                paths["meta"].write_text(
                    json.dumps(
                        {
                            "status": "ok",
                            "firmwareSHA256": sha,
                            "analyzerCompat": "999",
                        }
                    ),
                    encoding="utf-8",
                )
                self.assertIsNone(rc.load_catalog_functions(sha))

    def test_sha_mismatch_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(rc, "catalogs_root", lambda: Path(td) / "catalogs"):
                sha = "c" * 64
                paths = rc.catalog_paths(sha)
                paths["functions"].write_text(json.dumps({"functions": [], "functionCount": 0}), encoding="utf-8")
                paths["meta"].write_text(
                    json.dumps(
                        {
                            "status": "ok",
                            "firmwareSHA256": "d" * 64,
                            "analyzerCompat": rc.ANALYZER_COMPAT,
                        }
                    ),
                    encoding="utf-8",
                )
                self.assertIsNone(rc.load_catalog_functions(sha))

    def test_find_catalog_for_stock(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with mock.patch.object(rc, "catalogs_root", lambda: Path(td) / "catalogs"):
                sha = "e" * 64
                paths = rc.catalog_paths(sha)
                paths["functions"].write_text(
                    json.dumps(
                        {
                            "functions": [
                                {
                                    "address": "0x1",
                                    "name": "FUN_1",
                                    "size": 8,
                                    "basicBlocks": 1,
                                    "fingerprint": "x",
                                }
                            ],
                            "functionCount": 1,
                        }
                    ),
                    encoding="utf-8",
                )
                paths["meta"].write_text(
                    json.dumps(
                        {
                            "status": "ok",
                            "firmwareSHA256": sha,
                            "analyzerCompat": rc.ANALYZER_COMPAT,
                        }
                    ),
                    encoding="utf-8",
                )
                stock = {"outcome": "different", "referenceSHA256": sha, "referenceId": "r"}
                found = rc.find_catalog_for_stock(stock)
                self.assertIsNotNone(found)
                missing = rc.find_catalog_for_stock({"outcome": "noReference"})
                self.assertIsNone(missing)

    def test_failed_catalog_does_not_elevate_trust_fields(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            bin_path = Path(td) / "stock.bin"
            bin_path.write_bytes(b"\x00" * 64)
            ref = {
                "id": "r1",
                "path": str(bin_path),
                "sha256": "f" * 64,
                "label": "x",
                "model": "g3",
                "controllerType": "VCU",
                "version": "1",
                "source": "oem",
                "byteCount": 64,
                "provenanceVerified": False,
            }
            with mock.patch.object(rc, "STOCK_FW_DIR", Path(td)), mock.patch.object(
                rc, "catalogs_root", lambda: Path(td) / "catalogs"
            ), mock.patch.object(rc, "ghidra_configured", return_value=False), mock.patch.object(
                rc, "ensure_stock_dir", lambda: Path(td)
            ):
                out = rc.build_catalog_for_ref(ref)
                self.assertFalse(out["ok"])
                meta = out["meta"]
                self.assertEqual(meta["status"], "failed")
                self.assertEqual(meta["referenceTrust"], "communityLibrary")
                self.assertFalse(meta["referenceProvenanceVerified"])

    def test_function_diff_uses_catalog_blob(self) -> None:
        subject = {
            "ok": True,
            "functions": [
                {
                    "address": "0x1",
                    "name": "FUN_1",
                    "size": 8,
                    "basicBlocks": 1,
                    "cfgEdges": 1,
                    "fingerprint": "same",
                }
            ],
        }
        reference = {
            "ok": True,
            "functions": [
                {
                    "address": "0x1",
                    "name": "FUN_1",
                    "size": 8,
                    "basicBlocks": 1,
                    "cfgEdges": 1,
                    "fingerprint": "same",
                }
            ],
            "catalogMeta": {"referenceTrust": "communityLibrary", "analyzerCompat": "1"},
        }
        out = fd.compare_function_analyses(subject, reference)
        self.assertEqual(out["summary"]["identical"], 1)
        # Structural change must not imply ampellogik — limitation present.
        self.assertTrue(any("Manipulationsnachweis" in x for x in out["analysisLimitations"]))

    def test_compat_check_controller_mismatch(self) -> None:
        ok, reasons = rc.catalog_compatible_with_subject(
            {"status": "ok", "analyzerCompat": rc.ANALYZER_COMPAT, "controllerType": "VCU", "model": "g3"},
            controller_type="MCU",
            models=["g3"],
        )
        self.assertFalse(ok)
        self.assertTrue(any("controller" in r for r in reasons))


if __name__ == "__main__":
    unittest.main()
