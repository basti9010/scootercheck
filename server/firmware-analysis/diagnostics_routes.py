"""Cycle 11 diagnostics route handlers (draft — NOT wired into APP).

# wire in PM — after Agents B/C land tea/ghidra probe modules, in app.py:

    from diagnostics_routes import create_diagnostics_router
    APP.include_router(create_diagnostics_router(require_auth=require_auth))

Do NOT merge this include until auth gate review is done. Leaving unwired
avoids merge fights on app.py across parallel Cycle 11 agents.

Endpoints:
  GET  /v1/diagnostics/status
  POST /v1/diagnostics/selftest
  GET  /v1/diagnostics/selftest/{job_id}

Auth gate (stricter than app.require_admin / job_auth.is_admin):
  - Refuse if authMode == open
  - Refuse if authMode == shared_token_admin (API_TOKEN_GRANTS_ADMIN=1 CRITICAL)
  - Accept ONLY JWT role=admin OR X-ScooterCheck-Token == ADMIN_API_TOKEN
  - Never grant via apiTokenGrantsAdmin / shared API_TOKEN alone

Rate limit / single-flight (ops notes — enforced lightly in-process):
  - Selftest: at most ONE in-flight job process-wide (_SELFTEST_LOCK + _active_job_id).
  - Suggested nginx/edge: limit_req on /v1/diagnostics/  (e.g. 10 r/m per admin IP).
  - Status GET is cheap; still admin-gated — do not expose on public unauth paths.
  - Do not overlap selftest with production Ghidra jobs if host RAM ≤ 4 GB
    (shares _HEAVY_ANALYSIS_LOCK semantics once B/C wire real probes).
"""
from __future__ import annotations

import threading
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse

from diagnostics_models import SelftestCreateResponse, SelftestJobStatus, SelftestRequest
from diagnostics_status import (
    assemble_diagnostics_status,
    diagnostics_auth_allowed,
    status_as_dict,
)
from job_auth import api_token_grants_admin

# --- in-memory selftest job table (draft; PM may later persist under WORK_DIR) ---
_SELFTEST_JOBS: dict[str, dict[str, Any]] = {}
_SELFTEST_LOCK = threading.Lock()
_ACTIVE_SELFTEST_ID: str | None = None

# Soft rate hint: reject new selftest if last create was < N seconds ago (same process).
_MIN_SELFTEST_INTERVAL_SEC = 30.0
_LAST_SELFTEST_CREATE_MONO: float = 0.0


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def enforce_diagnostics_admin(auth: dict[str, Any]) -> dict[str, Any]:
    """True-admin only. Never accept privilege via apiTokenGrantsAdmin.

    Call after require_auth (not require_admin — that still allows shared-token
    admin when API_TOKEN_GRANTS_ADMIN=1).
    """
    allowed, detail = diagnostics_auth_allowed()
    if not allowed:
        raise HTTPException(status_code=403, detail=detail)

    # Defense in depth: even if posture flips mid-request, never trust grants flag.
    if api_token_grants_admin() and not (
        auth.get("role") == "admin" or auth.get("adminToken") is True
    ):
        raise HTTPException(
            status_code=403,
            detail="diagnostics refused: shared-token-admin CRITICAL path",
        )

    if auth.get("auth") == "open":
        raise HTTPException(status_code=403, detail="diagnostics refused: auth=open")

    # JWT role=admin
    if auth.get("auth") == "jwt" and auth.get("role") == "admin":
        return auth

    # Dedicated ADMIN_API_TOKEN only (require_auth sets adminToken=True)
    if auth.get("auth") == "api_token" and auth.get("adminToken") is True:
        return auth

    raise HTTPException(
        status_code=403,
        detail="admin only (JWT role=admin or ADMIN_API_TOKEN) — shared API_TOKEN denied",
    )


