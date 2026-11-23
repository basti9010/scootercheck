#!/usr/bin/env python3
"""Phase 2.2H.1 — isolated Backend Ghidra E2E (no production paths / no service restart).

Run on a host that has Ghidra + project venv (typically Hetzner /tmp copy).
Copies reference BINs into an isolated tree, uploads via FastAPI TestClient,
runs process_job with ENABLE_GHIDRA=1, validates function/callgraph artifacts.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import jwt

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# Expected stock SHA-256 prefixes from Phase 2.2E/G calibration
F3_PREFIX = "895e0642"
G3_PREFIX = "1f1e05eb"
F3_FUNCS = 181
G3_FUNCS = 220


def _sha(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _issue(secret: str, sub: str = "e2e-ghidra", role: str = "user") -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": sub,
            "email": f"{sub}@example.test",
            "role": role,
            "status": "active",
            "iat": now,
            "exp": now + timedelta(hours=2),
        },
        secret,
        algorithm="HS256",
    )


def run_one(
    *,
    app_mod,
    client,
    jwt_token: str,
    bin_path: Path,
    label: str,
    expected_funcs: int | None,
) -> dict:
    from fastapi.testclient import TestClient  # noqa: F401

    data = bin_path.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    name = f"{label}.dec.bin"
    meta = {
        "clientReportId": f"22h1-{label}",
        "originalFileName": name,
        "archiveSHA256": sha,
        "models": [label.split("_")[0]],
        "controllerType": "VCU",
        "allowDecrypt": True,
        "allowLLM": False,
    }
    headers = {"Authorization": f"Bearer {jwt_token}"}
    t0 = time.monotonic()
    r = client.post(
        "/v1/firmware/jobs",
        files={"archive": (name, data, "application/octet-stream")},
        data={"meta_json": json.dumps(meta)},
        headers=headers,
    )
    upload_ms = int((time.monotonic() - t0) * 1000)
    if r.status_code not in {200, 202}:
        return {
            "ok": False,
            "label": label,
            "sha256": sha,
            "uploadStatus": r.status_code,
            "uploadBody": r.text[:500],
        }
    job_id = r.json().get("jobId")
    t1 = time.monotonic()
    app_mod.process_job(job_id)
    elapsed = time.monotonic() - t1
    job = app_mod.load_job(job_id)
    result = (job or {}).get("result") or {}
    # Artifact endpoints
    arts = {}
    for key, path in (
        ("functions", f"/v1/firmware/jobs/{job_id}/functions"),
        ("callgraph", f"/v1/firmware/jobs/{job_id}/callgraph"),
        ("functionDiff", f"/v1/firmware/jobs/{job_id}/function-diff"),
        ("inputBehavior", f"/v1/firmware/jobs/{job_id}/input-behavior"),
    ):
        ar = client.get(path, headers=headers)
        arts[key] = {
            "status": ar.status_code,
            "bytes": len(ar.content),
            "contentType": ar.headers.get("content-type"),
        }
        if ar.status_code == 200 and key in {"functions", "callgraph"}:
            try:
                arts[key]["jsonKeys"] = sorted((ar.json() or {}).keys())[:20]
            except Exception:
                pass

    fa_path = Path(job.get("dir") or "") / "FIRM.functions.json"
    cg_path = Path(job.get("dir") or "") / "FIRM.callgraph.json"
    fa = json.loads(fa_path.read_text(encoding="utf-8")) if fa_path.is_file() else {}
    cg = json.loads(cg_path.read_text(encoding="utf-8")) if cg_path.is_file() else {}
    fn_count = int(fa.get("functionCount") or len(fa.get("functions") or []) or 0)
    cgq = (result.get("callGraphQuality") or cg.get("callGraphQuality") or {})
    profile = result.get("analysisProfile") or fa.get("analysisProfile") or {}
    notes = " ".join(result.get("notes") or [])
    ghidra_ran = "ghidra=" in notes.lower() and "skipped" not in notes.lower().split("ghidra=")[-1][:40]
    if job.get("decompileSaved") or fa_path.is_file():
        ghidra_ran = True

    out = {
        "ok": job.get("state") == "completed" and fn_count > 0,
        "label": label,
        "sha256": sha,
        "jobIdAnon": (job_id or "")[:8] + "…",
        "state": job.get("state"),
        "message": (job.get("message") or "")[:240],
        "uploadStatus": r.status_code,
        "uploadMs": upload_ms,
        "processElapsedSec": round(elapsed, 2),
        "plaintextSHA256": job.get("plaintextSHA256"),
        "decompileSaved": job.get("decompileSaved"),
        "functionsPathExists": fa_path.is_file(),
        "callgraphPathExists": cg_path.is_file(),
        "functionCount": fn_count,
        "expectedFunctionCount": expected_funcs,
        "functionCountMatch": (fn_count == expected_funcs) if expected_funcs else None,
        "analysisProfileVersion": profile.get("analysisProfileVersion"),
        "analysisProfileHash": profile.get("analysisProfileHash"),
        "ghidraVersion": profile.get("ghidraVersion") or fa.get("ghidraVersion"),
        "processor": fa.get("processor") or profile.get("processorArchitecture"),
        "requestedLoaderBase": fa.get("requestedLoaderBase") or (result.get("ghidraAddressLayout") or {}).get("requestedLoaderBase"),
        "actualImageBase": fa.get("actualImageBase") or (result.get("ghidraAddressLayout") or {}).get("actualImageBase"),
        "memoryBlockStart": fa.get("memoryBlockStart") or (result.get("ghidraAddressLayout") or {}).get("memoryBlockStart"),
        "resetHandlerAddress": fa.get("resetHandlerAddress") or (result.get("ghidraAddressLayout") or {}).get("resetHandlerAddress"),
        "callGraphQuality": {
            "directCalls": cgq.get("directCalls"),
            "indirectCalls": cgq.get("indirectCalls"),
            "internalBranches": cgq.get("internalBranches"),
            "tailCalls": cgq.get("tailCalls"),
            "unresolvedCalls": cgq.get("unresolvedCalls"),
            "edgeCount": cg.get("edgeCount") or (result.get("callGraph") or {}).get("edgeCount"),
        },
        "ghidraRan": ghidra_ran,
        "artifacts": arts,
        "foreignJob404": None,
    }
    # Ownership: foreign JWT must 404
    other = _issue(os.environ["JWT_SECRET"], sub="other-user")
    fr = client.get(f"/v1/firmware/jobs/{job_id}", headers={"Authorization": f"Bearer {other}"})
    out["foreignJob404"] = fr.status_code
    return out


def main() -> int:
    base = Path(os.environ.get("PHASE22H1_ROOT") or tempfile.mkdtemp(prefix="scootercheck-22h1-"))
    base.mkdir(parents=True, exist_ok=True)
    bins_dir = base / "bins"
    bins_dir.mkdir(exist_ok=True)
    report_path = base / "ghidra_backend_e2e_report.json"

    # Locate reference bins (env overrides or stock copies already placed)
    f3 = Path(os.environ.get("F3_BIN") or (bins_dir / "f3_vcu_1.5.8.bin"))
    g3 = Path(os.environ.get("G3_BIN") or (bins_dir / "g3_vcu_1.5.13.bin"))
    if not f3.is_file() or not g3.is_file():
        print("Missing F3/G3 bins — set F3_BIN/G3_BIN or copy into", bins_dir, file=sys.stderr)
        return 2

    f3_sha = _sha(f3)
    g3_sha = _sha(g3)
    if not f3_sha.startswith(F3_PREFIX) or not g3_sha.startswith(G3_PREFIX):
        print("SHA mismatch:", f3_sha, g3_sha, file=sys.stderr)
        return 3

    import staging_harness as staging

    env = staging.staging_env(base / "staging", enable_ghidra=True)
    # Point Ghidra at known install if present
    if not os.environ.get("GHIDRA_HOME"):
        for cand in (
            Path("/opt/ghidra/ghidra_12.2_PUBLIC"),
            Path("/opt/ghidra"),
        ):
            if (cand / "support" / "analyzeHeadless").is_file() or any(
                cand.glob("ghidra_*/support/analyzeHeadless")
            ):
                env["GHIDRA_HOME"] = str(cand)
                break
    else:
        env["GHIDRA_HOME"] = os.environ["GHIDRA_HOME"]
    env["ENABLE_GHIDRA"] = "1"
    env["GHIDRA_SEED_IVT"] = "1"
    env["TRUST_API_TOKEN_CLIENT_ID"] = "0"
    env["API_TOKEN_GRANTS_ADMIN"] = "0"

    with staging.apply_env(env):
        from ghidra_decompile import ghidra_configured

        if not ghidra_configured():
            print("Ghidra not configured after env apply", file=sys.stderr)
            return 4
        app_mod = staging.reload_app_modules()
        from fastapi.testclient import TestClient

        client = TestClient(app_mod.APP)
        token = _issue(env["JWT_SECRET"])
        results = []
        results.append(
            run_one(
                app_mod=app_mod,
                client=client,
                jwt_token=token,
                bin_path=f3,
                label="f3_vcu_1.5.8",
                expected_funcs=F3_FUNCS,
            )
        )
        results.append(
            run_one(
                app_mod=app_mod,
                client=client,
                jwt_token=token,
                bin_path=g3,
                label="g3_vcu_1.5.13",
                expected_funcs=G3_FUNCS,
            )
        )

    report = {
        "phase": "2.2H.1",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "base": str(base),
        "ghidraHome": env.get("GHIDRA_HOME"),
        "results": results,
        "allOk": all(r.get("ok") for r in results),
        "functionCountsMatch": all(r.get("functionCountMatch") for r in results),
    }
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    print("REPORT", report_path)
    return 0 if report["allOk"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
