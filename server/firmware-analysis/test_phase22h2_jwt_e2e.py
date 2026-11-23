"""Phase 2.2H.2: multi-user JWT ownership E2E (isolated staging, no prod).

User A uploads + owns job/artifacts; User B gets opaque 404.
Also covers expired/invalid/missing-sub/suspended JWTs and dual-header preference.
"""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

import jwt

try:
    from fastapi.testclient import TestClient
except RuntimeError as _tc_err:
    TestClient = None  # type: ignore[misc, assignment]
    _TESTCLIENT_IMPORT_ERROR = _tc_err
else:
    _TESTCLIENT_IMPORT_ERROR = None

from staging_harness import apply_env, reload_app_modules, staging_env


def _issue(
    secret: str,
    *,
    sub: str | None,
    role: str = "user",
    status: str = "active",
    exp_delta: timedelta | None = None,
    email: str | None = None,
) -> str:
    now = datetime.now(timezone.utc)
    payload: dict = {
        "role": role,
        "status": status,
        "iat": now,
        "exp": now + (exp_delta if exp_delta is not None else timedelta(hours=1)),
    }
    if sub is not None:
        payload["sub"] = sub
        payload["email"] = email or f"{sub}@example.test"
    return jwt.encode(payload, secret, algorithm="HS256")


@unittest.skipIf(TestClient is None, f"httpx/TestClient unavailable: {_TESTCLIENT_IMPORT_ERROR}")
class Phase22H2JwtE2ETests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="sc-phase22h2-jwt-"))
        cls.env = staging_env(cls.root, enable_ghidra=False)
        cls._cm = apply_env(cls.env)
        cls._cm.__enter__()
        cls.app_mod = reload_app_modules()
        cls.client = TestClient(cls.app_mod.APP)
        cls.secret = cls.env["JWT_SECRET"]
        cls.token_a = _issue(cls.secret, sub="user-a")
        cls.token_b = _issue(cls.secret, sub="user-b")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._cm.__exit__(None, None, None)

    def _upload(self, token: str, name: str = "sample.bin") -> str:
        meta = {
            "clientReportId": "phase22h2",
            "originalFileName": name,
            "archiveSHA256": "a" * 64,
            "allowDecrypt": False,
            "allowLLM": False,
        }
        files = {
            "meta_json": (None, json.dumps(meta)),
            "archive": (name, b"\x00" * 256, "application/octet-stream"),
        }
        r = self.client.post(
            "/v1/firmware/jobs",
            headers={"Authorization": f"Bearer {token}"},
            files=files,
        )
        self.assertEqual(r.status_code, 200, r.text)
        job_id = r.json().get("jobId") or r.json().get("job_id")
        self.assertTrue(job_id)
        return str(job_id)

    def test_user_a_owns_job_user_b_denied(self) -> None:
        job_id = self._upload(self.token_a, "a.bin")
        # Owner can poll
        ra = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {self.token_a}"},
        )
        self.assertEqual(ra.status_code, 200)
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("ownerPrincipal"), "user:user-a")

        rb = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {self.token_b}"},
        )
        self.assertEqual(rb.status_code, 404)
        self.assertEqual(rb.json().get("detail"), "job not found")

        for path in ("functions", "callgraph", "function-diff", "input-behavior", "plaintext"):
            r = self.client.get(
                f"/v1/firmware/jobs/{job_id}/{path}",
                headers={"Authorization": f"Bearer {self.token_b}"},
            )
            self.assertEqual(r.status_code, 404, path)

    def test_expired_jwt_401(self) -> None:
        tok = _issue(self.secret, sub="user-a", exp_delta=timedelta(hours=-1))
        r = self.client.get(
            "/v1/firmware/jobs/nope",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r.status_code, 401)

    def test_invalid_signature_401(self) -> None:
        tok = _issue("wrong-secret-not-staging", sub="user-a")
        r = self.client.get(
            "/v1/firmware/jobs/nope",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r.status_code, 401)

    def test_missing_jwt_401(self) -> None:
        r = self.client.get("/v1/firmware/jobs/nope")
        self.assertEqual(r.status_code, 401)

    def test_missing_subject_401(self) -> None:
        tok = _issue(self.secret, sub=None)
        r = self.client.get(
            "/v1/firmware/jobs/nope",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r.status_code, 401)

    def test_suspended_user_403(self) -> None:
        tok = _issue(self.secret, sub="user-a", status="suspended")
        r = self.client.get(
            "/v1/firmware/jobs/nope",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r.status_code, 403)

    def test_jwt_plus_shared_token_prefers_jwt(self) -> None:
        job_id = self._upload(self.token_a, "prefer.bin")
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={
                "Authorization": f"Bearer {self.token_a}",
                "X-ScooterCheck-Token": self.env["API_TOKEN"],
                "X-ScooterCheck-Client-Id": "spoofed-device",
            },
        )
        self.assertEqual(r.status_code, 200)

    def test_shared_token_cannot_steal_jwt_job(self) -> None:
        job_id = self._upload(self.token_a, "steal.bin")
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={
                "X-ScooterCheck-Token": self.env["API_TOKEN"],
                "X-ScooterCheck-Client-Id": "any-id",
            },
        )
        self.assertEqual(r.status_code, 404)

    def test_user_jwt_cannot_admin(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {self.token_a}"},
        )
        self.assertEqual(r.status_code, 403)

    def test_health_auth_security_flags(self) -> None:
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertFalse(body.get("apiTokenGrantsAdmin"))
        self.assertFalse(body.get("trustApiTokenClientId"))
        self.assertEqual(body.get("authMode"), "separated")
        self.assertTrue(body.get("authSecurityOk"))
        self.assertFalse(body.get("authSecurityCritical"))
        self.assertEqual(body.get("authSecurityWarnings"), [])

    def test_job_survives_expired_jwt_and_relogin(self) -> None:
        """Server job ownership is stable on sub; expired JWT does not delete the job."""
        job_id = self._upload(self.token_a, "persist.bin")
        expired = _issue(self.secret, sub="user-a", exp_delta=timedelta(hours=-1))
        r_exp = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {expired}"},
        )
        self.assertEqual(r_exp.status_code, 401)
        # Job still on disk with same owner.
        job = self.app_mod.load_job(job_id)
        self.assertIsNotNone(job)
        self.assertEqual(job.get("ownerPrincipal"), "user:user-a")
        # Fresh JWT for same sub restores access (simulates re-login / new client session).
        fresh = _issue(self.secret, sub="user-a")
        r_ok = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {fresh}"},
        )
        self.assertEqual(r_ok.status_code, 200)
        # Different sub still denied.
        r_b = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {self.token_b}"},
        )
        self.assertEqual(r_b.status_code, 404)

    def test_admin_token_can_read_user_job(self) -> None:
        job_id = self._upload(self.token_a, "admin-read.bin")
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"X-ScooterCheck-Token": self.env["ADMIN_API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 200)


if __name__ == "__main__":
    unittest.main()