def _run_lightweight_selftest(job: dict[str, Any], body: SelftestRequest) -> None:
    """Existence-level selftest. TEA/Ghidra VERIFIED probes belong to Agents B/C.

    Optional hooks (lazy import) when diagnostics_tea / diagnostics_ghidra exist:
      try: from diagnostics_tea import run_tea_selftest
      try: from diagnostics_ghidra import run_ghidra_selftest
    """
    global _ACTIVE_SELFTEST_ID
    job_id = job["jobId"]
    steps: list[dict[str, Any]] = []
    try:
        job["state"] = "running"
        job["progressPercent"] = 10
        job["message"] = "assembling status probes"
        job["updatedAt"] = _utc_now_iso()

        status = assemble_diagnostics_status()
        steps.append(
            {
                "id": "status_snapshot",
                "grade": "AVAILABLE",
                "ok": True,
                "components": len(status.components),
            }
        )
        job["progressPercent"] = 40

        if body.includeTea:
            # Agent B: replace with diagnostics_tea.run_tea_selftest()
            tea = next((c for c in status.components if c.id == "decrypt"), None)
            try:
                from diagnostics_tea import run_tea_selftest  # type: ignore

                tea_result = run_tea_selftest()
                steps.append({"id": "tea", **dict(tea_result)})
            except ImportError:
                steps.append(
                    {
                        "id": "tea",
                        "grade": tea.grade.value if tea else "UNKNOWN",
                        "ok": tea is not None and tea.grade.value in ("AVAILABLE", "VERIFIED"),
                        "detail": "diagnostics_tea not wired — existence grade only",
                    }
                )
            job["progressPercent"] = 60

        if body.includeGhidra:
            ghidra = next((c for c in status.components if c.id == "ghidra"), None)
            try:
                from diagnostics_ghidra import run_ghidra_selftest  # type: ignore

                g_result = run_ghidra_selftest()
                steps.append({"id": "ghidra", **dict(g_result)})
            except ImportError:
                steps.append(
                    {
                        "id": "ghidra",
                        "grade": ghidra.grade.value if ghidra else "UNKNOWN",
                        "ok": ghidra is not None
                        and ghidra.grade.value in ("AVAILABLE", "VERIFIED"),
                        "detail": "diagnostics_ghidra not wired — existence grade only",
                    }
                )
            job["progressPercent"] = 80

        if body.includeWorkers:
            workers = next((c for c in status.components if c.id == "workers"), None)
            steps.append(
                {
                    "id": "workers",
                    "grade": workers.grade.value if workers else "UNKNOWN",
                    "ok": True,
                    "detail": workers.detail if workers else "",
                }
            )

        job["state"] = "completed"
        job["progressPercent"] = 100
        job["message"] = "selftest completed (existence-level; VERIFIED deferred to B/C)"
        job["result"] = {
            "auth": status.auth.model_dump(mode="json"),
            "steps": steps,
            "notes": status.notes,
        }
        job["updatedAt"] = _utc_now_iso()
    except Exception as exc:
        job["state"] = "failed"
        job["errorCode"] = "SELFTEST_FAILED"
        job["message"] = f"selftest error: {type(exc).__name__}"
        job["updatedAt"] = _utc_now_iso()
        job["result"] = {"steps": steps}
    finally:
        with _SELFTEST_LOCK:
            if _ACTIVE_SELFTEST_ID == job_id:
                _ACTIVE_SELFTEST_ID = None


def create_diagnostics_router(*, require_auth: Callable[..., Any]) -> APIRouter:
    """Build router bound to app.require_auth (injected by PM to avoid cycles)."""

    router = APIRouter(prefix="/v1/diagnostics", tags=["diagnostics"])

    def require_diagnostics_admin(
        auth: dict[str, Any] = Depends(require_auth),
    ) -> dict[str, Any]:
        return enforce_diagnostics_admin(auth)

    @router.get("/status")
    def diagnostics_status(
        _: dict[str, Any] = Depends(require_diagnostics_admin),
    ) -> JSONResponse:
        # Cheap read — still admin-only. Prefer edge rate limit (see module docstring).
        return JSONResponse(status_as_dict())

    @router.post("/selftest")
    def diagnostics_selftest_create(
        body: SelftestRequest | None = None,
        _: dict[str, Any] = Depends(require_diagnostics_admin),
    ) -> JSONResponse:
        """Enqueue lightweight selftest.

        Single-flight: rejects with 429 if another selftest is active.
        Soft interval: rejects with 429 if created < _MIN_SELFTEST_INTERVAL_SEC ago.

        Draft runs inline. PM may wrap with BackgroundTasks.add_task when wiring:
          background_tasks.add_task(_run_lightweight_selftest, job, body)
        """
        import time

        global _ACTIVE_SELFTEST_ID, _LAST_SELFTEST_CREATE_MONO

        body = body or SelftestRequest()
        now = time.monotonic()

        with _SELFTEST_LOCK:
            if _ACTIVE_SELFTEST_ID is not None:
                raise HTTPException(
                    status_code=429,
                    detail="selftest single-flight: another diagnostics selftest is running",
                )
            if (
                _LAST_SELFTEST_CREATE_MONO
                and (now - _LAST_SELFTEST_CREATE_MONO) < _MIN_SELFTEST_INTERVAL_SEC
            ):
                raise HTTPException(
                    status_code=429,
                    detail=(
                        f"selftest rate limit: wait "
                        f"{int(_MIN_SELFTEST_INTERVAL_SEC)}s between creates"
                    ),
                )

            job_id = str(uuid.uuid4())
            now_iso = _utc_now_iso()
            job: dict[str, Any] = {
                "jobId": job_id,
                "state": "queued",
                "progressPercent": 0,
                "message": "queued",
                "errorCode": None,
                "createdAt": now_iso,
                "updatedAt": now_iso,
                "result": None,
            }
            _SELFTEST_JOBS[job_id] = job
            _ACTIVE_SELFTEST_ID = job_id
            _LAST_SELFTEST_CREATE_MONO = now

        # Draft: run inline (no BackgroundTasks import from app — wire in PM).
        _run_lightweight_selftest(job, body)

        return JSONResponse(
            SelftestCreateResponse(
                jobId=job_id,
                state=job["state"],
                message=job.get("message") or "",
            ).model_dump()
        )

    @router.get("/selftest/{job_id}")
    def diagnostics_selftest_get(
        job_id: str,
        _: dict[str, Any] = Depends(require_diagnostics_admin),
    ) -> JSONResponse:
        job = _SELFTEST_JOBS.get(job_id)
        if not job:
            # Opaque 404 — no existence oracle beyond admin auth.
            raise HTTPException(status_code=404, detail="not found")
        payload = {k: job[k] for k in SelftestJobStatus.model_fields}
        return JSONResponse(SelftestJobStatus(**payload).model_dump())

    return router


# Convenience exports for unit tests / PM without mounting the router.
__all__ = [
    "create_diagnostics_router",
    "enforce_diagnostics_admin",
    "_run_lightweight_selftest",
    "_SELFTEST_JOBS",
]
