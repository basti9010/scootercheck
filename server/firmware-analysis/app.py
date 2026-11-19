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
from cortex_m_ivt import analyze_firmware as ivt_analyze, merge_ivt_into_result
from function_analysis import (
    load_call_graph,
    load_function_analysis,
    summarize_call_graph_for_poll,
    summarize_for_poll as summarize_functions_for_poll,
)
from function_diff import compare_function_analyses, summarize_diff_for_poll
from input_behavior import (
    analyze_input_behavior,
    diff_input_behavior,
    summarize_input_behavior_for_poll,
    summarize_input_diff_for_poll,
)
from activation_forensics import (
    run_activation_forensics,
    slice_findings_for_page,
    summarize_activation_forensics_for_poll,
)
from analysis_profile import build_analysis_profile, summarize_profile_for_poll
from ghidra_decompile import ghidra_configured, load_speed_xrefs, run_ghidra_decompile
from input_probe import analyze as input_probe_analyze, merge_into_result as merge_input_probe
from job_auth import (
    api_token_grants_admin,
    enrich_auth_with_client_id,
    is_admin,
    ownership_fields_for_new_job,
    require_job_access,
    trust_api_token_client_id,
)
from limit_slice import analyze as limit_slice_analyze, merge_into_result as merge_limit_slice
from llm_enrich import (
    _model as llm_model_name,
    enrich_result,
    llm_configured,
    llm_key_status,
    llm_provider,
)
from llm_verify import verify_enrichment
from plaintext_detect import looks_like_plaintext_firmware
from r2_extract import analyze_firmware as r2_analyze, merge_r2_into_result, r2_configured
from reference_catalog import (
    build_catalogs,
    find_catalog_for_stock,
    list_catalogs,
)
from speed_extract import deep_result
from stock_diff import (
    TRUSTED_SOURCES,
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
from zip_safe import (
    MAX_UPLOAD_BYTES,
    ZipSafetyError,
    inspect_zip,
    safe_extract_member,
    validate_upload_size,
)

APP = FastAPI(title="ScooterCheck Firmware Analysis", version="1.5.0")

API_TOKEN = os.environ.get("API_TOKEN", "").strip()
# Optional dedicated admin token (preferred over granting admin via shared API_TOKEN).
ADMIN_API_TOKEN = os.environ.get("ADMIN_API_TOKEN", "").strip()
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
    x_scootercheck_client_id: str | None = Header(default=None, alias="X-ScooterCheck-Client-Id"),
) -> dict[str, Any]:
    """Accept active ScooterCheck JWT and/or shared X-ScooterCheck-Token.

    Phase 2.2H.1: Bearer JWT is preferred over shared API token when both are sent
    (JWT is the cryptographic user identity). Shared API tokens authenticate the
    request but do not bind job ownership to X-ScooterCheck-Client-Id unless
    TRUST_API_TOKEN_CLIENT_ID=1 (legacy).
    """
    auth: dict[str, Any]
    # Prefer JWT identity when present (stable sub claim).
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
        sub = payload.get("sub")
        if not sub:
            raise HTTPException(status_code=401, detail="invalid token: missing subject")
        auth = {
            "auth": "jwt",
            "userId": sub,
            "email": payload.get("email"),
            "role": payload.get("role"),
        }
    elif x_scootercheck_token:
        if ADMIN_API_TOKEN and x_scootercheck_token == ADMIN_API_TOKEN:
            auth = {"auth": "api_token", "adminToken": True}
        elif API_TOKEN and x_scootercheck_token == API_TOKEN:
            auth = {"auth": "api_token", "adminToken": False}
        else:
            raise HTTPException(status_code=401, detail="missing or invalid credentials")
    elif not API_TOKEN and not ADMIN_API_TOKEN and not JWT_SECRET:
        # Dev mode: open if nothing configured (still bind localhost in prod).
        auth = {"auth": "open"}
    else:
        raise HTTPException(status_code=401, detail="missing or invalid credentials")
    return enrich_auth_with_client_id(auth, x_scootercheck_client_id)


def require_admin(auth: dict[str, Any] = Depends(require_auth)) -> dict[str, Any]:
    if is_admin(auth):
        return auth
    raise HTTPException(status_code=403, detail="admin only")


def _load_job_authorized(job_id: str, auth: dict[str, Any]) -> dict[str, Any]:
    return require_job_access(load_job(job_id), auth)


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
        try:
            inspect_zip(archive_path)
        except ZipSafetyError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
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
            try:
                safe_extract_member(zf, enc_name, enc_path)
            except ZipSafetyError as e:
                raise HTTPException(status_code=400, detail=str(e)) from e
            info_name = next((n for n in names if n.lower().endswith("info.json")), None)
            if info_name:
                try:
                    raw = zf.read(info_name)
                    if len(raw) > 2 * 1024 * 1024:
                        raise ZipSafetyError("info.json zu groß (>2 MiB).")
                    info = json.loads(raw.decode("utf-8"))
                except ZipSafetyError as e:
                    raise HTTPException(status_code=400, detail=str(e)) from e
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


# App FirmwareDeepAnalysisSource raw values — never emit unknown tags (breaks old TF builds).
_APP_KNOWN_SOURCES = frozenset(
    {
        "localDeterministic",
        "knownCatalog",
        "serverDecompile",
        "serverR2",
        "serverCapstone",
        "serverYara",
        "serverEmulation",
        "serverAngr",
        "serverIvt",  # new builds only; still filtered for legacy via sanitize flag below
        "serverLLM",
        "liveVehicleContext",
    }
)
# Strict set shipped before IVT — keep default responses compatible with TestFlight in the field.
_APP_LEGACY_SAFE_SOURCES = _APP_KNOWN_SOURCES - {"serverIvt"}


def _sanitize_result_for_app(result: Any) -> Any:
    """Drop unknown/breaking sources[] tags; keep cortexMIvt object (ignored by old clients)."""
    if not isinstance(result, dict):
        return result
    out = dict(result)
    raw_sources = out.get("sources") or []
    if isinstance(raw_sources, list):
        out["sources"] = [s for s in raw_sources if isinstance(s, str) and s in _APP_LEGACY_SAFE_SOURCES]
    return out


def _job_artifact_path(job: dict[str, Any], *candidates: Any, fallback_name: str) -> Path | None:
    """Resolve an artifact path that must stay inside the job directory."""
    job_dir = Path(str(job.get("dir") or ""))
    if not job_dir.is_dir():
        return None
    root = job_dir.resolve()
    for cand in candidates:
        if not cand:
            continue
        try:
            p = Path(str(cand)).resolve()
        except OSError:
            continue
        if p.is_file() and (p == root or root in p.parents):
            return p
    fallback = (job_dir / fallback_name).resolve()
    if fallback.is_file() and (fallback == root or root in fallback.parents):
        return fallback
    return None


