"""
ScooterCheck firmware analysis worker.

App upload → structured job dir → ninebottea (DECRYPT_CMD) → optional Ghidra
→ FirmwareDeepAnalysisResult JSON back to the app.

Does NOT ship ninebottea or keys.
"""
from __future__ import annotations

import asyncio
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

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from ghidra_decompile import ghidra_configured, run_ghidra_decompile
from speed_extract import deep_result

APP = FastAPI(title="ScooterCheck Firmware Analysis", version="1.1.0")

API_TOKEN = os.environ.get("API_TOKEN", "").strip()
JWT_SECRET = os.environ.get("JWT_SECRET", "").strip()
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256").strip() or "HS256"
DECRYPT_CMD = os.environ.get("DECRYPT_CMD", "").strip()
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

# Hot cache; disk status.json is source of truth across restarts.
JOBS: dict[str, dict[str, Any]] = {}
_JOB_LOCK = asyncio.Lock()


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


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _job_day_dir(when: datetime | None = None) -> Path:
    when = when or _utc_now()
    return WORK_DIR / f"{when:%Y}" / f"{when:%m}" / f"{when:%d}"


def _status_path(job_dir: Path) -> Path:
    return job_dir / "status.json"


def persist_job(job: dict[str, Any]) -> None:
    job_dir = Path(job["dir"])
    job_dir.mkdir(parents=True, exist_ok=True)
    payload = {k: v for k, v in job.items() if k != "meta"}
    payload["updatedAt"] = _utc_now().isoformat()
    _status_path(job_dir).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    JOBS[job["jobId"]] = job


def load_job(job_id: str) -> dict[str, Any] | None:
    if job_id in JOBS:
        return JOBS[job_id]
    # Structured layout: WORK_DIR/YYYY/MM/DD/<jobId>/status.json
    matches = list(WORK_DIR.glob(f"*/*/*/{job_id}/status.json"))
    if not matches:
        # Legacy flat layout
        flat = WORK_DIR / job_id / "status.json"
        if flat.exists():
            matches = [flat]
    if not matches:
        return None
    try:
        data = json.loads(matches[0].read_text(encoding="utf-8"))
    except Exception:
        return None
    data["dir"] = str(matches[0].parent)
    JOBS[job_id] = data
    return data


def require_auth(
    authorization: str | None = Header(default=None),
    x_scootercheck_token: str | None = Header(default=None),
) -> dict[str, Any]:
    """Accept active ScooterCheck JWT and/or shared X-ScooterCheck-Token."""
    if API_TOKEN and x_scootercheck_token and x_scootercheck_token == API_TOKEN:
        return {"auth": "api_token"}

    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        if not JWT_SECRET:
            raise HTTPException(status_code=401, detail="JWT auth not configured on firmware worker")
        try:
            import jwt

            payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        except Exception as e:
            raise HTTPException(status_code=401, detail=f"invalid token: {e}") from e
        status = str(payload.get("status") or "")
        if status != "active":
            raise HTTPException(status_code=403, detail="account not active")
        return {
            "auth": "jwt",
            "userId": payload.get("sub"),
            "email": payload.get("email"),
            "role": payload.get("role"),
        }

    if not API_TOKEN and not JWT_SECRET:
        # Dev mode: open if nothing configured (still bind localhost in prod).
        return {"auth": "open"}

    raise HTTPException(status_code=401, detail="missing or invalid credentials")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def extract_enc_payload(archive_path: Path, dest_dir: Path) -> tuple[Path, dict[str, Any]]:
    """Return path to FIRM.bin.enc (or bare .enc/.bin) and optional info.json dict."""
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
    enc_path = dest_dir / archive_path.name
    shutil.copy2(archive_path, enc_path)
    return enc_path, info


def run_decrypt(enc_path: Path, out_bin: Path) -> tuple[bool, str]:
    if not DECRYPT_CMD:
        return False, "DECRYPT_CMD not set — point it at your installed decrypt wrapper"
    if not Path(DECRYPT_CMD).exists() and not shutil.which(DECRYPT_CMD.split()[0]):
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


