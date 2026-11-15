"""
ScooterCheck firmware analysis worker.

Accepts ZIP/ENC uploads from the app, runs a server-local decrypt command
(DECRYPT_CMD — your already-installed tool wrapper), then returns a
FirmwareDeepAnalysisResult-compatible JSON.

This repository does NOT ship ninebottea or keys.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from ghidra_decompile import ghidra_configured, run_ghidra_decompile
from speed_extract import deep_result

APP = FastAPI(title="ScooterCheck Firmware Analysis", version="1.0.0")

API_TOKEN = os.environ.get("API_TOKEN", "").strip()
DECRYPT_CMD = os.environ.get("DECRYPT_CMD", "").strip()
# Default: run Ghidra when configured; set ENABLE_GHIDRA=0 to skip.
ENABLE_GHIDRA = os.environ.get("ENABLE_GHIDRA", "1").strip() not in ("0", "false", "False")
GHIDRA_PROCESSOR = os.environ.get("GHIDRA_PROCESSOR", "ARM:LE:32:Cortex").strip()
GHIDRA_BASE_ADDR = os.environ.get("GHIDRA_BASE_ADDR", "0x08000000").strip()
WORK_DIR = Path(os.environ.get("WORK_DIR", tempfile.gettempdir() + "/scootercheck-fw-jobs"))
PLAINTEXT_STORE = Path(
    os.environ.get("PLAINTEXT_STORE", str(Path(tempfile.gettempdir()) / "scootercheck-decrypted"))
)
DECOMPILE_STORE = Path(
    os.environ.get("DECOMPILE_STORE", str(Path(tempfile.gettempdir()) / "scootercheck-decompiled"))
)
WORK_DIR.mkdir(parents=True, exist_ok=True)
PLAINTEXT_STORE.mkdir(parents=True, exist_ok=True)
DECOMPILE_STORE.mkdir(parents=True, exist_ok=True)

# In-memory job index (restart loses state — fine for v1; use Redis later).
JOBS: dict[str, dict[str, Any]] = {}


class JobRequestMeta(BaseModel):
    clientReportId: str = ""
    originalFileName: str = ""
    archiveSHA256: str = ""
    payloadSHA256: str | None = None
    infoJSON: str | None = None
    models: list[str] = Field(default_factory=list)
    controllerType: str | None = None
    allowDecrypt: bool = True
    allowLLM: bool = False


def require_token(x_scootercheck_token: str | None = Header(default=None)) -> None:
    if not API_TOKEN:
        # Dev mode: open if no token configured (still bind to localhost in prod).
        return
    if not x_scootercheck_token or x_scootercheck_token != API_TOKEN:
        raise HTTPException(status_code=401, detail="invalid token")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def extract_enc_payload(archive_path: Path, dest_dir: Path) -> tuple[Path, dict[str, Any]]:
    """Return path to FIRM.bin.enc (or bare .enc) and optional info.json dict."""
    info: dict[str, Any] = {}
    suffix = archive_path.suffix.lower()
    if suffix == ".zip":
        with zipfile.ZipFile(archive_path, "r") as zf:
            names = zf.namelist()
            enc_name = next(
                (n for n in names if n.lower().endswith("firm.bin.enc") or n.lower().endswith(".bin.enc")),
                None,
            )
            if enc_name is None:
                enc_name = next((n for n in names if n.lower().endswith(".enc")), None)
            if enc_name is None:
                raise HTTPException(status_code=400, detail="ZIP contains no .enc payload")
            enc_path = dest_dir / "FIRM.bin.enc"
            with zf.open(enc_name) as src, enc_path.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            info_name = next((n for n in names if n.lower().endswith("info.json")), None)
            if info_name:
                raw = zf.read(info_name)
                try:
                    info = json.loads(raw.decode("utf-8"))
                except Exception:
                    info = {}
            return enc_path, info
    # bare enc/bin
    enc_path = dest_dir / archive_path.name
    shutil.copy2(archive_path, enc_path)
    return enc_path, info


def run_decrypt(enc_path: Path, out_bin: Path) -> tuple[bool, str]:
    if not DECRYPT_CMD:
        return False, "DECRYPT_CMD not set — point it at your installed decrypt wrapper"
    if not Path(DECRYPT_CMD).exists() and not shutil.which(DECRYPT_CMD.split()[0]):
        # Allow "cmd with args" only as single executable path for v1
        if not Path(DECRYPT_CMD).exists():
            return False, f"DECRYPT_CMD not found: {DECRYPT_CMD}"
    try:
        proc = subprocess.run(
            [DECRYPT_CMD, str(enc_path), str(out_bin)],
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, "decrypt timed out"
    except OSError as e:
        return False, f"decrypt spawn failed: {e}"
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()[:500]
        return False, f"decrypt exit {proc.returncode}: {err}"
    if not out_bin.exists() or out_bin.stat().st_size == 0:
        return False, "decrypt produced empty output"
    return True, "ok"


def job_status_payload(job: dict[str, Any]) -> dict[str, Any]:
    return {
        "jobId": job["jobId"],
        "state": job["state"],
        "progressPercent": job["progressPercent"],
        "message": job["message"],
        "result": job.get("result"),
        "errorCode": job.get("errorCode"),
        "plaintextSHA256": job.get("plaintextSHA256"),
        "encSHA256": job.get("encSHA256"),
        "plaintextPath": job.get("plaintextPath"),
        "plaintextSaved": job.get("plaintextSaved", False),
        "decompilePath": job.get("decompilePath"),
        "decompileSaved": job.get("decompileSaved", False),
    }


@APP.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "decryptConfigured": bool(DECRYPT_CMD),
        "ghidraConfigured": ghidra_configured(),
        "ghidraEnabled": ENABLE_GHIDRA,
        "time": datetime.now(timezone.utc).isoformat(),
    }


@APP.post("/v1/firmware/jobs")
async def submit_job(
    meta_json: str = Form(..., description="FirmwareAnalysisJobRequest JSON"),
    archive: UploadFile = File(...),
    _: None = Depends(require_token),
) -> JSONResponse:
    try:
        meta = JobRequestMeta.model_validate_json(meta_json)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"invalid meta_json: {e}") from e

    job_id = str(uuid.uuid4())
    job_dir = WORK_DIR / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    archive_path = job_dir / (meta.originalFileName or archive.filename or "upload.bin")
    raw = await archive.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty upload")
    archive_path.write_bytes(raw)
    archive_sha = sha256_bytes(raw)

    job: dict[str, Any] = {
        "jobId": job_id,
        "state": "queued",
        "progressPercent": 5,
        "message": "upload stored",
        "result": None,
        "errorCode": None,
        "dir": str(job_dir),
        "meta": meta.model_dump(),
        "encSHA256": None,
        "plaintextSHA256": None,
    }
    JOBS[job_id] = job

    # Synchronous v1 processing (queue/worker later).
    job["state"] = "decrypting"
    job["progressPercent"] = 20
    job["message"] = "extracting encrypted payload"

    try:
        enc_path, info = extract_enc_payload(archive_path, job_dir)
    except HTTPException:
        job["state"] = "failed"
        job["errorCode"] = "NO_ENC_PAYLOAD"
        job["message"] = "no encrypted firmware payload in upload"
        return JSONResponse(job_status_payload(job))

    enc_sha = sha256_file(enc_path)
    job["encSHA256"] = enc_sha

    # Merge info.json models if meta empty
    fw = info.get("firmware") if isinstance(info.get("firmware"), dict) else {}
    models = meta.models or (
        [fw["model"]] if isinstance(fw.get("model"), str) else list(fw.get("models") or [])
    )
    display = fw.get("displayName") if isinstance(fw.get("displayName"), str) else None
    ctype = meta.controllerType or (fw.get("type") if isinstance(fw.get("type"), str) else None)

    notes: list[str] = [f"archiveSHA256={archive_sha}", f"encSHA256={enc_sha}"]
    plaintext = b""
    decrypt_ok = False

    if not meta.allowDecrypt:
        job["state"] = "failed"
        job["errorCode"] = "DECRYPT_NOT_ALLOWED"
        job["message"] = "client set allowDecrypt=false"
        job["progressPercent"] = 100
        return JSONResponse(job_status_payload(job))

    job["progressPercent"] = 40
    job["message"] = "running DECRYPT_CMD"
    out_bin = job_dir / "FIRM.dec.bin"
    ok, msg = run_decrypt(enc_path, out_bin)
    if not ok:
        job["state"] = "failed"
        job["errorCode"] = "DECRYPT_FAILED"
        job["message"] = msg
        job["progressPercent"] = 100
        # Still return a skeleton result so the app can fall back to catalog.
        job["result"] = deep_result(
            subject_sha256=enc_sha,
            display_name=display,
            models=models,
            controller_type=ctype,
            plaintext=b"",
            decrypt_ok=False,
            notes=notes + [msg],
        )
        return JSONResponse(job_status_payload(job))

    plaintext = out_bin.read_bytes()
    decrypt_ok = True
    plain_sha = sha256_bytes(plaintext)
    job["plaintextSHA256"] = plain_sha
    notes.append(f"plaintextSHA256={plain_sha}")
    notes.append(f"plaintextBytes={len(plaintext)}")

    # Durable copy: always keep decrypted file after successful ninebottea run.
    safe_name = (meta.originalFileName or "upload").replace("/", "_")
    stored = PLAINTEXT_STORE / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.bin"
    shutil.copy2(out_bin, stored)
    # Also keep a stable latest pointer per job
    latest = Path(job["dir"]) / "FIRM.dec.bin"
    if stored.resolve() != latest.resolve():
        shutil.copy2(stored, latest)
    job["plaintextPath"] = str(stored)
    job["plaintextSaved"] = True
    notes.append(f"plaintextSaved={stored}")

    decompiled_text: str | None = None
    job["decompileSaved"] = False
    job["decompilePath"] = None

    if ENABLE_GHIDRA and ghidra_configured():
        job["state"] = "decompiling"
        job["progressPercent"] = 60
        job["message"] = "Ghidra Headless decompiliert…"
        out_c = DECOMPILE_STORE / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.c"
        job_c = Path(job["dir"]) / "FIRM.dec.c"
        ok_g, msg_g = run_ghidra_decompile(
            stored,
            out_c,
            processor=GHIDRA_PROCESSOR,
            base_addr=GHIDRA_BASE_ADDR,
        )
        notes.append(f"ghidra={msg_g}")
        if ok_g:
            shutil.copy2(out_c, job_c)
            job["decompilePath"] = str(out_c)
            job["decompileSaved"] = True
            decompiled_text = out_c.read_text(encoding="utf-8", errors="replace")
            job["message"] = f"Decompile gespeichert: {out_c.name}"
        else:
            job["message"] = f"Decrypt OK, Ghidra fehlgeschlagen: {msg_g}"
    elif ENABLE_GHIDRA:
        notes.append("ghidra=skipped (GHIDRA_HOME / GHIDRA_HEADLESS not set)")
    else:
        notes.append("ghidra=disabled (ENABLE_GHIDRA=0)")

    job["state"] = "extracting"
    job["progressPercent"] = 85
    job["message"] = "Speed-Signaturen aus Klartext/Decompile…"

    result = deep_result(
        subject_sha256=enc_sha,
        display_name=display,
        models=models,
        controller_type=ctype,
        plaintext=plaintext,
        decrypt_ok=decrypt_ok,
        notes=notes,
        decompiled_text=decompiled_text,
    )
    # Mark source as server decrypt path
    if "serverDecompile" not in result["sources"]:
        result["sources"] = list(result["sources"]) + ["serverDecompile"]

    job["result"] = result
    job["state"] = "completed"
    job["progressPercent"] = 100
    parts = [f"Decrypt OK ({len(plaintext)} Byte) → {stored}"]
    if job.get("decompileSaved"):
        parts.append(f"Ghidra .c → {job['decompilePath']}")
    job["message"] = " · ".join(parts)
    job["errorCode"] = None
    return JSONResponse(job_status_payload(job))


@APP.get("/v1/firmware/jobs/{job_id}")
def get_job(job_id: str, _: None = Depends(require_token)) -> JSONResponse:
    job = JOBS.get(job_id)
    if not job:
        # Try reload marker file for restart resilience (optional)
        raise HTTPException(status_code=404, detail="job not found")
    return JSONResponse(job_status_payload(job))


@APP.get("/v1/firmware/jobs/{job_id}/plaintext")
def download_plaintext(job_id: str, _: None = Depends(require_token)):
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("plaintextPath") or (Path(job["dir"]) / "FIRM.dec.bin"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="plaintext not available")
    from fastapi.responses import FileResponse

    return FileResponse(path, filename=path.name, media_type="application/octet-stream")


@APP.get("/v1/firmware/jobs/{job_id}/decompile")
def download_decompile(job_id: str, _: None = Depends(require_token)):
    job = JOBS.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("decompilePath") or (Path(job["dir"]) / "FIRM.dec.c"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="decompile not available")
    from fastapi.responses import FileResponse

    return FileResponse(path, filename=path.name, media_type="text/plain")