def _reference_metadata_from_stock(stock: dict[str, Any] | None) -> dict[str, Any]:
    stock = stock or {}
    return {
        "referenceId": stock.get("referenceId"),
        "referenceLabel": stock.get("referenceLabel"),
        "referenceSHA256": stock.get("referenceSHA256"),
        "referenceSource": stock.get("referenceSource"),
        "referenceTrust": stock.get("referenceTrust"),
        "referenceProvenanceVerified": bool(stock.get("referenceProvenanceVerified")),
        "matchedModels": stock.get("matchedModels"),
        "outcome": stock.get("outcome"),
        "note": stock.get("note"),
        "manufacturer": stock.get("manufacturer"),
        "model": stock.get("model"),
        "modelAliases": stock.get("modelAliases") or [],
        "controllerType": stock.get("controllerType"),
        "hardwareVersion": stock.get("hardwareVersion"),
        "firmwareVersion": stock.get("firmwareVersion"),
        "fileSize": stock.get("fileSize") or stock.get("referenceBytes"),
        "origin": stock.get("origin") or stock.get("referenceSource"),
        "addedAt": stock.get("addedAt"),
        "verificationStatus": stock.get("verificationStatus"),
        "compatibility": stock.get("compatibility"),
        "candidateRefCount": stock.get("candidateRefCount"),
        "totalRefCount": stock.get("totalRefCount"),
    }


def _load_stock_function_analysis(stock: dict[str, Any] | None) -> dict[str, Any] | None:
    """Load reference function catalog (Phase 2.1) or legacy sibling *.functions.json."""
    if not stock or stock.get("outcome") not in {"identical", "different"}:
        return None
    # Prefer versioned catalogs keyed by SHA-256 (never alter trust).
    catalog = find_catalog_for_stock(stock)
    if catalog is not None:
        return catalog

    ref_id = str(stock.get("referenceId") or "")
    ref_sha = str(stock.get("referenceSHA256") or "")
    ensure_stock_dir()
    candidates: list[Path] = []
    root = stock_dir()
    for pattern in (
        f"{ref_id}.functions.json",
        f"{ref_sha[:16]}.functions.json",
        f"{ref_sha}.functions.json",
    ):
        if ref_id or ref_sha:
            candidates.append(root / pattern)
    try:
        from stock_diff import _load_refs  # type: ignore

        for r in _load_refs():
            if ref_sha and r.get("sha256") == ref_sha:
                p = Path(r.get("path") or "")
                if p.is_file():
                    candidates.append(p.with_suffix(p.suffix + ".functions.json"))
                    candidates.append(Path(str(p) + ".functions.json"))
    except Exception:
        pass
    for c in candidates:
        if c.is_file():
            return load_function_analysis(c)
    return None


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
        "ownerPrincipal": job.get("ownerPrincipal"),
        "ownerAuthKind": job.get("ownerAuthKind"),
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
        payload["result"] = _sanitize_result_for_app(job.get("result"))
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


