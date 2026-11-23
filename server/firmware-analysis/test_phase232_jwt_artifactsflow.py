"""Phase 2.3.2 — JWT ownership for semantic-dataflow / activation-forensics artifacts."""
from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt

try:
    from fastapi.testclient import TestClient
except RuntimeError as _tc_err:
    TestClient = None  # type: ignore
    _TESTCLIENT_IMPORT_ERROR = _tc_err
else:
    _TESTCLIENT_IMPORT_ERROR = None

from staging_harness import apply_env, reload_app_modules, staging_env


def _issue(secret: str, *, sub: str | None, role: str = "user", exp_delta: timedelta | None = None) -> str:
    now = datetime.now(timezone.utc)
    payload: dict = {
        "role": role,
        "status": "active",
        "iat": now,
        "exp": now + (exp_delta if exp_delta is not None else timedelta(hours=1)),
    }
    if sub is not None:
        payload["sub"] = sub
        payload["email"] = f"{sub}@example.test"
    return jwt.encode(payload, secret, algorithm="HS256")


@unittest.skipIf(TestClient is None, f"httpx/TestClient unavailable: {_TESTCLIENT_IMPORT_ERROR}")
class Phase232JwtDataflowArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="sc-phase232-jwt-"))
        cls.env = staging_env(cls.root, enable_ghidra=False)
        cls._cm = apply_env(cls.env)
        cls._cm.__enter__()
        cls.app_mod = reload_app_modules()
        cls.client = TestClient(cls.app_mod.APP)
        cls.secret = cls.env["JWT_SECRET"]
        cls.token_a = _issue(cls.secret, sub="user-a")
        cls.token_b = _issue(cls.secret, sub="user-b")
        cls.token_admin = _issue(cls.secret, sub="admin-a", role="admin")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._cm.__exit__(None, None, None)

    def _upload_and_plant(self, token: str) -> str:
        meta = {
            "clientReportId": "phase232",
            "originalFileName": "sample.bin",
            "archiveSHA256": "b" * 64,
            "allowDecrypt": False,
            "allowLLM": False,
        }
        r = self.client.post(
            "/v1/firmware/jobs",
            headers={"Authorization": f"Bearer {token}"},
            files={
                "meta_json": (None, json.dumps(meta)),
                "archive": ("sample.bin", b"\x00" * 128, "application/octet-stream"),
            },
        )
        self.assertEqual(r.status_code, 200, r.text)
        job_id = str(r.json().get("jobId") or r.json().get("job_id"))
        job = self.app_mod.load_job(job_id)
        job_dir = Path(job["dir"])
        job_dir.mkdir(parents=True, exist_ok=True)
        (job_dir / "FIRM.activation_forensics.json").write_text(
            json.dumps({"ok": True, "phase": "2.3.2", "inputHandlerFindings": []}),
            encoding="utf-8",
        )
        (job_dir / "FIRM.semantic_dataflow.json").write_text(
            json.dumps({"ok": True, "phase": "2.3.2", "functions": [], "summary": {"totalFunctions": 0}}),
            encoding="utf-8",
        )
        phase2 = dict(job.get("phase2") or {})
        phase2["activationForensicsPath"] = str(job_dir / "FIRM.activation_forensics.json")
        phase2["semanticDataflowPath"] = str(job_dir / "FIRM.semantic_dataflow.json")
        self.app_mod._update(job, phase2=phase2, state=job.get("state") or "queued")
        return job_id

    def test_owner_200_foreign_404(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        for path in ("activation-forensics", "semantic-dataflow"):
            ra = self.client.get(
                f"/v1/firmware/jobs/{job_id}/{path}",
                headers={"Authorization": f"Bearer {self.token_a}"},
            )
            self.assertEqual(ra.status_code, 200, path)
            self.assertTrue(ra.json().get("ok"))
            rb = self.client.get(
                f"/v1/firmware/jobs/{job_id}/{path}",
                headers={"Authorization": f"Bearer {self.token_b}"},
            )
            self.assertEqual(rb.status_code, 404, path)

    def test_missing_jwt_rejected(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r = self.client.get(f"/v1/firmware/jobs/{job_id}/semantic-dataflow")
        self.assertIn(r.status_code, {401, 403})

    def test_expired_jwt_401(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        tok = _issue(self.secret, sub="user-a", exp_delta=timedelta(hours=-2))
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}/semantic-dataflow",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r.status_code, 401)

    def test_invalid_jwt_401(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}/activation-forensics",
            headers={"Authorization": "Bearer not-a-real-jwt"},
        )
        self.assertEqual(r.status_code, 401)

    def test_shared_api_token_does_not_bypass_ownership(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}/semantic-dataflow",
            headers={"Authorization": f"Bearer {self.env['API_TOKEN']}"},
        )
        # Shared API token is not the owner JWT — expect 401/403/404 depending on auth path.
        self.assertIn(r.status_code, {401, 403, 404})


if __name__ == "__main__":
    unittest.main()