def _update(job: dict[str, Any], **fields: Any) -> None:
    job.update(fields)
    persist_job(job)


def process_job(job_id: str) -> None:
    job = load_job(job_id)
    if not job:
        return
    job_dir = Path(job["dir"])
    meta = JobRequestMeta.model_validate(job.get("request") or {})
    archive_path = Path(job["archivePath"])
    archive_sha = job.get("archiveSHA256") or sha256_file(archive_path)

    _update(job, state="decrypting", progressPercent=20, message="extracting encrypted payload")

    try:
        enc_path, info = extract_enc_payload(archive_path, job_dir)
    except HTTPException as e:
        _update(
            job,
            state="failed",
            errorCode="NO_ENC_PAYLOAD",
            message=str(e.detail),
            progressPercent=100,
        )
        return

    enc_sha = sha256_file(enc_path)
    _update(job, encSHA256=enc_sha)

    fw = info.get("firmware") if isinstance(info.get("firmware"), dict) else {}
    models = meta.models or (
        [fw["model"]] if isinstance(fw.get("model"), str) else list(fw.get("models") or [])
    )
    display = fw.get("displayName") if isinstance(fw.get("displayName"), str) else None
    ctype = meta.controllerType or (fw.get("type") if isinstance(fw.get("type"), str) else None)

    notes: list[str] = [f"archiveSHA256={archive_sha}", f"encSHA256={enc_sha}"]

    if not meta.allowDecrypt:
        _update(
            job,
            state="failed",
            errorCode="DECRYPT_NOT_ALLOWED",
            message="client set allowDecrypt=false",
            progressPercent=100,
        )
        return

    _update(job, progressPercent=40, message="ninebottea decrypt…")
    out_bin = job_dir / "FIRM.dec.bin"
    ok, msg = run_decrypt(enc_path, out_bin)
    if not ok:
        result = deep_result(
            subject_sha256=enc_sha,
            display_name=display,
            models=models,
            controller_type=ctype,
            plaintext=b"",
            decrypt_ok=False,
            notes=notes + [msg],
        )
        _update(
            job,
            state="failed",
            errorCode="DECRYPT_FAILED",
            message=msg,
            progressPercent=100,
            result=result,
        )
        return

    plaintext = out_bin.read_bytes()
    plain_sha = sha256_bytes(plaintext)
    notes.append(f"plaintextSHA256={plain_sha}")
    notes.append(f"plaintextBytes={len(plaintext)}")

    safe_name = (meta.originalFileName or "upload").replace("/", "_")
    day = _utc_now().strftime("%Y/%m/%d")
    stored = PLAINTEXT_STORE / day / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.bin"
    stored.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(out_bin, stored)
    _update(
        job,
        plaintextSHA256=plain_sha,
        plaintextPath=str(stored),
        plaintextSaved=True,
        progressPercent=55,
        message=f"Decrypt OK ({len(plaintext)} Byte)",
    )
    notes.append(f"plaintextSaved={stored}")

    decompiled_text: str | None = None
    _update(job, decompileSaved=False, decompilePath=None)

    if ENABLE_GHIDRA and ghidra_configured():
        _update(job, state="decompiling", progressPercent=60, message="Ghidra Headless decompiliert…")
        out_c = DECOMPILE_STORE / day / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.c"
        out_c.parent.mkdir(parents=True, exist_ok=True)
        job_c = job_dir / "FIRM.dec.c"
        ok_g, msg_g = run_ghidra_decompile(
            stored,
            out_c,
            processor=GHIDRA_PROCESSOR,
            base_addr=GHIDRA_BASE_ADDR,
        )
        notes.append(f"ghidra={msg_g}")
        if ok_g:
            shutil.copy2(out_c, job_c)
            decompiled_text = out_c.read_text(encoding="utf-8", errors="replace")
            _update(
                job,
                decompilePath=str(out_c),
                decompileSaved=True,
                message=f"Decompile gespeichert: {out_c.name}",
            )
        else:
            _update(job, message=f"Decrypt OK, Ghidra fehlgeschlagen: {msg_g}")
    elif ENABLE_GHIDRA:
        notes.append("ghidra=skipped (GHIDRA_HOME / GHIDRA_HEADLESS not set)")
    else:
        notes.append("ghidra=disabled (ENABLE_GHIDRA=0)")

    _update(job, state="extracting", progressPercent=85, message="Speed-Signaturen aus Klartext/Decompile…")

    result = deep_result(
        subject_sha256=enc_sha,
        display_name=display,
        models=models,
        controller_type=ctype,
        plaintext=plaintext,
        decrypt_ok=True,
        notes=notes,
        decompiled_text=decompiled_text,
    )
    if "serverDecompile" not in result["sources"]:
        result["sources"] = list(result["sources"]) + ["serverDecompile"]

    parts = [f"Decrypt OK ({len(plaintext)} Byte) → {stored}"]
    if job.get("decompileSaved"):
        parts.append(f"Ghidra .c → {job.get('decompilePath')}")
    _update(
        job,
        result=result,
        state="completed",
        progressPercent=100,
        message=" · ".join(parts),
        errorCode=None,
    )


