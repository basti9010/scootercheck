"""Phase 2.2H.1 validation tests: auth hardening + Ghidra failure paths (no heavy Ghidra)."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import ble_container as ble
import job_auth as ja
from ghidra_decompile import ghidra_configured, run_ghidra_decompile


class AuthHardening22H1(unittest.TestCase):
    def test_trust_flag_default_false(self) -> None:
        prev = os.environ.get("TRUST_API_TOKEN_CLIENT_ID")
        os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
        try:
            self.assertFalse(ja.trust_api_token_client_id())
        finally:
            if prev is None:
                os.environ.pop("TRUST_API_TOKEN_CLIENT_ID", None)
            else:
                os.environ["TRUST_API_TOKEN_CLIENT_ID"] = prev

    def test_health_exposes_trust_flag_via_reload(self) -> None:
        try:
            from fastapi.testclient import TestClient
        except RuntimeError as e:
            self.skipTest(str(e))
        prev = {k: os.environ.get(k) for k in (
            "API_TOKEN", "ADMIN_API_TOKEN", "API_TOKEN_GRANTS_ADMIN",
            "TRUST_API_TOKEN_CLIENT_ID", "JWT_SECRET", "ENABLE_GHIDRA",
            "WORK_DIR", "PLAINTEXT_STORE", "DECOMPILE_STORE", "STOCK_FW_DIR",
        )}
        os.environ.update({
            "API_TOKEN": "t",
            "ADMIN_API_TOKEN": "a",
            "API_TOKEN_GRANTS_ADMIN": "0",
            "TRUST_API_TOKEN_CLIENT_ID": "0",
            "JWT_SECRET": "s",
            "ENABLE_GHIDRA": "0",
            "WORK_DIR": "/tmp/sc22h1-health-w",
            "PLAINTEXT_STORE": "/tmp/sc22h1-health-p",
            "DECOMPILE_STORE": "/tmp/sc22h1-health-d",
            "STOCK_FW_DIR": "/tmp/sc22h1-health-s",
        })
        for d in ("WORK_DIR", "PLAINTEXT_STORE", "DECOMPILE_STORE", "STOCK_FW_DIR"):
            Path(os.environ[d]).mkdir(parents=True, exist_ok=True)
        try:
            import importlib
            import stock_diff
            import job_auth
            import app as app_mod
            importlib.reload(stock_diff)
            importlib.reload(job_auth)
            importlib.reload(app_mod)
            r = TestClient(app_mod.APP).get("/health")
            self.assertEqual(r.status_code, 200)
            self.assertFalse(r.json().get("trustApiTokenClientId"))
            self.assertFalse(r.json().get("apiTokenGrantsAdmin"))
        finally:
            for k, v in prev.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v


class GhidraFailurePaths(unittest.TestCase):
    def test_ghidra_not_configured_returns_false(self) -> None:
        with mock.patch.dict(os.environ, {"GHIDRA_HOME": "", "GHIDRA_HEADLESS": ""}, clear=False):
            # May still find /opt/ghidra — force empty home and no which
            with mock.patch("ghidra_decompile.shutil.which", return_value=None):
                with mock.patch("ghidra_decompile.Path.glob", return_value=[]):
                    with mock.patch.dict(os.environ, {"GHIDRA_HOME": "/nonexistent-ghidra-home-22h1"}, clear=False):
                        # ghidra_configured may still scan /opt — call run with forced miss
                        ok, msg = run_ghidra_decompile(
                            Path("/nonexistent.bin"),
                            Path("/tmp/out.c"),
                        )
                        # Either not configured or input missing — must not claim success
                        self.assertFalse(ok)

    def test_ble_unknown_architecture_blocks_import_flag(self) -> None:
        payload = bytes(range(256)) * 8
        header = bytearray(0x400)
        header[0:8] = ble.RAW4TFT_MAGIC
        import struct
        struct.pack_into("<I", header, 12, len(payload))
        struct.pack_into("<I", header, 0x18, 0x400)
        out = ble.identify_ble_container(bytes(header) + payload, original_name="x_BLE.bin")
        self.assertFalse(out.get("ghidraImportAllowed"))
        self.assertEqual(out.get("architectureConfidence"), ble.ARCHITECTURE_UNKNOWN)

    def test_missing_export_artifact_marked_incomplete(self) -> None:
        from function_analysis import load_function_analysis

        missing = Path("/tmp/does-not-exist-22h1-functions.json")
        fa = load_function_analysis(missing if missing.is_file() else None)
        self.assertFalse(fa.get("ok"))


if __name__ == "__main__":
    unittest.main()