def _stock_region_hints(result: dict[str, Any]) -> list[dict[str, Any]]:
    """Collect offset hints from prior analysis stages for stockDiff region tagging."""
    hints: list[dict[str, Any]] = []
    for s in result.get("speedLimits") or []:
        off = s.get("offset") or s.get("fileOffset")
        if off is None:
            continue
        role = str(s.get("role") or "speed")
        hints.append({"offset": off, "kind": f"speed:{role}", "label": f"speed {s.get('kmh')} km/h ({role})"})
    for sl in result.get("limitSlices") or []:
        off = sl.get("offset") or sl.get("fileOffset") or sl.get("addr")
        if off is None:
            continue
        hints.append({"offset": off, "kind": "limit", "label": str(sl.get("note") or "limitSlice")})
    for m in result.get("yaraMatches") or []:
        fam = str(m.get("family") or m.get("rule") or "").lower()
        kind = "panic" if any(k in fam for k in ("panic", "unlock", "cfw", "soft")) else "yara"
        # YARA merge does not always expose offsets; keep as kind-only hint via strings scan in stock_diff
        hints.append({"kind": kind, "label": m.get("rule") or fam})
    return hints


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

    out_bin = job_dir / "FIRM.dec.bin"
    already_plain, plain_reason = looks_like_plaintext_firmware(
        enc_path, original_name=meta.originalFileName or enc_path.name
    )
    if already_plain:
        _update(job, progressPercent=40, message="Klartext erkannt — Decrypt übersprungen")
        shutil.copy2(enc_path, out_bin)
        ok, msg = True, f"already plaintext ({plain_reason})"
        notes.append(msg)
    else:
        _update(job, progressPercent=40, message="ninebottea decrypt…")
        ok, msg = run_decrypt(enc_path, out_bin)
        if not ok:
            # Recovery: ninebottea exit 4 on dumps that are already cleartext
            # (e.g. bare .bin without .dec hint). Filename already ruled out above —
            # only accept strong IVT evidence so real .enc failures stay failed.
            recover, recover_reason = looks_like_plaintext_firmware(
                enc_path,
                original_name=meta.originalFileName or enc_path.name,
                ignore_filename=True,
            )
            if recover and recover_reason == "cortex_m_ivt":
                shutil.copy2(enc_path, out_bin)
                ok, msg = True, f"decrypt failed; treating as plaintext ({recover_reason})"
                notes.append(f"decrypt_error_ignored={msg}")
            else:
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

    # Phase 2.2F/H: container analysis before deep_result (must not touch `result` yet).
    container_meta: dict[str, Any] | None = None
    architecture_confidence: str | None = None
    try:
        from ble_container import identify_ble_container
        from firmware_identify import identify_firmware_image

        container = identify_ble_container(
            plaintext, original_name=job.get("originalFileName") or "upload"
        )
        identity = identify_firmware_image(plaintext)
        container_meta = {
            "ok": bool(container.get("ok") or identity.get("ok")),
            "status": container.get("status") or (
                "ARCHITECTURE_UNKNOWN" if identity.get("architectureUnknown") else "IDENTIFIED"
            ),
            "format": container.get("format"),
            "containerRecognized": bool(container.get("containerRecognized")),
            "architecture": container.get("architecture") or identity.get("processor"),
            "architectureConfidence": container.get("architectureConfidence")
            or identity.get("architectureConfidence")
            or ("ARCHITECTURE_UNKNOWN" if identity.get("architectureUnknown") else None),
            "architectureEvidence": list(container.get("architectureEvidence") or [])[:6],
            "baseAddr": container.get("baseAddr") or identity.get("baseAddr"),
            "imageExtractable": container.get("imageExtractable"),
            "ghidraImportAllowed": container.get("ghidraImportAllowed"),
            "payloadStructure": container.get("payloadStructure"),
            "components": list(container.get("components") or [])[:8],
            "confidence": container.get("confidence") or identity.get("confidence"),
            "analysisLimitations": list(container.get("analysisLimitations") or [])
            + list(identity.get("analysisLimitations") or []),
            "notes": list(container.get("notes") or [])[:6],
        }
        architecture_confidence = container_meta.get("architectureConfidence")
        notes.extend((container.get("notes") or [])[:2])
    except Exception as cont_e:
        notes.append(f"phase22fContainer={type(cont_e).__name__}")

    safe_name = (meta.originalFileName or "upload").replace("/", "_")
    day = _utc_now().strftime("%Y/%m/%d")
    stored = PLAINTEXT_STORE / day / f"{job_id}_{plain_sha[:12]}_{safe_name}.dec.bin"
    stored.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(out_bin, stored)
    decrypt_label = "Klartext übernommen" if already_plain or msg.startswith("decrypt failed") else "Decrypt OK"
    _update(
        job,
        plaintextSHA256=plain_sha,
        plaintextPath=str(stored),
        plaintextSaved=True,
        progressPercent=55,
        message=f"{decrypt_label} ({len(plaintext)} Byte)",
    )
    notes.append(f"plaintextSaved={stored}")

    decompiled_text: str | None = None
    limit_c_text: str | None = None
    _update(job, decompileSaved=False, decompilePath=None)

    r2_info: dict[str, Any] = {"ok": False, "speeds": [], "notes": [], "stringsSample": []}
    if r2_configured():
        _update(job, progressPercent=58, message="radare2 Speed-/String-Scan…")
        r2_info = r2_analyze(stored)
        notes.extend(r2_info.get("notes") or [])
    else:
        notes.append("r2=skipped (radare2 not installed or ENABLE_R2=0)")

    ghidra_xrefs: dict[str, Any] = {"ok": False, "speeds": [], "notes": []}
    # Phase 2.2H: never force Cortex-M Ghidra when container analysis forbids import.
    cont_meta = container_meta or {}
    ghidra_blocked = cont_meta.get("ghidraImportAllowed") is False
    if ghidra_blocked:
        notes.append(
            "ghidra=skipped (architectureConfidence/ghidraImportAllowed=false — "
            "no Cortex-M import without technical evidence)"
        )
        result.setdefault("analysisLimitations", []).append(
            "Ghidra übersprungen: Architektur nicht ausreichend belegt."
        )
        _update(
            job,
            progressPercent=70,
            message="Ghidra übersprungen (Architektur unbestätigt)",
            decompileSaved=False,
        )
    elif ENABLE_GHIDRA and ghidra_configured():
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
        limit_c = out_c.with_suffix(".limits.c")
        functions_json = out_c.with_suffix(".functions.json")
        callgraph_json = out_c.with_suffix(".callgraph.json")
        with _GHIDRA_LOCK:
            _update(
                job,
                message="Ghidra Headless → .c + Speeds + Limits + Funktionen + Callgraph…",
            )
            ok_g, msg_g = run_ghidra_decompile(
                stored,
                out_c,
                processor=GHIDRA_PROCESSOR,
                base_addr=GHIDRA_BASE_ADDR,
                speed_json=speed_json,
                limit_c=limit_c,
                functions_json=functions_json,
                callgraph_json=callgraph_json,
            )
        notes.append(f"ghidra={msg_g}")
        if ok_g:
            shutil.copy2(out_c, job_c)
            decompiled_text = out_c.read_text(encoding="utf-8", errors="replace")
            if limit_c.is_file() and limit_c.stat().st_size > 0:
                limit_c_text = limit_c.read_text(encoding="utf-8", errors="replace")
                shutil.copy2(limit_c, job_dir / "FIRM.limits.c")
            ghidra_xrefs = load_speed_xrefs(speed_json)
            notes.extend(ghidra_xrefs.get("notes") or [])
            # Phase-2 artifacts (best-effort; never abort job if missing).
            try:
                if functions_json.is_file():
                    shutil.copy2(functions_json, job_dir / "FIRM.functions.json")
                if callgraph_json.is_file():
                    shutil.copy2(callgraph_json, job_dir / "FIRM.callgraph.json")
                    dot = Path(str(callgraph_json).replace(".json", ".dot"))
                    if dot.is_file():
                        shutil.copy2(dot, job_dir / "FIRM.callgraph.dot")
            except OSError as e:
                notes.append(f"phase2ArtifactCopy={e}")
            _update(
                job,
                decompilePath=str(out_c),
                decompileSaved=True,
                functionsPath=str(functions_json) if functions_json.is_file() else None,
                callgraphPath=str(callgraph_json) if callgraph_json.is_file() else None,
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
    if container_meta is not None:
        result["firmwareContainerAnalysis"] = container_meta
        result["firmwareArchitectureConfidence"] = architecture_confidence
        for lim in container_meta.get("analysisLimitations") or []:
            result.setdefault("analysisLimitations", []).append(lim)
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

    _update(job, progressPercent=85, message="Cortex-M IVT / Vektortabelle…")
    ivt_info = ivt_analyze(stored)
    result = merge_ivt_into_result(result, ivt_info)

    _update(job, progressPercent=86, message="Unicorn-Emulation (IVT+Speed-Fenster)…")
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

    _update(job, progressPercent=87, message="Limit-Slice / Board-Pinout…")
    slice_info = limit_slice_analyze(
        stored,
        models=models,
        controller_type=ctype,
        display_name=display,
        filename=job.get("originalFileName") or safe_name,
        decompiled_text=decompiled_text,
        limit_c_text=limit_c_text,
    )
    result = merge_limit_slice(result, slice_info)

    _update(job, progressPercent=88, message="Input-Probe (Unicorn Dual-Hebel)…")
    probe_info = input_probe_analyze(
        stored,
        models=models,
        controller_type=ctype,
        display_name=display,
        filename=job.get("originalFileName") or safe_name,
    )
    result = merge_input_probe(result, probe_info)

    _update(job, progressPercent=89, message="Stock-Diff gegen Referenzbibliothek…")
    region_hints = _stock_region_hints(result)
    name_blob = f"{job.get('originalFileName') or ''} {display or ''}".lower()
    if any(k in name_blob for k in ("panic", "softunlock", "cfw", "unlock")):
        region_hints.append({"kind": "panic", "label": f"filename:{job.get('originalFileName') or display}"})
    stock = compare_to_stock(
        plaintext,
        models=models,
        controller_type=ctype,
        region_hints=region_hints,
        strict_model_match=True,
    )
    result["stockDiff"] = stock
    result.setdefault("notes", []).append(f"stockDiff={stock.get('outcome')}: {stock.get('note')}")
    if stock.get("limitRegionAffected"):
        result.setdefault("notes", []).append("stockDiff=limitRegionAffected")
    if stock.get("panicRegionAffected"):
        result.setdefault("notes", []).append("stockDiff=panicRegionAffected")

    # Phase-2: structured function analysis + optional functionDiff vs stock export.
    # Best-effort: never abort the whole job if function/callgraph/diff fails.
    _update(job, progressPercent=90, message="Funktionsanalyse / Callgraph…")
    func_path = Path(job.get("functionsPath") or (job_dir / "FIRM.functions.json"))
    cg_path = Path(job.get("callgraphPath") or (job_dir / "FIRM.callgraph.json"))
    func_full: dict[str, Any] = {"ok": False, "functions": [], "notes": [], "analysisLimitations": []}
    try:
        func_full = load_function_analysis(func_path if func_path.is_file() else None)
        cg_full = load_call_graph(cg_path if cg_path.is_file() else None)
        result["functionAnalysis"] = summarize_functions_for_poll(func_full)
        result["callGraph"] = summarize_call_graph_for_poll(cg_full)
        if isinstance(result["callGraph"].get("callGraphQuality"), dict):
            result["callGraphQuality"] = result["callGraph"]["callGraphQuality"]
        # Phase 2.2G/H: analysis profile + address layout (always expose intended profile)
        if isinstance(func_full.get("analysisProfile"), dict):
            result["analysisProfile"] = func_full["analysisProfile"]
            result["analysisProfileHash"] = func_full["analysisProfile"].get("analysisProfileHash")
        elif not result.get("analysisProfile"):
            stub = summarize_profile_for_poll(
                build_analysis_profile(
                    processor=GHIDRA_PROCESSOR,
                    loader_base=GHIDRA_BASE_ADDR,
                    seed_ivt=True,
                )
            )
            stub["ghidraExecuted"] = False
            stub["note"] = "Profile declared without Ghidra execution in this job"
            result["analysisProfile"] = stub
            result["analysisProfileHash"] = stub.get("analysisProfileHash")
        result["ghidraAddressLayout"] = {
            "requestedLoaderBase": func_full.get("requestedLoaderBase"),
            "actualImageBase": func_full.get("actualImageBase") or func_full.get("imageBase"),
            "memoryBlockStart": func_full.get("memoryBlockStart"),
            "resetHandlerAddress": func_full.get("resetHandlerAddress"),
            "firmwareFileOffset": func_full.get("firmwareFileOffset"),
            "note": (
                "BinaryLoader may map at requestedLoaderBase while Ghidra ImageBase stays 0; "
                "prefer memoryBlockStart / function entry addresses for layout."
            ),
        }
        notes.extend(func_full.get("notes") or [])
        notes.extend(cg_full.get("notes") or [])

        ref_func = _load_stock_function_analysis(stock)
        func_diff_full = compare_function_analyses(func_full, ref_func)
        poll_diff = summarize_diff_for_poll(func_diff_full)
        catalog_meta = (ref_func or {}).get("catalogMeta") if isinstance(ref_func, dict) else None
        if isinstance(catalog_meta, dict):
            poll_diff["referenceCatalog"] = {
                "referenceId": catalog_meta.get("referenceId"),
                "firmwareSHA256": catalog_meta.get("firmwareSHA256"),
                "analyzerCompat": catalog_meta.get("analyzerCompat"),
                "functionCount": catalog_meta.get("functionCount"),
                "analyzedAt": catalog_meta.get("analyzedAt"),
                "analysisQuality": catalog_meta.get("analysisQuality"),
                "referenceTrust": catalog_meta.get("referenceTrust"),
                "processor": catalog_meta.get("processor"),
            }
            poll_diff.setdefault("notes", []).append("functionDiff=referenceCatalog")
        elif stock.get("outcome") in {"identical", "different"}:
            poll_diff.setdefault("analysisLimitations", []).append(
                "Kein kompatibler Referenz-Funktionskatalog — FunctionDiff eingeschränkt/NICHT_VERGLEICHBAR."
            )
        result["functionDiff"] = poll_diff
        # Compact matching block at top-level for newer clients (also nested in functionDiff).
        if isinstance(poll_diff.get("functionMatching"), dict):
            result["functionMatching"] = poll_diff["functionMatching"]
        notes.extend(func_diff_full.get("notes") or [])

        # Phase 2.2C/F: Input Behavior + State Machine (static + optional runtime suite).
        input_full = analyze_input_behavior(func_full, call_graph=cg_full)
        try:
            from fsm_runtime import merge_runtime_into_state_machines, run_fsm_runtime_suite

            # Controlled synthetic suite only — never real scooter firmware.
            runtime_suite = run_fsm_runtime_suite()
            sm = merge_runtime_into_state_machines(
                input_full.get("stateMachineAnalysis"), runtime_suite
            )
            if sm:
                input_full["stateMachineAnalysis"] = sm
            result["runtimeStateMachineValidation"] = {
                "ok": runtime_suite.get("ok"),
                "dynamicRuntimeVerified": runtime_suite.get("dynamicRuntimeVerified"),
                "runtimeTransitionsObserved": runtime_suite.get("runtimeTransitionsObserved"),
                "programCount": runtime_suite.get("programCount"),
                "evidenceTier": runtime_suite.get("evidenceTier"),
                "threeStateReproducible": runtime_suite.get("threeStateReproducible"),
                "sampleResults": list(runtime_suite.get("results") or [])[:6],
                "analysisLimitations": runtime_suite.get("analysisLimitations"),
                "notes": runtime_suite.get("notes"),
            }
            result["runtimeValidationDetails"] = {
                "tool": runtime_suite.get("tool"),
                "threeStateReproducible": runtime_suite.get("threeStateReproducible"),
                "programCount": runtime_suite.get("programCount"),
                "evidenceTier": runtime_suite.get("evidenceTier"),
                "validationKind": "unicorn_controlled",
                "vehicleTest": False,
                "notes": runtime_suite.get("notes"),
            }
            notes.extend(runtime_suite.get("notes") or [])
        except Exception as rt_e:
            notes.append(f"phase22fRuntime={type(rt_e).__name__}")
            result["runtimeStateMachineValidation"] = {
                "ok": False,
                "dynamicRuntimeVerified": False,
                "notes": [f"runtime suite skipped: {type(rt_e).__name__}"],
            }
        result["inputBehaviorAnalysis"] = summarize_input_behavior_for_poll(input_full)
        result["stateMachineAnalysis"] = (
            result["inputBehaviorAnalysis"].get("stateMachineAnalysis") or {}
        )
        notes.extend(input_full.get("notes") or [])

        ref_input = None
        if isinstance(ref_func, dict) and ref_func.get("ok"):
            ref_input = analyze_input_behavior(ref_func)
        input_diff_full = diff_input_behavior(
            input_full,
            ref_input,
            subject_fns=list(func_full.get("functions") or []),
            reference_fns=list((ref_func or {}).get("functions") or []) if ref_func else [],
        )
        result["inputBehaviorDiff"] = summarize_input_diff_for_poll(input_diff_full)
        notes.extend(input_diff_full.get("notes") or [])

        # Phase 2.3 / 2.3.1: Activation Forensics (hidden input mechanisms — static only).
        activation_full = None
        dataflow_full = None
        try:
            from analysis_profile import profiles_compatible

            subj_sha = None
            if isinstance(result.get("plaintextSHA256"), str):
                subj_sha = result.get("plaintextSHA256")
            elif isinstance(result.get("sha256"), str):
                subj_sha = result.get("sha256")
            ref_sha = stock.get("referenceSHA256") if isinstance(stock, dict) else None
            ref_trust = stock.get("referenceTrust") if isinstance(stock, dict) else None
            if isinstance(catalog_meta, dict) and catalog_meta.get("referenceTrust"):
                ref_trust = catalog_meta.get("referenceTrust")
            profile_obj = result.get("analysisProfile") if isinstance(result.get("analysisProfile"), dict) else None
            compat = None
            if isinstance(catalog_meta, dict) and catalog_meta.get("analysisProfile"):
                try:
                    compat = profiles_compatible(profile_obj, catalog_meta.get("analysisProfile"))
                except Exception:
                    compat = None
            # Phase 2.3.1: optional compact dataflow export (never dump into poll).
            df_export = None
            try:
                from semantic_dataflow import analyze_semantic_dataflow, load_dataflow_export

                df_path = None
                for cand in (
                    job_dir / "FIRM.dataflow.json",
                    Path(str(func_path)).with_name(
                        Path(str(func_path)).name.replace(".functions.json", ".dataflow.json")
                    )
                    if func_path
                    else None,
                ):
                    if cand is not None and Path(cand).is_file():
                        df_path = Path(cand)
                        break
                df_export = load_dataflow_export(df_path) if df_path else None
                dataflow_full = analyze_semantic_dataflow(
                    func_full, dataflow_export=df_export, call_graph=cg_full
                )
            except Exception as df_e:
                notes.append(f"phase231Dataflow={type(df_e).__name__}")
                dataflow_full = None
                df_export = None

            activation_full = run_activation_forensics(
                func_full,
                call_graph=cg_full,
                function_diff=func_diff_full,
                input_behavior=input_full,
                input_behavior_diff=input_diff_full,
                analysis_profile=profile_obj,
                profile_compat=compat,
                subject_sha256=subj_sha,
                reference_sha256=ref_sha,
                reference_trust=ref_trust,
                runtime_validation=result.get("runtimeStateMachineValidation"),
                dataflow_export=df_export,
            )
            result["activationForensics"] = summarize_activation_forensics_for_poll(activation_full)
            result["undocumentedLogic"] = (result["activationForensics"] or {}).get("undocumentedLogic")
            result["inputHandlerFindings"] = {
                "count": (result["activationForensics"].get("summary") or {}).get("inputHandlerCount"),
                "sample": result["activationForensics"].get("sampleInputHandlers"),
                "categoryCounts": result["activationForensics"].get("categoryCounts"),
            }
            result["conditionalLogicFindings"] = (result["activationForensics"] or {}).get(
                "conditionalLogicFindings"
            )
            result["activationEvidenceGraph"] = (result["activationForensics"] or {}).get(
                "activationEvidenceGraph"
            )
            # Optional Phase 2.3.1 poll fields (compact).
            result["semanticDataFlow"] = (result["activationForensics"] or {}).get("semanticDataFlow")
            result["inputDetectionQuality"] = (result["activationForensics"] or {}).get(
                "inputDetectionQuality"
            )
            result["conditionalLogicQuality"] = (result["activationForensics"] or {}).get(
                "conditionalLogicQuality"
            )
            result["activationEvidenceDistribution"] = (result["activationForensics"] or {}).get(
                "activationEvidenceDistribution"
            )
            result["evidenceGraphQuality"] = (result["activationForensics"] or {}).get(
                "evidenceGraphQuality"
            )
            result["resultLimits"] = (result["activationForensics"] or {}).get("resultLimits")
            result["analysisLimitations"] = list(
                dict.fromkeys(
                    list(result.get("analysisLimitations") or [])
                    + list((result["activationForensics"] or {}).get("analysisLimitations") or [])
                )
            )
            notes.extend(activation_full.get("notes") or [])
        except Exception as act_e:
            notes.append(f"phase23Activation={type(act_e).__name__}")
            result["activationForensics"] = {
                "ok": False,
                "phase": "2.3.1",
                "notes": [f"activation forensics skipped: {type(act_e).__name__}"],
            }
            activation_full = None

        # Persist full artifacts for authenticated download endpoints.
        try:
            ib_path = job_dir / "FIRM.input_behavior.json"
            ib_path.write_text(json.dumps(input_full, ensure_ascii=False), encoding="utf-8")
            fd_path = job_dir / "FIRM.function_diff.json"
            fd_path.write_text(json.dumps(func_diff_full, ensure_ascii=False), encoding="utf-8")
            ibd_path = job_dir / "FIRM.input_behavior_diff.json"
            ibd_path.write_text(json.dumps(input_diff_full, ensure_ascii=False), encoding="utf-8")
            if activation_full is not None:
                af_path = job_dir / "FIRM.activation_forensics.json"
                af_path.write_text(
                    json.dumps(activation_full, ensure_ascii=False), encoding="utf-8"
                )
            if dataflow_full is not None:
                sdf_path = job_dir / "FIRM.semantic_dataflow.json"
                sdf_path.write_text(
                    json.dumps(dataflow_full, ensure_ascii=False), encoding="utf-8"
                )
        except Exception as art_e:
            notes.append(f"phase22cArtifactWrite={type(art_e).__name__}")

        # Reference metadata for UI (never auto-elevate trust).
        result["referenceMetadata"] = _reference_metadata_from_stock(stock)
        if isinstance(catalog_meta, dict):
            result["referenceMetadata"]["functionCatalog"] = {
                "present": True,
                "analyzerCompat": catalog_meta.get("analyzerCompat"),
                "functionCount": catalog_meta.get("functionCount"),
                "analyzedAt": catalog_meta.get("analyzedAt"),
                "completenessStatus": catalog_meta.get("completenessStatus")
                or catalog_meta.get("analysisCompleteness"),
                "truncated": bool(catalog_meta.get("truncated")),
                "ghidraVersion": catalog_meta.get("ghidraVersion"),
                "processor": catalog_meta.get("processor"),
                "baseAddr": catalog_meta.get("baseAddr"),
                "referenceTrust": catalog_meta.get("referenceTrust"),
            }
        else:
            result["referenceMetadata"]["functionCatalog"] = {"present": False}

        # Phase 2.2E: structured completeness / coverage (optional, poll-safe).
        try:
            from analysis_completeness import assess_analysis_completeness

            completeness = assess_analysis_completeness(
                function_analysis=func_full,
                call_graph=cg_full,
                catalog_meta=catalog_meta if isinstance(catalog_meta, dict) else None,
                matching=func_diff_full.get("functionMatching")
                if isinstance(func_diff_full, dict)
                else None,
            )
            result["analysisCompleteness"] = completeness.get("analysisCompleteness")
            result["firmwareAnalysisCoverage"] = completeness.get("firmwareAnalysisCoverage")
            result["referenceCatalogCoverage"] = completeness.get("referenceCatalogCoverage")
            result["functionMatchingCoverage"] = completeness.get("functionMatchingCoverage")
            sm_full = input_full.get("stateMachineAnalysis") or {}
            result["stateMachineValidation"] = sm_full.get("stateMachineValidation")
            notes.extend(completeness.get("notes") or [])
        except Exception as cov_e:
            notes.append(f"phase22eCoverage={type(cov_e).__name__}")

        limitations = []
        limitations.extend(result.get("functionAnalysis", {}).get("analysisLimitations") or [])
        limitations.extend(result.get("functionDiff", {}).get("analysisLimitations") or [])
        limitations.extend(result.get("callGraph", {}).get("analysisLimitations") or [])
        limitations.extend(result.get("inputBehaviorAnalysis", {}).get("analysisLimitations") or [])
        limitations.extend(result.get("inputBehaviorDiff", {}).get("analysisLimitations") or [])
        limitations.extend(result.get("activationForensics", {}).get("analysisLimitations") or [])
        if stock.get("outcome") == "noReference":
            limitations.append("Keine eindeutig passende Referenzfirmware für Funktionsvergleich.")
        # Deduplicate while preserving order
        seen_lim: set[str] = set()
        uniq_lim: list[str] = []
        for line in limitations:
            if line and line not in seen_lim:
                seen_lim.add(line)
                uniq_lim.append(line)
        result["analysisLimitations"] = uniq_lim
        job["phase2"] = {
            "functionsPath": str(func_path) if func_path.is_file() else None,
            "callgraphPath": str(cg_path) if cg_path.is_file() else None,
            "functionDiffSummary": result["functionDiff"].get("summary"),
            "functionDiffPath": str(job_dir / "FIRM.function_diff.json"),
            "inputBehaviorPath": str(job_dir / "FIRM.input_behavior.json"),
            "inputBehaviorDiffPath": str(job_dir / "FIRM.input_behavior_diff.json"),
            "inputBehaviorSummary": result["inputBehaviorAnalysis"].get("summary"),
            "activationForensicsPath": str(job_dir / "FIRM.activation_forensics.json"),
            "activationForensicsSummary": (result.get("activationForensics") or {}).get("summary"),
            "semanticDataflowPath": str(job_dir / "FIRM.semantic_dataflow.json"),
            "analysisCompleteness": result.get("analysisCompleteness"),
        }
    except Exception as e:
        notes.append(f"phase2=error:{type(e).__name__}:{e}")
        result.setdefault("analysisLimitations", []).append(
            "Phase-2-Funktionsanalyse fehlgeschlagen — Phase-1-Ergebnis bleibt gültig."
        )
        result.setdefault("functionAnalysis", {"ok": False, "functionCount": 0, "notes": [f"phase2={e}"]})
        result.setdefault("functionDiff", {"ok": False, "summary": {}, "notes": [f"phase2={e}"]})
        result.setdefault("callGraph", {"ok": False, "edgeCount": 0, "notes": [f"phase2={e}"]})
        result.setdefault("referenceMetadata", _reference_metadata_from_stock(stock))
    for n in notes:
        if n and n not in (result.get("notes") or []):
            result.setdefault("notes", []).append(n)

    if meta.allowLLM and llm_configured():
        _update(job, state="llmEnrichment", progressPercent=92, message="KI-Anreicherung (schema)…")
        result = enrich_result(
            result,
            decompiled_text=decompiled_text,
            limit_c_text=limit_c_text,
        )
        result = verify_enrichment(
            result,
            function_analysis=func_full,
            plaintext_size=len(plaintext),
        )
    elif meta.allowLLM:
        # enrich_result also annotates bad key kinds (e.g. sk-ant-oat OAuth)
        result = enrich_result(
            result,
            decompiled_text=decompiled_text,
            limit_c_text=limit_c_text,
        )
        if not any(str(n).startswith("llm=") for n in (result.get("notes") or [])):
            result.setdefault("notes", []).append("llm=skipped (LLM_API_KEY not set)")

    from combo_policy import sanitize_result_combos

    result = sanitize_result_combos(result)
    if not (result.get("comboSummaries") or []):
        result.setdefault("notes", []).append(
            "comboPolicy=keine validierte Tastenfolge (nur Live-/Belegt-/Validiert:-Zeilen erlaubt)"
        )

    parts = [f"{decrypt_label} ({len(plaintext)} Byte) → {stored}"]
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


def _auth_security_warnings() -> list[str]:
    """Surface insecure legacy auth flags (fail-open for ops visibility, fail-closed for ownership)."""
    warnings: list[str] = []
    if api_token_grants_admin():
        warnings.append(
            "INSECURE: API_TOKEN_GRANTS_ADMIN=1 — shared API_TOKEN grants admin. "
            "Set API_TOKEN_GRANTS_ADMIN=0 and use ADMIN_API_TOKEN / JWT role=admin."
        )
    if trust_api_token_client_id():
        warnings.append(
            "INSECURE: TRUST_API_TOKEN_CLIENT_ID=1 — Client-Id can own/access jobs under "
            "shared API_TOKEN (spoofable). Set TRUST_API_TOKEN_CLIENT_ID=0; prefer Bearer JWT."
        )
    if API_TOKEN and not ADMIN_API_TOKEN and api_token_grants_admin():
        warnings.append(
            "INSECURE: shared API_TOKEN is the only admin credential (no ADMIN_API_TOKEN)."
        )
    if not JWT_SECRET:
        warnings.append(
            "JWT_SECRET unset — user-owned firmware jobs via Bearer JWT are unavailable."
        )
    return warnings


@APP.get("/health")
def health() -> dict[str, Any]:
    auth_warnings = _auth_security_warnings()
    return {
        "ok": True,
        "service": "scootercheck-fw",
        "decryptConfigured": bool(DECRYPT_CMD),
        "ghidraConfigured": ghidra_configured(),
        "ghidraEnabled": ENABLE_GHIDRA,
        "jwtConfigured": bool(JWT_SECRET),
        "apiTokenConfigured": bool(API_TOKEN),
        "adminApiTokenConfigured": bool(ADMIN_API_TOKEN),
        "apiTokenGrantsAdmin": api_token_grants_admin(),
        "trustApiTokenClientId": trust_api_token_client_id(),
        "authSecurityOk": len(auth_warnings) == 0,
        "authSecurityWarnings": auth_warnings,
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
    try:
        validate_upload_size(raw, max_bytes=MAX_UPLOAD_BYTES)
    except ZipSafetyError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    # Extra ZIP safety for .zip uploads (path traversal, zip bombs, symlinks).
    if safe_upload_name.lower().endswith(".zip") or (archive.filename or "").lower().endswith(".zip"):
        try:
            inspect_zip(raw)
        except ZipSafetyError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
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
        "createdAt": _utc_now().isoformat(),
        "encSHA256": None,
        "plaintextSHA256": None,
        "plaintextPath": None,
        "plaintextSaved": False,
        "decompilePath": None,
        "decompileSaved": False,
    }
    job.update(ownership_fields_for_new_job(auth))
    persist_job(job)
    background_tasks.add_task(process_job, job_id)
    return JSONResponse(job_status_payload(job))


@APP.get("/v1/firmware/jobs/{job_id}")
def get_job(job_id: str, auth: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    job = _load_job_authorized(job_id, auth)
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
    source: str = Form("oem"),
    region: str = Form(""),
    notes: str = Form(""),
    confirmOem: str = Form("false"),
    file: UploadFile = File(...),
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    """Upload OEM/serial reference only. confirmOem must be true for source=oem|serial."""
    raw = await file.read()
    if not raw:
        raise HTTPException(status_code=400, detail="empty file")
    if len(raw) > 16 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="stock file too large (max 16 MiB)")
    src = (source or "oem").strip().lower()
    if src in TRUSTED_SOURCES and confirmOem.strip().lower() not in ("1", "true", "yes"):
        raise HTTPException(
            status_code=400,
            detail="confirmOem=true erforderlich für OEM-/Serien-Stock (keine Fall-Uploads).",
        )
    if src == "case":
        raise HTTPException(
            status_code=400,
            detail="source=case ist nicht als Stock-Referenz erlaubt.",
        )
    ref = register_stock_file(
        raw,
        label=label or (file.filename or "stock"),
        model=model or "unknown",
        controller_type=controllerType or "VCU",
        version=version or "",
        filename=file.filename,
        source=src,
        region=region or "",
        notes=notes or "",
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
    source: str = Query("oem"),
    region: str = Query(""),
    notes: str = Query(""),
    confirmOem: bool = Query(False),
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    """Copy a job's decrypted plaintext into the stock library for future BinDiff.

    Requires confirmOem=true. Rejects images with high-confidence CFW YARA hits.
    Only OEM/serial sources become trusted compare targets.
    """
    if not confirmOem:
        raise HTTPException(
            status_code=400,
            detail="confirmOem=true erforderlich — nur echte OEM-/Serien-Klartexte promoten.",
        )
    src = (source or "oem").strip().lower()
    if src not in TRUSTED_SOURCES:
        raise HTTPException(
            status_code=400,
            detail="source muss oem oder serial sein (keine Fall-Uploads).",
        )
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    path = Path(job.get("plaintextPath") or (Path(job["dir"]) / "FIRM.dec.bin"))
    if not path.is_file():
        raise HTTPException(status_code=404, detail="plaintext not available")

    result = job.get("result") or {}
    yara_hits = result.get("yaraMatches") or []
    blocked = [
        m
        for m in yara_hits
        if str(m.get("confidence") or "").lower() == "high"
        and str(m.get("family") or m.get("rule") or "").lower()
        not in {""}  # any high-confidence rule blocks
    ]
    # Explicit CFW families always block even if confidence medium
    cfw_families = {"panicsystem", "scooterhacking", "esc-cfw", "soft-unlock"}
    for m in yara_hits:
        fam = str(m.get("family") or "").lower()
        rule = str(m.get("rule") or "")
        if fam in cfw_families or "CFW_" in rule or "Panic" in rule or "ScooterHacking" in rule:
            if m not in blocked:
                blocked.append(m)
    if blocked:
        names = ", ".join(sorted({str(m.get("rule")) for m in blocked[:6]}))
        raise HTTPException(
            status_code=409,
            detail=f"Promote abgelehnt — CFW-/YARA-Treffer: {names}. Nur OEM ohne CFW-Marker.",
        )

    raw = path.read_bytes()
    ref = register_stock_file(
        raw,
        label=label or (job.get("originalFileName") or f"stock-{job_id[:8]}"),
        model=model or ((result.get("models") or ["unknown"])[0]),
        controller_type=controllerType or (result.get("controllerType") or "VCU"),
        version=version or "",
        filename=f"{job_id[:8]}.dec.bin",
        source=src,
        region=region or "",
        notes=notes or f"promoted from job {job_id}",
    )
    return JSONResponse({"ok": True, "ref": ref})


@APP.get("/v1/firmware/jobs/{job_id}/plaintext")
def download_plaintext(job_id: str, auth: dict[str, Any] = Depends(require_auth)):
    job = _load_job_authorized(job_id, auth)
    path = Path(job.get("plaintextPath") or (Path(job["dir"]) / "FIRM.dec.bin"))
    if not path.exists():
        raise HTTPException(status_code=404, detail="plaintext not available")
    return FileResponse(path, filename=path.name, media_type="application/octet-stream")


@APP.get("/v1/firmware/jobs/{job_id}/decompile")
def download_decompile(
    job_id: str,
    preview_chars: int = 0,
    auth: dict[str, Any] = Depends(require_auth),
):
    job = _load_job_authorized(job_id, auth)
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


@APP.get("/v1/firmware/jobs/{job_id}/functions")
def download_functions(job_id: str, auth: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    """Full functionAnalysis artifact (not embedded in poll payload)."""
    job = _load_job_authorized(job_id, auth)
    path = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("functionsPath"),
        job.get("functionsPath"),
        fallback_name="FIRM.functions.json",
    )
    data = load_function_analysis(path)
    if not data.get("ok"):
        raise HTTPException(status_code=404, detail="function analysis not available")
    return JSONResponse(data)


@APP.get("/v1/firmware/jobs/{job_id}/callgraph")
def download_callgraph(job_id: str, auth: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    job = _load_job_authorized(job_id, auth)
    path = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("callgraphPath"),
        job.get("callgraphPath"),
        fallback_name="FIRM.callgraph.json",
    )
    data = load_call_graph(path)
    if not data.get("ok"):
        raise HTTPException(status_code=404, detail="call graph not available")
    return JSONResponse(data)


@APP.get("/v1/firmware/jobs/{job_id}/function-diff")
def download_function_diff(job_id: str, auth: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    """Recompute or return full functionDiff (pairs may be large)."""
    job = _load_job_authorized(job_id, auth)
    cached = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("functionDiffPath"),
        fallback_name="FIRM.function_diff.json",
    )
    if cached and cached.is_file():
        try:
            return JSONResponse(json.loads(cached.read_text(encoding="utf-8")))
        except Exception:
            pass
    result = job.get("result") or {}
    func_path = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("functionsPath"),
        job.get("functionsPath"),
        fallback_name="FIRM.functions.json",
    )
    func_full = load_function_analysis(func_path)
    stock = result.get("stockDiff") if isinstance(result, dict) else None
    ref_func = _load_stock_function_analysis(stock if isinstance(stock, dict) else None)
    full = compare_function_analyses(func_full, ref_func)
    return JSONResponse(full)


@APP.get("/v1/firmware/jobs/{job_id}/input-behavior")
def download_input_behavior(job_id: str, auth: dict[str, Any] = Depends(require_auth)) -> JSONResponse:
    """Full inputBehaviorAnalysis artifact (not fully embedded in poll)."""
    job = _load_job_authorized(job_id, auth)
    cached = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("inputBehaviorPath"),
        fallback_name="FIRM.input_behavior.json",
    )
    if cached and cached.is_file():
        try:
            return JSONResponse(json.loads(cached.read_text(encoding="utf-8")))
        except Exception:
            pass
    func_path = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("functionsPath"),
        job.get("functionsPath"),
        fallback_name="FIRM.functions.json",
    )
    func_full = load_function_analysis(func_path)
    cg_path = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("callgraphPath"),
        job.get("callgraphPath"),
        fallback_name="FIRM.callgraph.json",
    )
    cg_full = load_call_graph(cg_path)
    return JSONResponse(analyze_input_behavior(func_full, call_graph=cg_full))