@APP.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "scootercheck-fw",
        "decryptConfigured": bool(DECRYPT_CMD),
        "ghidraConfigured": ghidra_configured(),
        "ghidraEnabled": ENABLE_GHIDRA,
        "jwtConfigured": bool(JWT_SECRET),
        "apiTokenConfigured": bool(API_TOKEN),
        "time": _utc_now().isoformat(),
    }


@APP.post("/v1/firmware/jobs")
async def submit_job(
    background_tasks: BackgroundTasks,
    meta_json: str = Form(..., description="FirmwareAnalysisJobRequest JSON"),
    archive: UploadFile = File(...),
    auth: dict[str, Any] = Depends(require_auth),
) -> JSONResponse:
    try:
        meta = JobRequestMeta.model_validate_json(meta_json)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"invalid meta_json: {e}") from e

    job_id = str(uuid.uuid4())
    job_dir = _job_day_dir() / job_id
    job_dir.mkdir(parents=True, exist_ok=True)

    safe_upload_name = (meta.originalFileName or archive.filename or "upload.bin").replace("/", "_")
    archive_path = job_dir / "upload" / safe_upload_name
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    raw = await archive.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty upload")
    archive_path.write_bytes(raw)
    archive_sha = sha256_bytes(raw)

    (job_dir / "request.json").write_text(
        json.dumps(meta.model_dump(), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    job: dict[str, Any] = {
        "jobId": job_id,
        "state": "queued",
        "progressPercent": 5,
        "message": "upload stored — Warteschlange",
        "result": None,
        "errorCode": None,
        "dir": str(job_dir),
        "archivePath": str(archive_path),
        "archiveSHA256": archive_sha,
        "request": meta.model_dump(),
        "createdBy": auth.get("email") or auth.get("userId") or auth.get("auth"),
        "createdAt": _utc_now().isoformat(),
        "encSHA256": None,
        "plaintextSHA256": None,
        "plaintextPath": None,
        "plaintextSaved": False,
        "decompilePath": None,
        "decompileSaved": False,
    }
    persist_job(job)
    background_tasks.add_task(process_job, job_id)
    return JSONResponse(job_status_payload(job))


@APP.get("/v1/firmware/jobs/{job_id}")
def get_job(job_id: str, _: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return JSONResponse(job_status_payload(job))


@APP.get("/v1/firmware/jobs/{job_id}/plaintext")
def download_plaintext(job_id: str, _: dict[str, Any] = Depends(require_auth)):
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("plaintextPath") or (Path(job["dir"]) / "FIRM.dec.bin"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="plaintext not available")
    return FileResponse(path, filename=path.name, media_type="application/octet-stream")


@APP.get("/v1/firmware/jobs/{job_id}/decompile")
def download_decompile(job_id: str, _: dict[str, Any] = Depends(require_auth)):
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("decompilePath") or (Path(job["dir"]) / "FIRM.dec.c"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="decompile not available")
    return FileResponse(path, filename=path.name, media_type="text/plain")
