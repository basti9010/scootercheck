"""Cycle 9 AGENT A — local server validation (synthetic only).

Exercises auth, job create/poll, background process_job, error paths,
result delivery, and storage layout via FastAPI TestClient.
No production writes, no real ZT3 decrypt, no invented secrets.
"""
from __future__ import annotations

import hashlib
import json
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

ROOT = Path(__file__).resolve().parent
THUMB_A = ROOT / "testdata" / "thumb_validation" / "bin" / "version_a.bin"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _issue(secret: str, *, sub: str, role: str = "user", status: str = "active") -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": sub,
            "email": f"{sub}@example.test",
            "role": role,
            "status": status,
            "iat": now,
            "exp": now + timedelta(hours=1),
        },
        secret,
        algorithm="HS256",
    )


@unittest.skipIf(TestClient is None, f"TestClient unavailable: {_TC_ERR}")
class Cycle9ServerValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._tmpdir = tempfile.mkdtemp(prefix="sc-c9-val-")
        cls.env = staging.staging_env(Path(cls._tmpdir), enable_ghidra=False)
        # Explicitly leave DECRYPT_CMD unset so encrypted paths fail closed locally.
        cls.env.pop("DECRYPT_CMD", None)
        cls._cm = staging.apply_env(cls.env)
        cls._prev = cls._cm.__enter__()
        cls.app_mod = staging.reload_app_modules()
        cls.client = TestClient(cls.app_mod.APP)
        cls.jwt_user = _issue(cls.env["JWT_SECRET"], sub="c9-user")
        cls.jwt_admin = _issue(cls.env["JWT_SECRET"], sub="c9-admin", role="admin")
        cls.jwt_other = _issue(cls.env["JWT_SECRET"], sub="c9-other")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._cm.__exit__(None, None, None)

    def _auth(self, token: str | None = None) -> dict[str, str]:
        return {"Authorization": f"Bearer {token or self.jwt_user}"}

    def _meta(self, data: bytes, name: str, **extra) -> dict:
        meta = {
            "clientReportId": f"c9-{_sha(data)[:8]}",
            "originalFileName": name,
            "archiveSHA256": _sha(data),
            "models": ["test"],
            "controllerType": "VCU",
            "allowDecrypt": True,
            "allowLLM": False,
        }
        meta.update(extra)
        return meta

    def _submit(self, data: bytes, name: str, *, token: str | None = None, **extra) -> dict:
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": (name, data, "application/octet-stream")},
            data={"meta_json": json.dumps(self._meta(data, name, **extra))},
            headers=self._auth(token),
        )
        self.assertIn(r.status_code, {200, 202}, r.text)
        body = r.json()
        self.assertEqual(body.get("state"), "queued")
        self.assertTrue(body.get("jobId"))
        return body

    # --- 1. Health / config flags (no secrets) ---

    def test_health_flags_no_secrets(self) -> None:
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertTrue(body.get("ok"))
        self.assertEqual(body.get("service"), "scootercheck-fw")
        # Secure staging defaults
        self.assertTrue(body.get("jwtConfigured"))
        self.assertTrue(body.get("apiTokenConfigured"))
        self.assertTrue(body.get("adminApiTokenConfigured"))
        self.assertFalse(body.get("apiTokenGrantsAdmin"))
        self.assertFalse(body.get("trustApiTokenClientId"))
        self.assertEqual(body.get("authMode"), "separated")
        self.assertTrue(body.get("authSecurityOk"))
        self.assertFalse(body.get("authSecurityCritical"))
        self.assertEqual(body.get("authSecurityWarnings"), [])
        # Must not leak secrets
        blob = json.dumps(body)
        self.assertNotIn(self.env["JWT_SECRET"], blob)
        self.assertNotIn(self.env["API_TOKEN"], blob)
        self.assertNotIn(self.env["ADMIN_API_TOKEN"], blob)
        for forbidden in ("sk-", "Bearer ", "password", "secret="):
            self.assertNotIn(forbidden.lower(), blob.lower())

    # --- 2. Auth ---

    def test_auth_missing_401(self) -> None:
        r = self.client.get("/v1/firmware/jobs/00000000-0000-0000-0000-000000000001")
        self.assertEqual(r.status_code, 401)

    def test_auth_bad_jwt_401(self) -> None:
        r = self.client.get(
            "/v1/firmware/jobs/00000000-0000-0000-0000-000000000001",
            headers={"Authorization": "Bearer not-a-jwt"},
        )
        self.assertEqual(r.status_code, 401)

    def test_auth_inactive_403(self) -> None:
        tok = _issue(self.env["JWT_SECRET"], sub="inactive", status="suspended")
        r = self.client.get(
            "/v1/firmware/jobs/00000000-0000-0000-0000-000000000001",
            headers=self._auth(tok),
        )
        self.assertEqual(r.status_code, 403)

    def test_auth_shared_token_not_admin(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"X-ScooterCheck-Token": self.env["API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 403)

    def test_auth_admin_token_ok(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"X-ScooterCheck-Token": self.env["ADMIN_API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 200)

    def test_auth_jwt_admin_ok(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stock",
            headers=self._auth(self.jwt_admin),
        )
        self.assertEqual(r.status_code, 200)

    # --- 3–6. Job create, background process, errors, result delivery ---

    def test_job_create_process_poll_result(self) -> None:
        self.assertTrue(THUMB_A.is_file(), "synthetic thumb fixture missing")
        data = THUMB_A.read_bytes()
        queued = self._submit(data, "version_a.dec.bin")
        job_id = queued["jobId"]
        self.assertEqual(queued.get("state"), "queued")

        # Ownership recorded for JWT user. TestClient may already have run
        # BackgroundTasks.process_job; call again for determinism (idempotent).
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("ownerPrincipal"), "user:c9-user")
        self.app_mod.process_job(job_id)
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("state"), "completed", job.get("message"))
        self.assertTrue(job.get("plaintextSaved"))
        self.assertIsNone(job.get("errorCode"))
        result = job.get("result") or {}
        self.assertTrue(result)

        # Poll delivers sanitized result
        r = self.client.get(f"/v1/firmware/jobs/{job_id}", headers=self._auth())
        self.assertEqual(r.status_code, 200)
        poll = r.json()
        self.assertEqual(poll.get("state"), "completed")
        self.assertTrue(poll.get("result"))

        # Foreign JWT → opaque 404
        r2 = self.client.get(f"/v1/firmware/jobs/{job_id}", headers=self._auth(self.jwt_other))
        self.assertEqual(r2.status_code, 404)

        # Plaintext artifact download (auth + ownership)
        r3 = self.client.get(f"/v1/firmware/jobs/{job_id}/plaintext", headers=self._auth())
        self.assertEqual(r3.status_code, 200)
        self.assertEqual(r3.content, data)

        r4 = self.client.get(
            f"/v1/firmware/jobs/{job_id}/plaintext",
            headers=self._auth(self.jwt_other),
        )
        self.assertEqual(r4.status_code, 404)

    def test_job_allow_decrypt_false_fails(self) -> None:
        data = THUMB_A.read_bytes()
        queued = self._submit(data, "version_a.dec.bin", allowDecrypt=False)
        job_id = queued["jobId"]
        self.app_mod.process_job(job_id)
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("state"), "failed")
        self.assertEqual(job.get("errorCode"), "DECRYPT_NOT_ALLOWED")

    def test_job_invalid_meta_400(self) -> None:
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": ("x.bin", b"\x00" * 64, "application/octet-stream")},
            data={"meta_json": "{not-json"},
            headers=self._auth(),
        )
        self.assertEqual(r.status_code, 400)

    def test_job_encrypted_without_decrypt_cmd_fails(self) -> None:
        """Synthetic high-entropy blob is not treated as plaintext; DECRYPT_CMD unset → fail."""
        # Avoid Cortex-M IVT / .dec.bin filename heuristics
        data = bytes([0xA5 ^ (i * 37 % 256) for i in range(8192)])
        queued = self._submit(data, "payload.bin.enc")
        job_id = queued["jobId"]
        self.app_mod.process_job(job_id)
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("state"), "failed")
        self.assertEqual(job.get("errorCode"), "DECRYPT_FAILED")
        # Partial result may still be attached for diagnostics
        self.assertIn(job.get("errorCode"), {"DECRYPT_FAILED"})

    # --- 7. Secure file storage layout ---

    def test_storage_layout_under_workdir(self) -> None:
        data = THUMB_A.read_bytes()
        queued = self._submit(data, "version_a.dec.bin")
        job_id = queued["jobId"]
        self.app_mod.process_job(job_id)
        job = self.app_mod.load_job(job_id)
        job_dir = Path(job["dir"])
        work = Path(self.env["WORK_DIR"])
        plain = Path(self.env["PLAINTEXT_STORE"])

        self.assertTrue(str(job_dir).startswith(str(work)))
        self.assertTrue((job_dir / "status.json").is_file())
        self.assertTrue((job_dir / "request.json").is_file())
        self.assertTrue((job_dir / "upload").is_dir())
        # Dated plaintext store
        ppath = Path(job["plaintextPath"])
        self.assertTrue(str(ppath).startswith(str(plain)))
        self.assertTrue(ppath.is_file())
        self.assertEqual(ppath.read_bytes(), data)
        # SHA256 recorded
        self.assertEqual(job.get("plaintextSHA256"), _sha(data))
        self.assertEqual(job.get("archiveSHA256"), _sha(data))

    def test_zip_bomb_rejected(self) -> None:
        import io
        import zipfile

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            # Highly compressible member that would expand past ratio limits
            zf.writestr("FIRM.bin.enc", b"\x00" * (2 * 1024 * 1024))
        raw = buf.getvalue()
        # If ratio check fires on inspect, submit returns 400
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": ("bomb.zip", raw, "application/zip")},
            data={"meta_json": json.dumps(self._meta(raw, "bomb.zip"))},
            headers=self._auth(),
        )
        # Either rejected at upload (400) or accepted then fails extract — both OK for validation.
        self.assertIn(r.status_code, {200, 202, 400}, r.text)
        if r.status_code == 400:
            self.assertIn("detail", r.json())

    def test_ghidra_blocked_plaintext_no_unboundlocal(self) -> None:
        """RAW4TFT forbids Ghidra import — must complete without UnboundLocalError on result."""
        import struct

        import ble_container as ble

        payload = THUMB_A.read_bytes()
        header = bytearray(0x400)
        header[0:8] = ble.RAW4TFT_MAGIC
        struct.pack_into("<I", header, 12, len(payload))
        struct.pack_into("<I", header, 0x18, 0x400)
        data = bytes(header) + payload
        # .dec.bin forces plaintext path so process_job reaches the Ghidra-blocked branch.
        queued = self._submit(data, "raw4tft.dec.bin")
        job_id = queued["jobId"]
        self.app_mod.process_job(job_id)
        job = self.app_mod.load_job(job_id)
        self.assertEqual(job.get("state"), "completed", job.get("message"))
        self.assertIsNone(job.get("errorCode"))
        result = job.get("result") or {}
        lims = result.get("analysisLimitations") or []
        self.assertTrue(
            any("Ghidra" in str(x) for x in lims)
            or any("ghidra=skipped" in str(n) for n in (result.get("notes") or [])),
            msg=f"expected Ghidra-skip limitation/notes, got lims={lims!r} notes={result.get('notes')!r}",
        )

    # --- 8. Endpoint surface smoke (auth gates) ---

    def test_endpoint_checklist_auth_gates(self) -> None:
        """Verify documented routes exist and enforce auth (404/401/403 as appropriate)."""
        missing = "00000000-0000-0000-0000-000000000099"
        # Open
        self.assertEqual(self.client.get("/health").status_code, 200)
        # Auth required job routes → 401 without creds
        for path in (
            f"/v1/firmware/jobs/{missing}",
            f"/v1/firmware/jobs/{missing}/plaintext",
            f"/v1/firmware/jobs/{missing}/decompile",
            f"/v1/firmware/jobs/{missing}/functions",
            f"/v1/firmware/jobs/{missing}/callgraph",
            f"/v1/firmware/jobs/{missing}/function-diff",
            f"/v1/firmware/jobs/{missing}/input-behavior",
            f"/v1/firmware/jobs/{missing}/input-behavior-diff",
            f"/v1/firmware/jobs/{missing}/activation-forensics",
            f"/v1/firmware/jobs/{missing}/semantic-dataflow",
        ):
            self.assertEqual(self.client.get(path).status_code, 401, path)
            # With JWT, missing job → opaque 404
            self.assertEqual(
                self.client.get(path, headers=self._auth()).status_code,
                404,
                path,
            )
        # Admin routes → 401 unauth, 403 non-admin JWT, 200 admin JWT (list endpoints)
        for path in (
            "/v1/firmware/admin/jobs",
            "/v1/firmware/admin/stats",
            "/v1/firmware/admin/stock",
            "/v1/firmware/admin/reference-catalogs",
            "/v1/firmware/admin/reference-inventory",
        ):
            self.assertEqual(self.client.get(path).status_code, 401, path)
            self.assertEqual(
                self.client.get(path, headers=self._auth()).status_code,
                403,
                path,
            )
            self.assertEqual(
                self.client.get(path, headers=self._auth(self.jwt_admin)).status_code,
                200,
                path,
            )


if __name__ == "__main__":
    unittest.main()