@APP.get("/v1/firmware/jobs/{job_id}/input-behavior-diff")
def download_input_behavior_diff(
    job_id: str, auth: dict[str, Any] = Depends(require_auth)
) -> JSONResponse:
    job = _load_job_authorized(job_id, auth)
    cached = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("inputBehaviorDiffPath"),
        fallback_name="FIRM.input_behavior_diff.json",
    )
    if cached and cached.is_file():
        try:
            return JSONResponse(json.loads(cached.read_text(encoding="utf-8")))
        except Exception:
            pass
    raise HTTPException(status_code=404, detail="input behavior diff not available")


@APP.get("/v1/firmware/jobs/{job_id}/activation-forensics")
def download_activation_forensics(
    job_id: str,
    auth: dict[str, Any] = Depends(require_auth),
    offset: int = 0,
    limit: int | None = None,
) -> JSONResponse:
    """Full Phase 2.3 activation-forensics artifact (JWT/job ownership enforced).

    Optional query ``offset`` / ``limit`` slice ``inputHandlerFindings`` and
    conditional ``findings`` in the JSON response; the on-disk artifact is unchanged.
    """
    job = _load_job_authorized(job_id, auth)
    cached = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("activationForensicsPath"),
        fallback_name="FIRM.activation_forensics.json",
    )
    if cached and cached.is_file():
        try:
            payload = json.loads(cached.read_text(encoding="utf-8"))
            if limit is not None:
                page_lim = max(1, int(limit))
                handlers, h_meta = slice_findings_for_page(
                    payload.get("inputHandlerFindings"), offset=offset, limit=page_lim
                )
                cond = payload.get("conditionalLogicFindings") or {}
                cond_findings, c_meta = slice_findings_for_page(
                    cond.get("findings"), offset=offset, limit=page_lim
                )
                payload = {**payload}
                payload["inputHandlerFindings"] = handlers
                cond_out = dict(cond)
                cond_out["findings"] = cond_findings
                payload["conditionalLogicFindings"] = cond_out
                payload["responsePagination"] = {
                    "inputHandlers": h_meta,
                    "conditionalLogic": c_meta,
                    "note": "Disk artifact retains full lists; pagination applies to this response only.",
                }
            return JSONResponse(payload)
        except Exception:
            pass
    raise HTTPException(status_code=404, detail="activation forensics not available")


