"""Phase 2.3.3 — JWT ownership for analysis artifacts + pagination."""
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
class Phase233JwtArtifactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="sc-phase233-jwt-"))
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

    def _upload_and_plant(self, token: str) -> str:
        meta = {
            "clientReportId": "phase233",
            "originalFileName": "sample.bin",
            "archiveSHA256": "c" * 64,
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
            json.dumps(
                {
                    "ok": True,
                    "phase": "2.3.3",
                    "inputHandlerFindings": [
                        {
                            "address": f"0x0800{i:04x}",
                            "inputCategories": ["input_callback"],
                            "evidenceTier": "SPECULATIVE",
                        }
                        for i in range(12)
                    ],
                }
            ),
            encoding="utf-8",
        )
        (job_dir / "FIRM.semantic_dataflow.json").write_text(
            json.dumps({"ok": True, "phase": "2.3.3", "functions": [], "summary": {}}),
            encoding="utf-8",
        )
        (job_dir / "FIRM.functions.json").write_text(
            json.dumps({"ok": True, "functions": [], "functionCount": 0}), encoding="utf-8"
        )
        (job_dir / "FIRM.function_diff.json").write_text(
            json.dumps({"ok": True, "pairs": [], "summary": {}}), encoding="utf-8"
        )
        phase2 = dict(job.get("phase2") or {})
        phase2["activationForensicsPath"] = str(job_dir / "FIRM.activation_forensics.json")
        phase2["semanticDataflowPath"] = str(job_dir / "FIRM.semantic_dataflow.json")
        phase2["functionsPath"] = str(job_dir / "FIRM.functions.json")
        phase2["functionDiffPath"] = str(job_dir / "FIRM.function_diff.json")
        self.app_mod._update(job, phase2=phase2, state=job.get("state") or "queued")
        return job_id

    def test_owner_200_foreign_404_all_artifacts(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        for path in (
            "activation-forensics",
            "semantic-dataflow",
            "functions",
            "function-diff",
        ):
            ra = self.client.get(
                f"/v1/firmware/jobs/{job_id}/{path}",
                headers={"Authorization": f"Bearer {self.token_a}"},
            )
            self.assertEqual(ra.status_code, 200, path)
            rb = self.client.get(
                f"/v1/firmware/jobs/{job_id}/{path}",
                headers={"Authorization": f"Bearer {self.token_b}"},
            )
            self.assertEqual(rb.status_code, 404, path)

    def test_missing_expired_invalid_jwt(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r0 = self.client.get(f"/v1/firmware/jobs/{job_id}/semantic-dataflow")
        self.assertIn(r0.status_code, {401, 403})
        tok = _issue(self.secret, sub="user-a", exp_delta=timedelta(hours=-2))
        r1 = self.client.get(
            f"/v1/firmware/jobs/{job_id}/semantic-dataflow",
            headers={"Authorization": f"Bearer {tok}"},
        )
        self.assertEqual(r1.status_code, 401)
        r2 = self.client.get(
            f"/v1/firmware/jobs/{job_id}/activation-forensics",
            headers={"Authorization": "Bearer not-a-real-jwt"},
        )
        self.assertEqual(r2.status_code, 401)

    def test_shared_api_token_no_bypass(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}/functions",
            headers={"Authorization": f"Bearer {self.env['API_TOKEN']}"},
        )
        self.assertIn(r.status_code, {401, 403, 404})

    def test_activation_pagination(self) -> None:
        job_id = self._upload_and_plant(self.token_a)
        r = self.client.get(
            f"/v1/firmware/jobs/{job_id}/activation-forensics",
            params={"offset": 0, "limit": 5},
            headers={"Authorization": f"Bearer {self.token_a}"},
        )
        self.assertEqual(r.status_code, 200)
        body = r.json()
        findings = body.get("inputHandlerFindings") or []
        self.assertLessEqual(len(findings), 5)
        self.assertIn("responsePagination", body)


if __name__ == "__main__":
    unittest.main()
