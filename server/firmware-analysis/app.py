"""
ScooterCheck firmware analysis worker.

App upload → structured job dir → ninebottea (DECRYPT_CMD) → optional Ghidra
→ FirmwareDeepAnalysisResult JSON back to the app.

Does NOT ship ninebottea or keys.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import threading
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from angr_lite import (
    analyze_firmware as angr_analyze,
    angr_configured,
    angr_engine_available,
    merge_angr_into_result,
)
from capstone_extract import (
    analyze_firmware as capstone_analyze,
    capstone_configured,
    merge_capstone_into_result,
)
from ghidra_decompile import ghidra_configured, load_speed_xrefs, run_ghidra_decompile
from llm_enrich import (
    _model as llm_model_name,
    enrich_result,
    llm_configured,
    llm_key_status,
    llm_provider,
)
from r2_extract import analyze_firmware as r2_analyze, merge_r2_into_result, r2_configured
from speed_extract import deep_result
from stock_diff import (
    compare_to_stock,
    delete_stock_ref,
    ensure_stock_dir,
    list_stock_refs,
    register_stock_file,
    stock_dir,
)
from unicorn_emulate import (
    analyze_firmware as unicorn_analyze,
    merge_unicorn_into_result,
    unicorn_configured,
)
from yara_scan import merge_yara_into_result, scan_firmware as yara_scan, yara_configured

APP = FastAPI(title="ScooterCheck Firmware Analysis", version="1.5.0")

API_TOKEN = os.environ.get("API_TOKEN", "").strip()
JWT_SECRET = os.environ.get("JWT_SECRET", "").strip()
JWT_ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256").strip() or "HS256"
DECRYPT_CMD = os.environ.get("DECRYPT_CMD", "").strip()
ENABLE_GHIDRA = os.environ.get("ENABLE_GHIDRA", "1").strip() not in ("0", "false", "False")
GHIDRA_PROCESSOR = os.environ.get("GHIDRA_PROCESSOR", "ARM:LE:32:Cortex").strip()
GHIDRA_BASE_ADDR = os.environ.get("GHIDRA_BASE_ADDR", "0x08000000").strip()
# Keep artifacts this many days (upload + plaintext + .c). 0 = keep forever.
JOB_RETENTION_DAYS = int(os.environ.get("JOB_RETENTION_DAYS", "30") or "30")
# Soft cap: when exceeded, oldest completed jobs are pruned first.
MAX_STORED_JOBS = int(os.environ.get("MAX_STORED_JOBS", "500") or "500")
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
# Ghidra is RAM-heavy — only one headless run at a time. Decrypt may still overlap.
# Serialize Ghidra + angr so the 4 GB VPS does not OOM.
_HEAVY_ANALYSIS_LOCK = threading.Lock()
_GHIDRA_LOCK = _HEAVY_ANALYSIS_LOCK  # alias for existing call sites


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


def require_admin(auth: dict[str, Any] = Depends(require_auth)) -> dict[str, Any]:
    if auth.get("auth") == "api_token":
        return auth
    if auth.get("role") == "admin":
        return auth
    raise HTTPException(status_code=403, detail="admin only")


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


def _request_meta(job: dict[str, Any]) -> dict[str, Any]:
    req = job.get("request")
    return req if isinstance(req, dict) else {}


def job_status_payload(job: dict[str, Any], *, include_result: bool = True) -> dict[str, Any]:
    req = _request_meta(job)
    payload = {
        "jobId": job["jobId"],
        "state": job["state"],
        "progressPercent": job["progressPercent"],
        "message": job["message"],
        "errorCode": job.get("errorCode"),
        "createdBy": job.get("createdBy"),
        "createdByUserId": job.get("createdByUserId"),
        "createdAt": job.get("createdAt"),
        "updatedAt": job.get("updatedAt"),
        "originalFileName": req.get("originalFileName") or job.get("originalFileName"),
        "archiveSHA256": job.get("archiveSHA256"),
        "plaintextSHA256": job.get("plaintextSHA256"),
        "encSHA256": job.get("encSHA256"),
        "plaintextPath": job.get("plaintextPath"),
        "plaintextSaved": job.get("plaintextSaved", False),
        "decompilePath": job.get("decompilePath"),
        "decompileSaved": job.get("decompileSaved", False),
    }
    if include_result:
        payload["result"] = job.get("result")
    return payload


def iter_status_files() -> list[Path]:
    files = list(WORK_DIR.glob("*/*/*/*/status.json"))
    files += list(WORK_DIR.glob("*/status.json"))  # legacy flat
    # unique by resolved path
    seen: set[str] = set()
    out: list[Path] = []
    for p in files:
        key = str(p.resolve())
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def list_jobs_from_disk() -> list[dict[str, Any]]:
    jobs: list[dict[str, Any]] = []
    for status in iter_status_files():
        try:
            data = json.loads(status.read_text(encoding="utf-8"))
        except Exception:
            continue
        data["dir"] = str(status.parent)
        jid = data.get("jobId")
        if isinstance(jid, str):
            JOBS[jid] = data
        jobs.append(data)
    jobs.sort(key=lambda j: str(j.get("createdAt") or ""), reverse=True)
    return jobs


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


def delete_job_artifacts(job: dict[str, Any]) -> None:
    for key in ("plaintextPath", "decompilePath", "archivePath"):
        p = job.get(key)
        if isinstance(p, str) and p:
            path = Path(p)
            if path.exists():
                try:
                    path.unlink()
                except OSError:
                    pass
    job_dir = job.get("dir")
    if isinstance(job_dir, str) and job_dir:
        try:
            shutil.rmtree(job_dir, ignore_errors=True)
        except OSError:
            pass
    jid = job.get("jobId")
    if isinstance(jid, str):
        JOBS.pop(jid, None)


def cleanup_old_jobs() -> dict[str, int]:
    """Age-based + soft count cap. Safe to call on submit / admin list."""
    removed_age = 0
    removed_cap = 0
    jobs = list_jobs_from_disk()
    if JOB_RETENTION_DAYS > 0:
        cutoff = _utc_now() - timedelta(days=JOB_RETENTION_DAYS)
        keep: list[dict[str, Any]] = []
        for job in jobs:
            created = _parse_iso(job.get("createdAt") or job.get("updatedAt"))
            if created is not None and created < cutoff and job.get("state") in (
                "completed",
                "failed",
            ):
                delete_job_artifacts(job)
                removed_age += 1
            else:
                keep.append(job)
        jobs = keep
    if MAX_STORED_JOBS > 0 and len(jobs) > MAX_STORED_JOBS:
        # oldest first among finished jobs
        finished = [
            j
            for j in sorted(jobs, key=lambda x: str(x.get("createdAt") or ""))
            if x.get("state") in ("completed", "failed")
        ]
        overflow = len(jobs) - MAX_STORED_JOBS
        for job in finished[:overflow]:
            delete_job_artifacts(job)
            removed_cap += 1
    return {"removedByAge": removed_age, "removedByCap": removed_cap}


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

    r2_info: dict[str, Any] = {"ok": False, "speeds": [], "notes": [], "stringsSample": []}
    if r2_configured():
        _update(job, progressPercent=58, message="radare2 Speed-/String-Scan…")
        r2_info = r2_analyze(stored)
        notes.extend(r2_info.get("notes") or [])
    else:
        notes.append("r2=skipped (radare2 not installed or ENABLE_R2=0)")

    ghidra_xrefs: dict[str, Any] = {"ok": False, "speeds": [], "notes": []}
    if ENABLE_GHIDRA and ghidra_configured():
        _update(
            job,
            state="decompiling",
            progressPercent=60,
            message="Ghidra wartet / decompiliert zu .c …",
        )
        out_c = DECOMPILE_STORE / day / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.c"
        out_c.parent.mkdir(parents=True, exist_ok=True)
        job_c = job_dir / "FIRM.dec.c"
        # Serialize Ghidra so parallel uploads don't OOM the VPS.
        speed_json = out_c.with_suffix(".speeds.json")
        with _GHIDRA_LOCK:
            _update(job, message="Ghidra Headless decompiliert → .c + Speed-Xrefs…")
            ok_g, msg_g = run_ghidra_decompile(
                stored,
                out_c,
                processor=GHIDRA_PROCESSOR,
                base_addr=GHIDRA_BASE_ADDR,
                speed_json=speed_json,
            )
        notes.append(f"ghidra={msg_g}")
        if ok_g:
            shutil.copy2(out_c, job_c)
            decompiled_text = out_c.read_text(encoding="utf-8", errors="replace")
            ghidra_xrefs = load_speed_xrefs(speed_json)
            notes.extend(ghidra_xrefs.get("notes") or [])
            _update(
                job,
                decompilePath=str(out_c),
                decompileSaved=True,
                message=f"Decompile .c gespeichert: {out_c.name}",
            )
        else:
            _update(job, message=f"Decrypt OK, Ghidra fehlgeschlagen: {msg_g}")
    elif ENABLE_GHIDRA:
        notes.append("ghidra=skipped (GHIDRA_HOME / GHIDRA_HEADLESS not set)")
    else:
        notes.append("ghidra=disabled (ENABLE_GHIDRA=0)")

    _update(job, progressPercent=78, message="Capstone Disasm-Scan…")
    cs_info = capstone_analyze(stored) if capstone_configured() else {
        "ok": False,
        "speeds": [],
        "notes": ["capstone=skipped"],
    }
    notes.extend(cs_info.get("notes") or [])

    _update(job, progressPercent=82, message="YARA-Signaturen…")
    yr_info = yara_scan(stored) if yara_configured() else {
        "ok": False,
        "matches": [],
        "notes": ["yara=skipped"],
    }
    notes.extend(yr_info.get("notes") or [])

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
    result = merge_r2_into_result(result, r2_info)
    # Merge Ghidra listing xrefs (same source tag serverDecompile)
    if ghidra_xrefs.get("ok"):
        by_packed = {
            s.get("packedU16"): s
            for s in (result.get("speedLimits") or [])
            if s.get("packedU16") is not None
        }
        for s in ghidra_xrefs.get("speeds") or []:
            p = s.get("packedU16")
            if p not in by_packed:
                by_packed[p] = s
            elif "Ghidra xref" not in str(by_packed[p].get("evidence") or ""):
                by_packed[p]["evidence"] = (
                    str(by_packed[p].get("evidence") or "") + " · " + str(s.get("evidence") or "")
                ).strip(" ·")
        result["speedLimits"] = sorted(by_packed.values(), key=lambda x: x["kmh"])
    result = merge_capstone_into_result(result, cs_info)
    result = merge_yara_into_result(result, yr_info)

    _update(job, progressPercent=86, message="Unicorn-Emulation (Speed-Fenster)…")
    uni_info = unicorn_analyze(stored) if unicorn_configured() else {
        "ok": False,
        "speeds": [],
        "notes": ["unicorn=skipped"],
        "sites": [],
    }
    result = merge_unicorn_into_result(result, uni_info)

    _update(job, progressPercent=87, message="Pfadanalyse (Capstone/angr-CFGFast)…")
    if angr_configured():
        # Never overlap with Ghidra/Unicorn-heavy work on this box.
        with _HEAVY_ANALYSIS_LOCK:
            ang_info = angr_analyze(stored)
    else:
        ang_info = {
            "ok": False,
            "notes": ["angr_lite=skipped"],
            "transitions": [],
            "pathHints": [],
        }
    result = merge_angr_into_result(result, ang_info)

    _update(job, progressPercent=88, message="Stock-Diff gegen Referenzbibliothek…")
    stock = compare_to_stock(plaintext, models=models, controller_type=ctype)
    result["stockDiff"] = stock
    result.setdefault("notes", []).append(f"stockDiff={stock.get('outcome')}: {stock.get('note')}")

    if meta.allowLLM and llm_configured():
        _update(job, state="llmEnrichment", progressPercent=92, message="KI-Anreicherung (schema)…")
        result = enrich_result(result, decompiled_text=decompiled_text)
    elif meta.allowLLM:
        # enrich_result also annotates bad key kinds (e.g. sk-ant-oat OAuth)
        result = enrich_result(result, decompiled_text=decompiled_text)
        if not any(str(n).startswith("llm=") for n in (result.get("notes") or [])):
            result.setdefault("notes", []).append("llm=skipped (LLM_API_KEY not set)")

    parts = [f"Decrypt OK ({len(plaintext)} Byte) → {stored}"]
    if r2_info.get("ok"):
        parts.append(f"r2 {len(r2_info.get('speeds') or [])} Speeds")
    if cs_info.get("ok"):
        parts.append(f"capstone {len(cs_info.get('speeds') or [])}")
    if yr_info.get("ok"):
        parts.append(f"yara {len(yr_info.get('matches') or [])}")
    if uni_info.get("ok"):
        parts.append(f"unicorn {len(uni_info.get('speeds') or [])}")
    if ang_info.get("ok"):
        parts.append(f"paths {len(ang_info.get('pathHints') or [])}")
    if job.get("decompileSaved"):
        parts.append(f"Ghidra .c → {job.get('decompilePath')}")
    if stock.get("outcome") == "identical":
        parts.append("Stock identisch")
    elif stock.get("outcome") == "different":
        parts.append(f"Stock-Diff {stock.get('differingBytes')} B")
    if "serverLLM" in (result.get("sources") or []):
        parts.append("KI-Hinweise")
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
        "retentionDays": JOB_RETENTION_DAYS,
        "maxStoredJobs": MAX_STORED_JOBS,
        "llmConfigured": llm_configured(),
        "llmKeyStatus": llm_key_status(),
        "llmProvider": llm_provider() if llm_configured() else None,
        "llmModel": (llm_model_name() if llm_configured() else None),
        "stockFwDir": str(stock_dir()),
        "stockRefCount": len(list_stock_refs()),
        "r2Configured": r2_configured(),
        "capstoneConfigured": capstone_configured(),
        "yaraConfigured": yara_configured(),
        "unicornConfigured": unicorn_configured(),
        "angrLiteConfigured": angr_configured(),
        "angrEngineConfigured": angr_engine_available(),
        "angrTimeoutSec": int(os.environ.get("ANGR_TIMEOUT_SEC", "150") or "150"),
        "angrMemMb": int(os.environ.get("ANGR_MEM_MB", "1800") or "1800"),
        "angrCfgDepth": int(os.environ.get("ANGR_CFG_DEPTH", "6") or "6"),
        "angrSymbolic": os.environ.get("ANGR_SYMBOLIC", "0").strip()
        in ("1", "true", "True", "yes"),
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

    cleanup_old_jobs()

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
        "originalFileName": safe_upload_name,
        "request": meta.model_dump(),
        "createdBy": auth.get("email") or auth.get("userId") or auth.get("auth"),
        "createdByUserId": auth.get("userId"),
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


@APP.get("/v1/firmware/admin/jobs")
def admin_list_jobs(
    created_by: str | None = None,
    limit: int = 100,
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    cleanup_old_jobs()
    jobs = list_jobs_from_disk()
    if created_by:
        needle = created_by.strip().lower()
        jobs = [j for j in jobs if str(j.get("createdBy") or "").lower() == needle]
    limit = max(1, min(limit, 500))
    items = [job_status_payload(j, include_result=False) for j in jobs[:limit]]
    return JSONResponse({"jobs": items, "total": len(jobs), "returned": len(items)})


@APP.get("/v1/firmware/admin/stats")
def admin_stats(_: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    cleanup_old_jobs()
    jobs = list_jobs_from_disk()
    by_user: dict[str, dict[str, Any]] = {}
    for job in jobs:
        key = str(job.get("createdBy") or "unknown")
        entry = by_user.setdefault(
            key,
            {
                "createdBy": key,
                "createdByUserId": job.get("createdByUserId"),
                "jobs": 0,
                "completed": 0,
                "failed": 0,
                "queuedOrRunning": 0,
                "withDecompile": 0,
            },
        )
        entry["jobs"] += 1
        state = job.get("state")
        if state == "completed":
            entry["completed"] += 1
        elif state == "failed":
            entry["failed"] += 1
        else:
            entry["queuedOrRunning"] += 1
        if job.get("decompileSaved"):
            entry["withDecompile"] += 1
    users = sorted(by_user.values(), key=lambda u: u["jobs"], reverse=True)
    return JSONResponse(
        {
            "totalJobs": len(jobs),
            "retentionDays": JOB_RETENTION_DAYS,
            "maxStoredJobs": MAX_STORED_JOBS,
            "users": users,
        }
    )


@APP.get("/v1/firmware/admin/stock")
def admin_list_stock(_: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    ensure_stock_dir()
    refs = list_stock_refs()
    return JSONResponse({"stockFwDir": str(stock_dir()), "refs": refs, "count": len(refs)})


@APP.post("/v1/firmware/admin/stock")
async def admin_upload_stock(
    label: str = Form(""),
    model: str = Form(""),
    controllerType: str = Form("VCU"),
    version: str = Form(""),
    file: UploadFile = File(...),
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty file")
    if len(raw) > 16 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="stock file too large (max 16 MiB)")
    ref = register_stock_file(
        raw,
        label=label or (file.filename or "stock"),
        model=model or "unknown",
        controller_type=controllerType or "VCU",
        version=version or "",
        filename=file.filename,
    )
    return JSONResponse({"ok": True, "ref": ref})


@APP.delete("/v1/firmware/admin/stock/{ref_id}")
def admin_delete_stock(ref_id: str, _: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    if not delete_stock_ref(ref_id):
        raise HTTPException(status_code=404, detail="stock ref not found")
    return JSONResponse({"ok": True, "deleted": ref_id})


@APP.post("/v1/firmware/admin/jobs/{job_id}/promote-stock")
def admin_promote_job_stock(
    job_id: str,
    label: str = Query(""),
    model: str = Query(""),
    controllerType: str = Query("VCU"),
    version: str = Query(""),
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    """Copy a job's decrypted plaintext into the stock library for future BinDiff.

    Only use for known OEM/serial reference images — not for arbitrary case uploads,
    or every re-upload of the same file will report stockDiff=identical.
    """
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("plaintextPath") or (Path(job["dir"]) / "FIRM.dec.bin"))
    if not path.is_file():
        raise HTTPException(status_code=404, detail="plaintext not available")
    raw = path.read_bytes()
    ref = register_stock_file(
        raw,
        label=label or (job.get("originalFileName") or f"stock-{job_id[:8]}"),
        model=model or ((job.get("result") or {}).get("models") or ["unknown"])[0],
        controller_type=controllerType or ((job.get("result") or {}).get("controllerType") or "VCU"),
        version=version or "",
        filename=f"{job_id[:8]}.dec.bin",
    )
    return JSONResponse({"ok": True, "ref": ref})


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
def download_decompile(
    job_id: str,
    preview_chars: int = 0,
    _: dict[str, Any] = Depends(require_auth),
):
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("decompilePath") or (Path(job["dir"]) / "FIRM.dec.c"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="decompile not available")
    if preview_chars and preview_chars > 0:
        text = path.read_text(encoding="utf-8", errors="replace")
        limit = max(500, min(preview_chars, 200_000))
        return JSONResponse(
            {
                "jobId": job_id,
                "path": str(path),
                "totalChars": len(text),
                "preview": text[:limit],
                "truncated": len(text) > limit,
            }
        )
    return FileResponse(path, filename=path.name, media_type="text/x-c")


@APP.delete("/v1/firmware/admin/jobs/{job_id}")
def admin_delete_job(job_id: str, _: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    delete_job_artifacts(job)
    return JSONResponse({"message": "deleted", "jobId": job_id})
