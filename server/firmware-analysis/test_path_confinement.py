"""Cycle 9 — store-root path confinement + client path sanitization (S1/S2/E1/E2).

Synthetic fixtures only. No production secrets or real firmware packs.
"""
from __future__ import annotations

import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
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
        "plaintextSaved": False,
        "decompileSaved": False,
    }
    base.update(kwargs)
    return base


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


@unittest.skipIf(TestClient is None, f"httpx/TestClient unavailable: {_TESTCLIENT_IMPORT_ERROR}")
class PathConfinementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmpdir = tempfile.mkdtemp(prefix="sc-c9-confine-")
        cls.root = Path(cls._tmpdir)
        cls.work = cls.root / "work"
        cls.plain = cls.root / "plain"
        cls.decomp = cls.root / "decomp"
        cls.stock = cls.root / "stock"
        cls.outside = cls.root / "outside"
        for d in (cls.work, cls.plain, cls.decomp, cls.stock, cls.outside):
            d.mkdir(parents=True, exist_ok=True)

        cls._env = {
            "API_TOKEN": "shared-test-token",
            "ADMIN_API_TOKEN": "admin-only-token",
            "API_TOKEN_GRANTS_ADMIN": "0",
            "TRUST_API_TOKEN_CLIENT_ID": "0",
            "JWT_SECRET": "unit-test-jwt-secret-c9",
            "JWT_ALGORITHM": "HS256",
            "ENABLE_GHIDRA": "0",
            "WORK_DIR": str(cls.work),
            "PLAINTEXT_STORE": str(cls.plain),
            "DECOMPILE_STORE": str(cls.decomp),
            "STOCK_FW_DIR": str(cls.stock),
        }
        cls._prev = {k: os.environ.get(k) for k in cls._env}
        os.environ.update(cls._env)

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
        import shutil

        shutil.rmtree(cls._tmpdir, ignore_errors=True)

    def _owner_headers(self) -> dict[str, str]:
        token = _issue(self._env["JWT_SECRET"], sub="owner1")
        return {"Authorization": f"Bearer {token}"}

    def test_poisoned_plaintext_path_outside_store_returns_404(self) -> None:
        """S2: status.json pointing at /etc/passwd must not be served."""
        secret = self.outside / "secret.bin"
        secret.write_bytes(b"SHOULD-NOT-LEAK")
        job_dir = self.work / "2026" / "01" / "01" / "job-poison-plain"
        job_dir.mkdir(parents=True, exist_ok=True)
        job = _job(
            jobId="job-poison-plain",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            plaintextPath=str(secret),
            plaintextSaved=True,
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-poison-plain/plaintext",
                headers=self._owner_headers(),
            )
        self.assertEqual(r.status_code, 404)
        self.assertEqual(r.json().get("detail"), "plaintext not available")

    def test_confined_plaintext_under_store_is_served(self) -> None:
        job_dir = self.work / "2026" / "01" / "01" / "job-ok-plain"
        job_dir.mkdir(parents=True, exist_ok=True)
        day = self.plain / "2026" / "01" / "01"
        day.mkdir(parents=True, exist_ok=True)
        stored = day / "job-ok-plain_abcd_FIRM.dec.bin"
        stored.write_bytes(b"\x00FIRMWARE_OK\x00")
        job = _job(
            jobId="job-ok-plain",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            plaintextPath=str(stored),
            plaintextSaved=True,
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-ok-plain/plaintext",
                headers=self._owner_headers(),
            )
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.content, b"\x00FIRMWARE_OK\x00")

    def test_poisoned_decompile_path_outside_store_returns_404(self) -> None:
        secret = self.outside / "leak.c"
        secret.write_text("int secret(void){return 1;}\n", encoding="utf-8")
        job_dir = self.work / "2026" / "01" / "01" / "job-poison-c"
        job_dir.mkdir(parents=True, exist_ok=True)
        job = _job(
            jobId="job-poison-c",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            decompilePath=str(secret),
            decompileSaved=True,
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-poison-c/decompile",
                headers=self._owner_headers(),
            )
        self.assertEqual(r.status_code, 404)

    def test_decompile_preview_exposes_basename_only(self) -> None:
        job_dir = self.work / "2026" / "01" / "01" / "job-prev"
        job_dir.mkdir(parents=True, exist_ok=True)
        day = self.decomp / "2026" / "01" / "01"
        day.mkdir(parents=True, exist_ok=True)
        stored = day / "FIRM.dec.c"
        stored.write_text("/* decompiled */\nint main(void){return 0;}\n", encoding="utf-8")
        job = _job(
            jobId="job-prev",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            decompilePath=str(stored),
            decompileSaved=True,
        )
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-prev/decompile?preview_chars=2000",
                headers=self._owner_headers(),
            )
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body.get("path"), "FIRM.dec.c")
        self.assertNotIn(str(self.decomp), body.get("path") or "")
        self.assertNotIn("/", body.get("path") or "")

    def test_job_status_strips_absolute_paths(self) -> None:
        job_dir = self.work / "2026" / "01" / "01" / "job-status"
        job_dir.mkdir(parents=True, exist_ok=True)
        abs_plain = str(self.plain / "2026" / "01" / "01" / "deep_secret.dec.bin")
        abs_c = str(self.decomp / "2026" / "01" / "01" / "deep_secret.dec.c")
        job = _job(
            jobId="job-status",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            plaintextPath=abs_plain,
            plaintextSaved=True,
            decompilePath=abs_c,
            decompileSaved=True,
            archiveSHA256="abc",
            plaintextSHA256="def",
        )
        payload = self.app_mod.job_status_payload(job)
        self.assertEqual(payload["plaintextPath"], "deep_secret.dec.bin")
        self.assertEqual(payload["decompilePath"], "deep_secret.dec.c")
        self.assertNotIn(str(self.plain), payload["plaintextPath"] or "")
        self.assertNotIn(str(self.decomp), payload["decompilePath"] or "")

        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-status",
                headers=self._owner_headers(),
            )
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body.get("plaintextPath"), "deep_secret.dec.bin")
        self.assertFalse(str(body.get("plaintextPath") or "").startswith("/"))

    def test_foreign_owner_cannot_download_confined_plaintext(self) -> None:
        """Unauthorized artifact access stays opaque 404 even when file is valid."""
        job_dir = self.work / "2026" / "01" / "01" / "job-acl"
        job_dir.mkdir(parents=True, exist_ok=True)
        stored = self.plain / "acl.dec.bin"
        stored.write_bytes(b"OWNER_ONLY")
        job = _job(
            jobId="job-acl",
            ownerPrincipal="user:owner1",
            createdByUserId="owner1",
            dir=str(job_dir),
            plaintextPath=str(stored),
            plaintextSaved=True,
        )
        attacker = _issue(self._env["JWT_SECRET"], sub="attacker")
        with mock.patch.object(self.app_mod, "load_job", return_value=job):
            r = self.client.get(
                "/v1/firmware/jobs/job-acl/plaintext",
                headers={"Authorization": f"Bearer {attacker}"},
            )
        self.assertEqual(r.status_code, 404)
        self.assertEqual(r.json().get("detail"), "job not found")

    def test_invalid_jwt_detail_is_generic(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": "Bearer not.a.jwt"},
        )
        self.assertEqual(r.status_code, 401)
        detail = r.json().get("detail")
        self.assertEqual(detail, "invalid token")
        self.assertNotIn("algorithm", str(detail).lower())
        self.assertNotIn("Signature", str(detail))

    def test_delete_job_artifacts_skips_paths_outside_roots(self) -> None:
        victim = self.outside / "do-not-delete.bin"
        victim.write_bytes(b"keep-me")
        job_dir = self.work / "2026" / "01" / "01" / "job-del"
        job_dir.mkdir(parents=True, exist_ok=True)
        (job_dir / "marker.txt").write_text("x", encoding="utf-8")
        job = _job(
            jobId="job-del",
            dir=str(job_dir),
            plaintextPath=str(victim),
            decompilePath=None,
            archivePath=None,
        )
        self.app_mod.delete_job_artifacts(job)
        self.assertTrue(victim.is_file(), "outside-store path must not be unlinked")
        self.assertFalse(job_dir.exists(), "job dir under WORK_DIR should be removed")

    def test_confined_helper_rejects_symlink_escape(self) -> None:
        """Symlink inside PLAINTEXT_STORE that points outside must not resolve."""
        target = self.outside / "via-symlink.bin"
        target.write_bytes(b"escaped")
        link = self.plain / "escape.link.bin"
        if link.exists() or link.is_symlink():
            link.unlink()
        try:
            link.symlink_to(target)
        except OSError:
            self.skipTest("symlink creation not permitted in this environment")
        job_dir = self.work / "2026" / "01" / "01" / "job-sym"
        job_dir.mkdir(parents=True, exist_ok=True)
        job = {
            "dir": str(job_dir),
            "plaintextPath": str(link),
        }
        resolved = self.app_mod._confined_stored_file(
            job,
            stored_key="plaintextPath",
            fallback_name="FIRM.dec.bin",
            allowed_roots=[self.app_mod.PLAINTEXT_STORE, self.app_mod.WORK_DIR],
        )
        self.assertIsNone(resolved)

    def test_open_auth_warning_when_secrets_missing(self) -> None:
        prev = {
            "API_TOKEN": self.app_mod.API_TOKEN,
            "ADMIN_API_TOKEN": self.app_mod.ADMIN_API_TOKEN,
            "JWT_SECRET": self.app_mod.JWT_SECRET,
        }
        try:
            self.app_mod.API_TOKEN = ""
            self.app_mod.ADMIN_API_TOKEN = ""
            self.app_mod.JWT_SECRET = ""
            warnings = self.app_mod._auth_security_warnings()
            self.assertTrue(any("auth=open" in w for w in warnings))
        finally:
            self.app_mod.API_TOKEN = prev["API_TOKEN"]
            self.app_mod.ADMIN_API_TOKEN = prev["ADMIN_API_TOKEN"]
            self.app_mod.JWT_SECRET = prev["JWT_SECRET"]


class ClientSafeNameUnitTests(unittest.TestCase):
    def test_basename_only(self) -> None:
        # Import helpers without full app reload when possible.
        from app import _client_safe_artifact_name

        self.assertEqual(
            _client_safe_artifact_name("/var/lib/scootercheck/decrypted/a/b/file.dec.bin"),
            "file.dec.bin",
        )
        self.assertIsNone(_client_safe_artifact_name(None))
        self.assertIsNone(_client_safe_artifact_name(""))


if __name__ == "__main__":
    unittest.main()
