"""Upload integrity: server-computed SHA-256 must win over client meta.

Synthetic fixtures only — no real firmware packs or decrypt keys.
"""
from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

try:
    from fastapi.testclient import TestClient
except RuntimeError as _tc_err:  # missing httpx
    TestClient = None  # type: ignore[misc, assignment]
    _TESTCLIENT_IMPORT_ERROR = _tc_err
else:
    _TESTCLIENT_IMPORT_ERROR = None

import zip_safe


@unittest.skipIf(TestClient is None, f"httpx/TestClient unavailable: {_TESTCLIENT_IMPORT_ERROR}")
class UploadIntegritySha256Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="sc-qa-sha256-"))
        cls._env = {
            "API_TOKEN": "qa-shared-token",
            "ADMIN_API_TOKEN": "qa-admin-token",
            "API_TOKEN_GRANTS_ADMIN": "0",
            "TRUST_API_TOKEN_CLIENT_ID": "0",
            "JWT_SECRET": "qa-jwt-secret-not-prod",
            "JWT_ALGORITHM": "HS256",
            "ENABLE_GHIDRA": "0",
            "ENABLE_ANGR": "0",
            "ENABLE_R2": "0",
            "WORK_DIR": str(cls.root / "jobs"),
            "PLAINTEXT_STORE": str(cls.root / "plain"),
            "DECOMPILE_STORE": str(cls.root / "decomp"),
            "STOCK_FW_DIR": str(cls.root / "stock"),
        }
        cls._prev = {k: os.environ.get(k) for k in cls._env}
        os.environ.update(cls._env)
        for d in (
            cls._env["WORK_DIR"],
            cls._env["PLAINTEXT_STORE"],
            cls._env["DECOMPILE_STORE"],
            cls._env["STOCK_FW_DIR"],
        ):
            Path(d).mkdir(parents=True, exist_ok=True)

        import importlib
        import job_auth
        import stock_diff
        import app as app_mod

        importlib.reload(stock_diff)
        importlib.reload(job_auth)
        importlib.reload(app_mod)
        cls.app_mod = app_mod
        cls.client = TestClient(app_mod.APP)

    @classmethod
    def tearDownClass(cls) -> None:
        for k, v in cls._prev.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_server_sha256_ignores_client_meta_lie(self) -> None:
        payload = b"SYNTHETIC-QA-FIRMWARE-" + bytes(range(64))
        true_sha = hashlib.sha256(payload).hexdigest()
        lie_sha = "0" * 64
        meta = {
            "clientReportId": "qa-sha",
            "originalFileName": "synthetic.bin",
            "archiveSHA256": lie_sha,
            "payloadSHA256": lie_sha,
            "allowDecrypt": False,
            "allowLLM": False,
        }

        def _noop_process(job_id: str) -> None:
            return None

        with mock.patch.object(self.app_mod, "process_job", _noop_process):
            r = self.client.post(
                "/v1/firmware/jobs",
                headers={"X-ScooterCheck-Token": "qa-shared-token"},
                data={"meta_json": json.dumps(meta)},
                files={"archive": ("synthetic.bin", payload, "application/octet-stream")},
            )
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertEqual(body.get("archiveSHA256"), true_sha)
        self.assertNotEqual(body.get("archiveSHA256"), lie_sha)

        job = self.app_mod.load_job(body["jobId"])
        assert job is not None
        self.assertEqual(job.get("archiveSHA256"), true_sha)
        on_disk = Path(job["archivePath"]).read_bytes()
        self.assertEqual(hashlib.sha256(on_disk).hexdigest(), true_sha)

    def test_default_upload_limit_matches_nginx_example(self) -> None:
        # nginx-fw.conf.example: client_max_body_size 80m;
        self.assertEqual(zip_safe.MAX_UPLOAD_BYTES, 80 * 1024 * 1024)

    def test_oversized_upload_rejected_before_persist(self) -> None:
        prev = zip_safe.MAX_UPLOAD_BYTES
        try:
            # Patch both module and app import binding
            zip_safe.MAX_UPLOAD_BYTES = 64
            self.app_mod.MAX_UPLOAD_BYTES = 64
            tiny_ok = b"x" * 32
            too_big = b"y" * 128
            meta = {
                "originalFileName": "tiny.bin",
                "archiveSHA256": "",
                "allowDecrypt": False,
            }

            def _noop(job_id: str) -> None:
                return None

            with mock.patch.object(self.app_mod, "process_job", _noop):
                ok = self.client.post(
                    "/v1/firmware/jobs",
                    headers={"X-ScooterCheck-Token": "qa-shared-token"},
                    data={"meta_json": json.dumps(meta)},
                    files={"archive": ("tiny.bin", tiny_ok, "application/octet-stream")},
                )
                bad = self.client.post(
                    "/v1/firmware/jobs",
                    headers={"X-ScooterCheck-Token": "qa-shared-token"},
                    data={"meta_json": json.dumps({**meta, "originalFileName": "big.bin"})},
                    files={"archive": ("big.bin", too_big, "application/octet-stream")},
                )
            self.assertEqual(ok.status_code, 200)
            self.assertEqual(bad.status_code, 400)
            self.assertIn("groß", bad.json().get("detail", "").lower() + bad.json().get("detail", ""))
        finally:
            zip_safe.MAX_UPLOAD_BYTES = prev
            self.app_mod.MAX_UPLOAD_BYTES = prev


if __name__ == "__main__":
    unittest.main()
