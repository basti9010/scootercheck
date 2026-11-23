#!/usr/bin/env python3
"""Isolated ENABLE_GHIDRA=1 pipeline smoke for Phase 2.3.2 (no prod paths).

Usage (on a host with Ghidra + venv):
  WORK_ROOT=/tmp/phase232-e2e \\
  GHIDRA_HOME=/opt/ghidra/ghidra_12.2_PUBLIC \\
  FIRMWARE_BIN=/tmp/.../f3_vcu_1.5.8.bin \\
  python scripts/phase232_isolated_ghidra_e2e.py
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def main() -> int:
    work_root = Path(os.environ.get("WORK_ROOT") or tempfile.mkdtemp(prefix="phase232-e2e-"))
    fw = Path(os.environ["FIRMWARE_BIN"])
    expected_sha = os.environ.get(
        "EXPECTED_SHA256", "895e06427e167ac5bc4f5e1539e68c78cc433448856a199c201d1159a35badc4"
    )
    raw = fw.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != expected_sha:
        print("SHA_MISMATCH", sha, expected_sha)
        return 2

    from staging_harness import apply_env, reload_app_modules, staging_env

    env = staging_env(work_root, enable_ghidra=True)
    env["GHIDRA_HOME"] = os.environ.get("GHIDRA_HOME", "/opt/ghidra/ghidra_12.2_PUBLIC")
    env["ENABLE_GHIDRA"] = "1"
    env["GHIDRA_TIMEOUT_SEC"] = os.environ.get("GHIDRA_TIMEOUT_SEC", "600")
    env["JWT_SECRET"] = env.get("JWT_SECRET") or "phase232-isolated-jwt"

    import jwt
    from fastapi.testclient import TestClient

    with apply_env(env):
        app_mod = reload_app_modules()
        from ghidra_decompile import ghidra_configured

        if not ghidra_configured():
            print("GHIDRA_NOT_CONFIGURED")
            return 3
        client = TestClient(app_mod.APP)
        now = datetime.now(timezone.utc)
        token = jwt.encode(
            {
                "sub": "phase232-user",
                "email": "phase232@example.test",
                "role": "user",
                "status": "active",
                "iat": now,
                "exp": now + timedelta(hours=2),
            },
            env["JWT_SECRET"],
            algorithm="HS256",
        )
        meta = {
            "clientReportId": "phase232-e2e",
            "originalFileName": fw.name,
            "archiveSHA256": sha,
            "allowDecrypt": True,
            "allowLLM": False,
            "controllerType": "VCU",
        }
        r = client.post(
            "/v1/firmware/jobs",
            headers={"Authorization": f"Bearer {token}"},
            files={"archive": (fw.name, raw, "application/octet-stream")},
            data={"meta_json": json.dumps(meta)},
        )
        if r.status_code not in (200, 202):
            print("UPLOAD_FAIL", r.status_code, r.text[:500])
            return 4
        job_id = r.json().get("jobId")
        t0 = time.monotonic()
        app_mod.process_job(job_id)
        elapsed = time.monotonic() - t0
        job = app_mod.load_job(job_id)
        result = (job or {}).get("result") or {}
        poll = client.get(
            f"/v1/firmware/jobs/{job_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        af = client.get(
            f"/v1/firmware/jobs/{job_id}/activation-forensics",
            headers={"Authorization": f"Bearer {token}"},
        )
        sdf = client.get(
            f"/v1/firmware/jobs/{job_id}/semantic-dataflow",
            headers={"Authorization": f"Bearer {token}"},
        )
        foreign = jwt.encode(
            {
                "sub": "other-user",
                "email": "other@example.test",
                "role": "user",
                "status": "active",
                "iat": now,
                "exp": now + timedelta(hours=2),
            },
            env["JWT_SECRET"],
            algorithm="HS256",
        )
        denied = client.get(
            f"/v1/firmware/jobs/{job_id}/semantic-dataflow",
            headers={"Authorization": f"Bearer {foreign}"},
        )
        out = {
            "ok": (job or {}).get("state") == "completed",
            "jobId": job_id,
            "elapsedSec": round(elapsed, 3),
            "plaintextSHA256": (job or {}).get("plaintextSHA256") or result.get("plaintextSHA256"),
            "ghidraNotes": [n for n in (result.get("notes") or []) if "ghidra" in str(n).lower() or "dataflow" in str(n).lower()],
            "activationForensicsPoll": bool((result.get("activationForensics") or {}).get("ok")),
            "semanticDataFlowPoll": (result.get("semanticDataFlow") or result.get("activationForensics") or {}).get(
                "semanticDataFlow"
            )
            is not None
            or bool((result.get("activationForensics") or {}).get("semanticDataFlow")),
            "pollHttp": poll.status_code,
            "activationArtifactHttp": af.status_code,
            "semanticArtifactHttp": sdf.status_code,
            "foreignSemanticHttp": denied.status_code,
            "resultLimits": (result.get("activationForensics") or {}).get("resultLimits"),
            "workRoot": str(work_root),
        }
        print(json.dumps(out, indent=2, ensure_ascii=False))
        # Success criteria
        if out["ok"] and out["pollHttp"] == 200 and out["foreignSemanticHttp"] == 404:
            return 0
        return 5


if __name__ == "__main__":
    raise SystemExit(main())
