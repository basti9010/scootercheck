"""ScooterCheck AI Bridge HTTP API v2 — tasks, auth, dashboard backend, health."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from ai_bridge.cursor_client import (
    CURSOR_API_LIVE_VERIFIED,
    live_api_available,
)
from ai_bridge.github_status import fetch_open_pulls, fetch_workflow_runs
from ai_bridge.models import TaskCreate, TaskPriority, TaskSource
from ai_bridge.orchestrator import OrchestratorError, TaskOrchestrator
from ai_bridge.session_auth import SessionAuthError, SessionRegistry, rate_limit_bucket
from ai_bridge.sqlite_store import SqliteTaskStore
from ai_bridge.store import TaskStore
from ai_bridge.webhooks import handle_status_change
from mcp.roles import Role
from mcp.security import sanitize_tool_payload

DATA_DIR = Path(
    os.environ.get(
        "AI_BRIDGE_DATA_DIR",
        str(Path(__file__).resolve().parent.parent / "data"),
    )
)
DB_PATH = Path(os.environ.get("AI_BRIDGE_DB_PATH", str(DATA_DIR / "ai_bridge.sqlite3")))
USE_SQLITE = os.environ.get("AI_BRIDGE_USE_SQLITE", "1").lower() not in ("0", "false", "no")
CORS_ORIGINS = [
    o.strip()
    for o in os.environ.get("AI_BRIDGE_CORS_ORIGINS", "").split(",")
    if o.strip()
]

app = FastAPI(
    title="ScooterCheck AI Bridge",
    version="2.0.0",
    description="Development Automation bridge — Cursor API server-side only.",
)

if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],
    )

_registry = SessionRegistry.from_env()
if USE_SQLITE:
    _store: Any = SqliteTaskStore(DB_PATH)
    migrated = _store.migrate_from_json(DATA_DIR)
else:
    _store = TaskStore(DATA_DIR)
    migrated = 0

_orchestrator = TaskOrchestrator(
    _store,
    use_live=os.environ.get("AI_BRIDGE_USE_LIVE", "").lower() in ("1", "true", "yes"),
)

DASHBOARD_DIR = Path(__file__).resolve().parent.parent / "dashboard"
if DASHBOARD_DIR.is_dir():
    app.mount("/static", StaticFiles(directory=str(DASHBOARD_DIR)), name="static")


def _auth(authorization: str | None, need: Role):
    try:
        return _registry.require(authorization, need)
    except SessionAuthError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc


def _rate(request: Request, principal_sub: str) -> None:
    key = f"{request.client.host if request.client else 'unk'}:{principal_sub}"
    if not rate_limit_bucket(key, limit=120):
        raise HTTPException(status_code=429, detail="rate limit exceeded")


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/")
def root_dashboard():
    index = DASHBOARD_DIR / "index.html"
    if index.is_file():
        return FileResponse(index)
    return JSONResponse({"service": "ai-bridge", "dashboard": "missing"})


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "version": "2.0.0",
        "live_api_key_present": live_api_available(),
        "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
        "chatgpt_connection_verified": False,
        "client_mode": _orchestrator.client_mode,
        "persistence": "sqlite" if USE_SQLITE else "json",
        "json_migrated_on_boot": migrated,
        "anonymous_write": False,
    }


@app.get("/api/v1/status")
def api_status(
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.READ)
    _rate(request, principal.subject)
    pulls = fetch_open_pulls("basti9010", "scootercheck")
    ci = fetch_workflow_runs("basti9010", "scootercheck", branch="cursor/ai-bridge-v2-b100")
    tasks = _store.list_tasks(
        owner_subject=principal.subject,
        admin=principal.role == Role.ADMIN,
        limit=20,
    )
    active = [t for t in tasks if t.status.value not in ("COMPLETED", "CANCELLED", "FAILED")]
    return {
        "bridge": "ok",
        "cursor": {
            "key_present": live_api_available(),
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "mode": _orchestrator.client_mode,
            "status": "LIVE_READY" if live_api_available() else "BLOCKED_MISSING_CREDENTIAL",
        },
        "chatgpt_connection_verified": False,
        "active_tasks": [
            {"task_id": t.task_id, "title": t.title, "status": t.status.value}
            for t in active
        ],
        "recent_tasks": [
            {"task_id": t.task_id, "title": t.title, "status": t.status.value}
            for t in tasks[:10]
        ],
        "pull_requests": pulls,
        "ci": ci,
        "production_deploy": "UNKNOWN",
        "security_approvals_open": [],
    }


class CreateTaskBody(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    repository: str = "https://github.com/basti9010/scootercheck"
    base_branch: str = "cursor/ai-bridge-v2-b100"
    priority: TaskPriority = TaskPriority.P2
    approval_required: bool = True
    idempotency_key: str = Field(min_length=1)
    requirements: list[str] = Field(default_factory=list)
    acceptance_criteria: list[str] = Field(default_factory=list)


@app.get("/api/v1/tasks")
def list_tasks(
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.READ)
    _rate(request, principal.subject)
    tasks = _store.list_tasks(
        owner_subject=principal.subject,
        admin=principal.role == Role.ADMIN,
    )
    return {
        "tasks": [t.model_dump(mode="json") for t in tasks],
        "count": len(tasks),
    }


@app.post("/api/v1/tasks")
def create_task_api(
    body: CreateTaskBody,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.TASK_WRITE)
    _rate(request, principal.subject)
    payload = TaskCreate(
        title=body.title,
        description=body.description,
        source=TaskSource.API,
        repository=body.repository,
        base_branch=body.base_branch,
        priority=body.priority,
        requirements=body.requirements,
        acceptance_criteria=body.acceptance_criteria,
        idempotency_key=body.idempotency_key,
        requested_by=principal.subject,
        approval_required=body.approval_required,
    )
    task, created = _orchestrator.create_task(payload)
    if hasattr(_store, "audit"):
        _store.audit(task.task_id, principal.subject, "create_task", {"created": created})
    return {"created": created, "task": task.model_dump(mode="json")}


@app.get("/api/v1/tasks/{task_id}")
def get_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.READ)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    return task.model_dump(mode="json")


@app.post("/api/v1/tasks/{task_id}/approve")
def approve_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.APPROVAL)
    _rate(request, principal.subject)
    try:
        task = _orchestrator.approve(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if hasattr(_store, "audit"):
        _store.audit(task_id, principal.subject, "approve", {})
    return task.model_dump(mode="json")


def _assert_task_access(task, principal) -> None:
    if principal.role == Role.ADMIN:
        return
    if task.requested_by and task.requested_by != principal.subject:
        raise HTTPException(status_code=403, detail="foreign task")


@app.post("/api/v1/tasks/{task_id}/analyze")
def analyze_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.TASK_WRITE)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    try:
        task = _orchestrator.plan_task(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if hasattr(_store, "audit"):
        _store.audit(task_id, principal.subject, "analyze", {"status": task.status.value})
    return task.model_dump(mode="json")


@app.post("/api/v1/tasks/{task_id}/start")
def start_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    """Start Cursor agent for an existing QUEUED task (after analyze/approve)."""
    principal = _auth(authorization, Role.TASK_WRITE)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    try:
        report = _orchestrator.start_existing(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if hasattr(_store, "audit"):
        _store.audit(task_id, principal.subject, "start_task", {"status": report.get("status")})
    return sanitize_tool_payload(report)


@app.post("/api/v1/tasks/{task_id}/cancel")
def cancel_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.TASK_WRITE)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    try:
        task = _orchestrator.cancel(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    if hasattr(_store, "audit"):
        _store.audit(task_id, principal.subject, "cancel", {})
    return task.model_dump(mode="json")


@app.post("/api/v1/tasks/{task_id}/sync")
def sync_task_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.READ)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    try:
        task = _orchestrator.sync_agent(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return task.model_dump(mode="json")


@app.get("/api/v1/tasks/{task_id}/report")
def task_report_api(
    task_id: str,
    request: Request,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    principal = _auth(authorization, Role.READ)
    _rate(request, principal.subject)
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    _assert_task_access(task, principal)
    if not task.report_path or not Path(task.report_path).is_file():
        return {
            "task_id": task_id,
            "status": task.status.value,
            "report": None,
            "summary": "No report yet",
        }
    import json

    data = json.loads(Path(task.report_path).read_text(encoding="utf-8"))
    return {"task_id": task_id, "status": task.status.value, "report": data}


# Legacy prototype routes (still gated lightly via optional auth in v2)
@app.post("/tasks")
def create_task_legacy(payload: TaskCreate, authorization: str | None = Header(default=None)):
    _auth(authorization, Role.TASK_WRITE)
    task, created = _orchestrator.create_task(payload)
    return {"task": task.model_dump(mode="json"), "created": created}


@app.post("/orchestrate")
def orchestrate(payload: TaskCreate, authorization: str | None = Header(default=None)):
    _auth(authorization, Role.TASK_WRITE)
    try:
        return _orchestrator.run_vertical(payload)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/webhooks/cursor/status-change")
def webhook_status_change(payload: dict[str, Any], authorization: str | None = Header(default=None)):
    # Prefer shared webhook secret when configured
    expected = os.environ.get("AIBRIDGE_WEBHOOK_SECRET", "").strip()
    if expected:
        if not authorization or authorization.strip() != f"Bearer {expected}":
            raise HTTPException(status_code=401, detail="invalid webhook auth")
    event = handle_status_change(payload)
    return {"accepted": True, "event": event.model_dump(by_alias=True)}
