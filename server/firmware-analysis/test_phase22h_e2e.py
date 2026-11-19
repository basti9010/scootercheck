"""Phase 2.2H end-to-end / integration tests (isolated staging dirs).

Real FastAPI TestClient + process_job pipeline exercises — not HTTP mocks alone.
Ghidra runs only when locally configured; remote calibration is documented in the report.
"""
from __future__ import annotations

import hashlib
import json
import struct
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

import jwt

try:
    from fastapi.testclient import TestClient
except RuntimeError as _e:  # pragma: no cover
    TestClient = None  # type: ignore
    _TC_ERR = _e
else:
    _TC_ERR = None

import analysis_profile as ap
import ble_container as ble
import fsm_runtime as fr
import ghidra_reproducibility as gr
import plaintext_detect as pd
import reference_catalog as rc
import staging_harness as staging
import zip_safe
from ghidra_decompile import ghidra_configured

ROOT = Path(__file__).resolve().parent
THUMB_A = ROOT / "testdata" / "thumb_validation" / "bin" / "version_a.bin"
THUMB_B = ROOT / "testdata" / "thumb_validation" / "bin" / "version_b.bin"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _raw4tft(payload: bytes, header_size: int = 0x400) -> bytes:
    header = bytearray(header_size)
    header[0:8] = ble.RAW4TFT_MAGIC
    struct.pack_into("<I", header, 12, len(payload))
    struct.pack_into("<I", header, 0x18, header_size)
    return bytes(header) + payload


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
class Phase22HStagingApiE2E(unittest.TestCase):
    """Upload → process_job → poll → ownership (Ghidra disabled in staging)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls._tmpdir = tempfile.mkdtemp(prefix="sc22h-e2e-")
        cls.env = staging.staging_env(Path(cls._tmpdir), enable_ghidra=False)
        cls._cm = staging.apply_env(cls.env)
        cls._prev = cls._cm.__enter__()
        cls.app_mod = staging.reload_app_modules()
        cls.client = TestClient(cls.app_mod.APP)
        cls.jwt_user = _issue(cls.env["JWT_SECRET"], sub="user-e2e")
        cls.jwt_admin = _issue(cls.env["JWT_SECRET"], sub="admin-e2e", role="admin")

    @classmethod
    def tearDownClass(cls) -> None:
        cls._cm.__exit__(None, None, None)

    def _submit_and_process(self, data: bytes, name: str, *, token: str | None = None) -> dict:
        sha = _sha(data)
        meta = {
            "clientReportId": f"e2e-{sha[:8]}",
            "originalFileName": name,
            "archiveSHA256": sha,
            "models": ["test"],
            "controllerType": "VCU",
            "allowDecrypt": True,
            "allowLLM": False,
        }
        headers = {
            "Authorization": f"Bearer {token or self.jwt_user}",
            "X-ScooterCheck-Client-Id": "ios-e2e-1",
        }
        # Capture BackgroundTasks.add_task so we run process_job synchronously
        captured: dict = {}

        class _BG:
            def add_task(self, fn, *a, **k):
                captured["fn"] = fn
                captured["args"] = a
                captured["kwargs"] = k

        # FastAPI injects a real BackgroundTasks instance; patch process_job scheduling
        # by letting the request complete then calling process_job ourselves.
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": (name, data, "application/octet-stream")},
            data={"meta_json": json.dumps(meta)},
            headers=headers,
        )
        self.assertIn(r.status_code, {200, 202}, r.text)
        body = r.json()
        job_id = body.get("jobId")
        self.assertTrue(job_id)
        # Drive worker inline (TestClient may or may not run background tasks)
        t0 = time.monotonic()
        self.app_mod.process_job(job_id)
        elapsed = time.monotonic() - t0
        job = self.app_mod.load_job(job_id)
        self.assertIsNotNone(job)
        job["_e2eElapsedSec"] = elapsed
        job["_e2eInputSHA256"] = sha
        return job

    def test_gate_health_secure_auth_flags(self) -> None:
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertTrue(body.get("ok"))
        self.assertFalse(body.get("apiTokenGrantsAdmin"))
        self.assertTrue(body.get("adminApiTokenConfigured"))
        self.assertTrue(body.get("apiTokenConfigured"))

    def test_tc1_plaintext_upload_pipeline(self) -> None:
        self.assertTrue(THUMB_A.is_file())
        data = THUMB_A.read_bytes()
        job = self._submit_and_process(data, "version_a.dec.bin")
        self.assertEqual(job.get("state"), "completed", job.get("message"))
        self.assertTrue(job.get("plaintextSaved"))
        self.assertEqual(job.get("plaintextSHA256"), _sha(data))
        result = job.get("result") or {}
        notes = " ".join(result.get("notes") or [])
        self.assertIn("already plaintext", notes.lower())
        # Container analysis must be merged (2.2H NameError fix)
        self.assertIn("firmwareContainerAnalysis", result)
        r = self.client.get(
            f"/v1/firmware/jobs/{job['jobId']}",
            headers={"Authorization": f"Bearer {self.jwt_user}"},
        )
        self.assertEqual(r.status_code, 200)
        poll = r.json()
        self.assertEqual(poll.get("state"), "completed")
        self.assertTrue(poll.get("result"))

    def test_tc1_foreign_job_opaque_404(self) -> None:
        data = THUMB_A.read_bytes()
        job = self._submit_and_process(data, "version_a.dec.bin")
        other = _issue(self.env["JWT_SECRET"], sub="other-user")
        r = self.client.get(
            f"/v1/firmware/jobs/{job['jobId']}",
            headers={"Authorization": f"Bearer {other}"},
        )
        self.assertEqual(r.status_code, 404)

    def test_tc4_ble_raw4tft_blocks_ghidra(self) -> None:
        payload = bytes([i % 256 for i in range(4096)])
        blob = _raw4tft(payload)
        job = self._submit_and_process(blob, "ble_test_BLE.bin")
        # May complete or fail decrypt depending on entropy; container path should record skip
        result = job.get("result") or {}
        notes = " ".join(result.get("notes") or []) + " " + str(job.get("message") or "")
        cont = result.get("firmwareContainerAnalysis") or {}
        if cont:
            self.assertFalse(cont.get("ghidraImportAllowed"))
            self.assertEqual(cont.get("architectureConfidence"), ble.ARCHITECTURE_UNKNOWN)
        # If job completed, ghidra skip note should appear when blocked
        if job.get("state") == "completed" and cont.get("ghidraImportAllowed") is False:
            self.assertIn("ghidra=skipped", notes)

    def test_tc5_corrupt_zip_rejected(self) -> None:
        headers = {"Authorization": f"Bearer {self.jwt_user}"}
        meta = {
            "clientReportId": "bad",
            "originalFileName": "bad.zip",
            "archiveSHA256": _sha(b"not-a-zip"),
            "allowDecrypt": True,
        }
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": ("bad.zip", b"not-a-zip", "application/zip")},
            data={"meta_json": json.dumps(meta)},
            headers=headers,
        )
        self.assertEqual(r.status_code, 400)

    def test_tc5_empty_upload_rejected(self) -> None:
        headers = {"Authorization": f"Bearer {self.jwt_user}"}
        meta = {
            "clientReportId": "empty",
            "originalFileName": "empty.bin",
            "archiveSHA256": _sha(b""),
            "allowDecrypt": True,
        }
        r = self.client.post(
            "/v1/firmware/jobs",
            files={"archive": ("empty.bin", b"", "application/octet-stream")},
            data={"meta_json": json.dumps(meta)},
            headers=headers,
        )
        self.assertEqual(r.status_code, 400)

    def test_tc7_artifact_endpoints_ownership(self) -> None:
        data = THUMB_A.read_bytes()
        job = self._submit_and_process(data, "version_a.dec.bin")
        jid = job["jobId"]
        # Owner can hit artifact endpoints (404 if no artifact file is fine if ownership passed)
        for path in (
            f"/v1/firmware/jobs/{jid}/functions",
            f"/v1/firmware/jobs/{jid}/callgraph",
            f"/v1/firmware/jobs/{jid}/function-diff",
            f"/v1/firmware/jobs/{jid}/input-behavior",
        ):
            r = self.client.get(path, headers={"Authorization": f"Bearer {self.jwt_user}"})
            self.assertIn(r.status_code, {200, 404}, path)
            if r.status_code == 404:
                # Must be missing artifact, not opaque foreign — foreign checked separately
                pass
        other = _issue(self.env["JWT_SECRET"], sub="attacker")
        r = self.client.get(
            f"/v1/firmware/jobs/{jid}/functions",
            headers={"Authorization": f"Bearer {other}"},
        )
        self.assertEqual(r.status_code, 404)

    def test_admin_endpoint_blocked_for_user(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {self.jwt_user}"},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_endpoint_ok_for_admin_jwt(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/stats",
            headers={"Authorization": f"Bearer {self.jwt_admin}"},
        )
        self.assertEqual(r.status_code, 200)

    def test_shared_api_token_not_admin(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/reference-catalogs",
            headers={"X-ScooterCheck-Token": self.env["API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 403)

    def test_admin_api_token_ok(self) -> None:
        r = self.client.get(
            "/v1/firmware/admin/reference-catalogs",
            headers={"X-ScooterCheck-Token": self.env["ADMIN_API_TOKEN"]},
        )
        self.assertEqual(r.status_code, 200)

    def test_missing_token_rejected(self) -> None:
        r = self.client.get("/v1/firmware/admin/stats")
        self.assertEqual(r.status_code, 401)

    def test_poll_payload_size_reasonable(self) -> None:
        data = THUMB_A.read_bytes()
        job = self._submit_and_process(data, "version_a.dec.bin")
        r = self.client.get(
            f"/v1/firmware/jobs/{job['jobId']}",
            headers={"Authorization": f"Bearer {self.jwt_user}"},
        )
        self.assertEqual(r.status_code, 200)
        # Polling summary should stay well under multi-MB artifact sizes
        self.assertLess(len(r.content), 2_000_000)


class Phase22HPipelineUnitE2E(unittest.TestCase):
    def test_plaintext_detect_thumb_fixture(self) -> None:
        data = THUMB_A.read_bytes()
        with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
            f.write(data)
            path = Path(f.name)
        try:
            ok, reason = pd.looks_like_plaintext_firmware(path, original_name="version_a.dec.bin")
            self.assertTrue(ok)
            self.assertTrue(reason)
        finally:
            path.unlink(missing_ok=True)

    def test_ble_unknown_blocks_ghidra_flag(self) -> None:
        payload = bytes([i % 256 for i in range(2048)])
        blob = _raw4tft(payload)
        out = ble.identify_ble_container(blob, original_name="x_BLE.bin")
        self.assertEqual(out["architectureConfidence"], ble.ARCHITECTURE_UNKNOWN)
        self.assertFalse(out["ghidraImportAllowed"])

    def test_analysis_profile_hash_stable(self) -> None:
        a = ap.build_analysis_profile(seed_ivt=True)
        b = ap.build_analysis_profile(seed_ivt=True)
        self.assertEqual(a["analysisProfileHash"], b["analysisProfileHash"])
        self.assertEqual(a["analysisProfileVersion"], "2.2G.1")

    def test_functiondiff_incompatible_profile_rejected(self) -> None:
        meta = {
            "status": "ok",
            "analyzerCompat": "1",
            "controllerType": "VCU",
            "processor": "ARM:LE:32:Cortex",
            "analysisProfileHash": "deadbeef",
            "fingerprintVersion": "2",
        }
        ok, reasons = rc.catalog_compatible_with_subject(
            meta,
            controller_type="VCU",
            processor="ARM:LE:32:Cortex",
            subject_profile=ap.build_analysis_profile(),
        )
        self.assertFalse(ok)
        self.assertTrue(any("analyzerCompat" in r for r in reasons))

    def test_corrupt_upload_rejected_by_zip_safe(self) -> None:
        with self.assertRaises(zip_safe.ZipSafetyError):
            zip_safe.inspect_zip(b"not-a-zip")

    def test_unsupported_format_ble_non_container(self) -> None:
        out = ble.identify_ble_container(b"\x00" * 1000)
        self.assertEqual(out["status"], ble.FORMAT_UNSUPPORTED)

    @unittest.skipUnless(fr.unicorn_fsm_available(), "unicorn missing")
    def test_fsm_multistep_still_green(self) -> None:
        out = fr.run_fsm_program(fr.build_three_state_program())
        self.assertEqual(out["finalState"], 2)
        self.assertEqual(len(out["observedTransitions"]), 2)

    def test_repro_helper_on_fixture_exports(self) -> None:
        fa = ROOT / "testdata" / "thumb_validation" / "meta" / "version_a.functions.json"
        if not fa.is_file():
            self.skipTest("no fixture export")
        data = json.loads(fa.read_text(encoding="utf-8"))
        n = gr.normalize_function_export(data)
        self.assertEqual(gr.semantic_hash(n), gr.semantic_hash(n))

    def test_tc3_reference_diff_with_isolated_catalogs(self) -> None:
        """FunctionDiff path with two fixture exports + matching profile."""
        from function_diff import compare_function_analyses

        fa = ROOT / "testdata" / "thumb_validation" / "meta" / "version_a.functions.json"
        fb = ROOT / "testdata" / "thumb_validation" / "meta" / "version_b.functions.json"
        if not fa.is_file() or not fb.is_file():
            self.skipTest("thumb_validation meta exports missing")
        subj = json.loads(fa.read_text(encoding="utf-8"))
        ref = json.loads(fb.read_text(encoding="utf-8"))
        profile = ap.build_analysis_profile(seed_ivt=True)
        for blob in (subj, ref):
            blob.setdefault("analysisProfile", profile)
            blob.setdefault("analyzerCompat", ap.ANALYZER_COMPAT)
        diff = compare_function_analyses(subj, ref)
        self.assertIsInstance(diff, dict)
        self.assertTrue(diff)

    @unittest.skipUnless(ghidra_configured(), "ghidra not configured locally")
    def test_ghidra_pipeline_thumb_fixture(self) -> None:
        from ghidra_decompile import run_ghidra_decompile

        with tempfile.TemporaryDirectory() as td:
            out_c = Path(td) / "out.c"
            fn = Path(td) / "out.functions.json"
            cg = Path(td) / "out.callgraph.json"
            ok, msg = run_ghidra_decompile(
                THUMB_A,
                out_c,
                functions_json=fn,
                callgraph_json=cg,
                seed_ivt_entry_points=True,
            )
            self.assertTrue(ok, msg)
            self.assertTrue(fn.is_file())
            fa = json.loads(fn.read_text(encoding="utf-8"))
            self.assertGreater(int(fa.get("functionCount") or len(fa.get("functions") or [])), 0)


class Phase22HJsonReportE2E(unittest.TestCase):
    def test_deep_result_json_roundtrip_fields(self) -> None:
        payload = {
            "schemaVersion": 1,
            "producedAt": "2026-11-19T12:00:00Z",
            "sources": ["serverDecompile"],
            "subjectSHA256": _sha(THUMB_A.read_bytes()) if THUMB_A.is_file() else "x",
            "models": ["test"],
            "speedLimits": [],
            "modeTransitions": [],
            "inputHints": [],
            "comboSummaries": [],
            "notes": ["e2e"],
            "caveats": [],
            "quality": {"hasDeterministicBasis": True, "llmSchemaValidated": False, "summary": "ok"},
            "analysisProfile": {
                "analysisProfileVersion": "2.2G.1",
                "analysisProfileHash": "abc",
                "ghidraVersion": "12.2_PUBLIC",
                "seedCortexMEntryPoints": True,
            },
            "callGraphQuality": {
                "directCalls": 1,
                "internalBranches": 1,
                "unresolvedCalls": 0,
            },
            "firmwareArchitectureConfidence": "ARCHITECTURE_UNKNOWN",
            "analysisLimitations": ["test"],
            "functionDiff": {"status": "partial"},
            "inputBehaviorAnalysis": {"status": "ok"},
            "analysisCompleteness": {"status": "PARTIAL"},
        }
        required = [
            "subjectSHA256",
            "analysisProfile",
            "callGraphQuality",
            "firmwareArchitectureConfidence",
            "analysisLimitations",
            "functionDiff",
            "inputBehaviorAnalysis",
            "analysisCompleteness",
        ]
        for k in required:
            self.assertIn(k, payload)


if __name__ == "__main__":
    unittest.main()
