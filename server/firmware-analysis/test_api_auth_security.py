"""HTTP-level API auth / ownership security tests (Phase 2.2B).

Uses FastAPI TestClient with controlled env + stubbed job store.
No real user accounts or production tokens.
"""
from __future__ import annotations

import os
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

import jwt

try:
    from fastapi.testclient import TestClient
except RuntimeError as _tc_err:  # missing httpx
    TestClient = None  # type: ignore[misc, assignment]
    _TESTCLIENT_IMPORT_ERROR = _tc_err
else:
    _TESTCLIENT_IMPORT_ERROR = None


def _job(**kwargs):
    base = {
        "jobId": "job",
        "state": "completed",
        "status": "completed",
        "progressPercent": 100,
        "message": "done",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "result": {},
    }
    base.update(kwargs)
    return base


def _issue(secret: str, *, sub: str, role: str = "user", exp_delta: timedelta | None = None, status: str = "active") -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": sub,
        "email": f"{sub}@example.test",
        "role": role,
        "status": status,
        "iat": now,
        "exp": now + (exp_delta if exp_delta is not None else timedelta(hours=1)),
    }
    return jwt.encode(payload, secret, algorithm="HS256")


@unittest.skipIf(TestClient is None, f"httpx/TestClient unavailable: {_TESTCLIENT_IMPORT_ERROR}")
class ApiAuthSecurityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._env = {
            "API_TOKEN": "shared-test-token",
            "ADMIN_API_TOKEN": "admin-only-token",
            "API_TOKEN_GRANTS_ADMIN": "0",
            "TRUST_API_TOKEN_CLIENT_ID": "0",
            "JWT_SECRET": "unit-test-jwt-secret",
            "JWT_ALGORITHM": "HS256",
            "ENABLE_GHIDRA": "0",
            "WORK_DIR": "/tmp/scootercheck-auth-tests-work",
            "PLAINTEXT_STORE": "/tmp/scootercheck-auth-tests-plain",
            "DECOMPILE_STORE": "/tmp/scootercheck-auth-tests-decompile",
            "STOCK_FW_DIR": "/tmp/scootercheck-auth-tests-stock",
        }
        cls._prev = {k: os.environ.get(k) for k in cls._env}
        os.environ.update(cls._env)
        for d in (
            cls._env["WORK_DIR"],
            cls._env["PLAINTEXT_STORE"],
            cls._env["DECOMPILE_STORE"],
            cls._env["STOCK_FW_DIR"],
        ):
            os.makedirs(d, exist_ok=True)

        import importlib
        import stock_diff
        import job_auth
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

    def test_health_exposes_auth_flags(self) -> None:
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertTrue(body.get("apiTokenConfigured"))
        self.assertTrue(body.get("adminApiTokenConfigured"))
        self.assertFalse(body.get("apiTokenGrantsAdmin"))
        self.assertFalse(body.get("trustApiTokenClientId"))
        self.assertEqual(body.get("authMode"), "separated")
        self.assertTrue(body.get("authSecurityOk"))
        self.assertFalse(body.get("authSecurityCritical"))
        self.assertEqual(body.get("authSecurityWarnings"), [])

    def test_open_auth_health_is_critical_not_ok(self) -> None:
        """auth=open must keep authSecurityOk false with a CRITICAL warning."""
        prev = {
            "API_TOKEN": self.app_mod.API_TOKEN,
            "ADMIN_API_TOKEN": self.app_mod.ADMIN_API_TOKEN,
            "JWT_SECRET": self.app_mod.JWT_SECRET,
        }
        try:
            self.app_mod.API_TOKEN = ""
            self.app_mod.ADMIN_API_TOKEN = ""
            self.app_mod.JWT_SECRET = ""
            r = self.client.get("/health")
            self.assertEqual(r.status_code, 200)
            body = r.json()
            self.assertEqual(body.get("authMode"), "open")
            self.assertFalse(body.get("authSecurityOk"))
            self.assertTrue(body.get("authSecurityCritical"))
            warnings = body.get("authSecurityWarnings") or []
            self.assertTrue(any(w.startswith("CRITICAL:") and "auth=open" in w for w in warnings))
        finally:
            self.app_mod.API_TOKEN = prev["API_TOKEN"]
            self.app_mod.ADMIN_API_TOKEN = prev["ADMIN_API_TOKEN"]
            self.app_mod.JWT_SECRET = prev["JWT_SECRET"]

    def test_shared_token_admin_health_is_critical_not_ok(self) -> None:
        """Prod-like grants=1 + no ADMIN_API_TOKEN → CRITICAL, authSecurityOk false."""
        prev_admin = self.app_mod.ADMIN_API_TOKEN
        with mock.patch.object(self.app_mod, "api_token_grants_admin", return_value=True):
            self.app_mod.ADMIN_API_TOKEN = ""
            try:
                r = self.client.get("/health")
                self.assertEqual(r.status_code, 200)
                body = r.json()
                self.assertEqual(body.get("authMode"), "shared_token_admin")
                self.assertFalse(body.get("adminApiTokenConfigured"))
                self.assertTrue(body.get("apiTokenGrantsAdmin"))
                self.assertFalse(body.get("authSecurityOk"))
                self.assertTrue(body.get("authSecurityCritical"))
                warnings = body.get("authSecurityWarnings") or []
                self.assertTrue(
                    any("API_TOKEN_GRANTS_ADMIN=1" in w and w.startswith("CRITICAL:") for w in warnings)
                )
                self.assertTrue(
                    any("only admin credential" in w and w.startswith("CRITICAL:") for w in warnings)
                )
            finally:
                self.app_mod.ADMIN_API_TOKEN = prev_admin

    def test_jwt_advisory_alone_does_not_fail_auth_security_ok(self) -> None:
        """ADVISORY (JWT unset) must not collapse authSecurityOk when tokens are separated."""
        prev = self.app_mod.JWT_SECRET
        try:
            self.app_mod.JWT_SECRET = ""
            r = self.client.get("/health")
            body = r.json()
            self.assertEqual(body.get("authMode"), "separated")
            self.assertTrue(body.get("authSecurityOk"))
            self.assertFalse(body.get("authSecurityCritical"))
            warnings = body.get("authSecurityWarnings") or []
            self.assertTrue(any(w.startswith("ADVISORY:") and "JWT_SECRET" in w for w in warnings))
        finally:
            self.app_mod.JWT_SECRET = prev

    def test_invalid_jwt_rejected(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": "Bearer not-a-jwt"},
        )
        self.assertEqual(r.status_code, 401)

    def test_expired_jwt_rejected(self) -> None:
        token = _issue(self._env["JWT_SECRET"], sub="u1", exp_delta=timedelta(hours=-2))
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(r.status_code, 401)

    def test_jwt_user_cannot_access_admin(self) -> None:
        token = _issue(self._env["JWT_SECRET"], sub="u1", role="user")
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_jwt_can_access_admin(self) -> None:
        token = _issue(self._env["JWT_SECRET"], sub="admin1", role="admin")
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(r.status_code, 200)

    def test_shared_token_not_admin_when_grants_disabled(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"X-ScooterCheck-Token": "shared-test-token"},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_api_token_can_access_admin(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"X-ScooterCheck-Token": "admin-only-token"},
        )
        self.assertEqual(r.status_code, 200)

    def test_foreign_job_opaque_404_for_jwt_user(self) -> None:
        job = _job(jobId="job-a", ownerPrincipal="user:owner1", createdByUserId="owner1")
        token = _issue(self._env["JWT_SECRET"], sub="attacker", role="user")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-a",
                headers={"Authorization": f"Bearer {token}"},
            )
        self.assertEqual(r.status_code, 404)
        self.assertEqual(r.json().get("detail"), "job not found")

    def test_owner_jwt_can_read_job(self) -> None:
        job = _job(jobId="job-a", ownerPrincipal="user:owner1", createdByUserId="owner1", result={"ok": True})
        token = _issue(self._env["JWT_SECRET"], sub="owner1", role="user")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-a",
                headers={"Authorization": f"Bearer {token}"},
            )
        self.assertEqual(r.status_code, 200)

    def test_manipulated_client_id_cannot_read_foreign_apitoken_job(self) -> None:
        job = _job(
            jobId="job-c",
            ownerPrincipal="apitoken-client:real-device",
            createdByClientId="real-device",
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-c",
                headers={
                    "X-ScooterCheck-Token": "shared-test-token",
                    "X-ScooterCheck-Client-Id": "attacker-device",
                },
            )
        self.assertEqual(r.status_code, 404)

    def test_known_victim_client_id_denied_without_trust(self) -> None:
        """Shared token + victim Client-Id must not open apitoken-client jobs (2.2H.1)."""
        job = _job(
            jobId="job-victim",
            ownerPrincipal="apitoken-client:victim-device",
            createdByClientId="victim-device",
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-victim",
                headers={
                    "X-ScooterCheck-Token": "shared-test-token",
                    "X-ScooterCheck-Client-Id": "victim-device",
                },
            )
        self.assertEqual(r.status_code, 404)

    def test_jwt_preferred_over_shared_token_for_identity(self) -> None:
        """When Bearer JWT and shared token are both sent, JWT identity wins."""
        job = _job(jobId="job-jwt", ownerPrincipal="user:owner1", createdByUserId="owner1")
        token = _issue(self._env["JWT_SECRET"], sub="owner1", role="user")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-jwt",
                headers={
                    "Authorization": f"Bearer {token}",
                    "X-ScooterCheck-Token": "shared-test-token",
                    "X-ScooterCheck-Client-Id": "spoofed",
                },
            )
        self.assertEqual(r.status_code, 200)

    def test_legacy_job_email_match(self) -> None:
        job = _job(jobId="legacy-1", createdBy="owner1@example.test", createdByUserId=None)
        token = _issue(self._env["JWT_SECRET"], sub="owner1", role="user")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/legacy-1",
                headers={"Authorization": f"Bearer {token}"},
            )
        self.assertEqual(r.status_code, 200)

    def test_artifact_get_respects_ownership(self) -> None:
        job = _job(
            jobId="job-art",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            functionsPath="/tmp/does-not-exist.json",
        )
        token = _issue(self._env["JWT_SECRET"], sub="attacker", role="user")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-art/functions",
                headers={"Authorization": f"Bearer {token}"},
            )
        self.assertEqual(r.status_code, 404)


if __name__ == "__main__":
    unittest.main()
