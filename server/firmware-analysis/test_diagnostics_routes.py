"""Cycle 11 — diagnostics routes auth gate + wiring smoke."""
from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt

try:
    from fastapi.testclient import TestClient
except RuntimeError as _e:  # pragma: no cover
    TestClient = None  # type: ignore
    _TC_ERR = _e
else:
    _TC_ERR = None

import staging_harness as staging


def _issue(secret: str, *, sub: str, role: str = "user") -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": sub,
            "email": f"{sub}@example.test",
            "role": role,
            "status": "active",
            "iat": now,
            "exp": now + timedelta(hours=1),
        },
        secret,
        algorithm="HS256",
    )


@unittest.skipIf(TestClient is None, f"TestClient unavailable: {_TC_ERR}")
class DiagnosticsRoutesAuthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmpdir = tempfile.mkdtemp(prefix="sc-c11-diag-")
        cls.env = staging.staging_env(Path(cls._tmpdir), enable_ghidra=False)
        cls.env.pop("DECRYPT_CMD", None)
        # Fail-closed: grants admin must stay off for diagnostics.
        cls.env["API_TOKEN_GRANTS_ADMIN"] = "0"
        cls._cm = staging.apply_env(cls.env)
        cls._prev = cls._cm.__enter__()
        cls.app_mod = staging.reload_app_modules()
        cls.client = TestClient(cls.app_mod.APP)
        cls.jwt_user = _issue(cls.env["JWT_SECRET"], sub="c11-user")
        cls.jwt_admin = _issue(cls.env["JWT_SECRET"], sub="c11-admin", role="admin")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._cm.__exit__(None, None, None)

    def test_status_requires_auth(self) -> None:
        r = self.client.get("/v1/diagnostics/status")
        self.assertEqual(r.status_code, 401)

    def test_status_denies_user_jwt(self) -> None:
        r = self.client.get(
            "/v1/diagnostics/status",
            headers={"Authorization": f"Bearer {self.jwt_user}"},
        )
        self.assertEqual(r.status_code, 403)

    def test_status_allows_admin_jwt(self) -> None:
        r = self.client.get(
            "/v1/diagnostics/status",
            headers={"Authorization": f"Bearer {self.jwt_admin}"},
        )
        self.assertEqual(r.status_code, 200, r.text)
        body = r.json()
        self.assertIn("components", body)
        # Never expose raw secrets
        blob = str(body)
        self.assertNotIn(self.env["JWT_SECRET"], blob)
        self.assertNotIn(self.env.get("API_TOKEN", "___"), blob)

    def test_shared_api_token_denied_even_when_present(self) -> None:
        r = self.client.get(
            "/v1/diagnostics/status",
            headers={"X-ScooterCheck-Token": self.env["API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_api_token_allowed(self) -> None:
        r = self.client.get(
            "/v1/diagnostics/status",
            headers={"X-ScooterCheck-Token": self.env["ADMIN_API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 200, r.text)

    def test_selftest_starts_for_admin(self) -> None:
        r = self.client.post(
            "/v1/diagnostics/selftest",
            json={"includeTea": True, "includeGhidra": True, "includeWorkers": True},
            headers={"Authorization": f"Bearer {self.jwt_admin}"},
        )
        self.assertIn(r.status_code, {200, 202}, r.text)
        job_id = r.json().get("jobId")
        self.assertTrue(job_id)
        # Poll (in-process selftest may already complete)
        r2 = self.client.get(
            f"/v1/diagnostics/selftest/{job_id}",
            headers={"Authorization": f"Bearer {self.jwt_admin}"},
        )
        self.assertEqual(r2.status_code, 200, r2.text)
        st = r2.json().get("state")
        self.assertIn(st, {"queued", "running", "completed", "failed"})


if __name__ == "__main__":
    unittest.main()