@APP.get("/v1/firmware/jobs/{job_id}/semantic-dataflow")
def download_semantic_dataflow(
    job_id: str, auth: dict[str, Any] = Depends(require_auth)
) -> JSONResponse:
    """Full Phase 2.3.1 semantic data-flow artifact (JWT/job ownership enforced)."""
    job = _load_job_authorized(job_id, auth)
    cached = _job_artifact_path(
        job,
        (job.get("phase2") or {}).get("semanticDataflowPath"),
        fallback_name="FIRM.semantic_dataflow.json",
    )
    if cached and cached.is_file():
        try:
            return JSONResponse(json.loads(cached.read_text(encoding="utf-8")))
        except Exception:
            pass
    raise HTTPException(status_code=404, detail="semantic dataflow not available")


@APP.get("/v1/firmware/admin/reference-catalogs")
def admin_list_reference_catalogs(_: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    cats = list_catalogs()
    return JSONResponse({"count": len(cats), "catalogs": cats})


@APP.get("/v1/firmware/admin/reference-inventory")
def admin_reference_inventory(_: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    """Read-only inventory + analyzability of stock references (Phase 2.2E)."""
    from reference_inventory import inventory_references

    return JSONResponse(inventory_references(include_file_probe=True))


@APP.post("/v1/firmware/admin/reference-catalogs/batch-test")
def admin_reference_catalog_batch_test(
    limit: int = 3,
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    """Isolated catalog batch into STOCK_CATALOG_BATCH_DIR — never productive catalogs."""
    from catalog_batch import run_catalog_batch

    with _HEAVY_ANALYSIS_LOCK:
        summary = run_catalog_batch(limit=max(1, min(int(limit or 3), 5)))
    return JSONResponse(summary)


@APP.post("/v1/firmware/admin/reference-catalogs/build")
def admin_build_reference_catalogs(
    limit: int | None = Query(default=None),
    force: bool = Query(default=False),
    only_sha: str | None = Query(default=None),
    _: dict[str, Any] = Depends(require_admin),
) -> JSONResponse:
    """Build Ghidra function catalogs for stock refs. Does not elevate trust. Heavy."""
    with _HEAVY_ANALYSIS_LOCK:
        out = build_catalogs(limit=limit, force=force, only_sha=only_sha)
    return JSONResponse(out)


@APP.delete("/v1/firmware/admin/jobs/{job_id}")
def admin_delete_job(job_id: str, _: dict[str, Any] = Depends(require_admin)) -> JSONResponse:
    job = load_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    delete_job_artifacts(job)
    return JSONResponse({"message": "deleted", "jobId": job_id})
