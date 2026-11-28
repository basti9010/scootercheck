"""FastAPI mini-service for the AI Bridge prototype."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from ai_bridge.cursor_client import CURSOR_API_LIVE_VERIFIED, live_api_available
from ai_bridge.models import TaskCreate
from ai_bridge.orchestrator import OrchestratorError, TaskOrchestrator
from ai_bridge.store import TaskStore
from ai_bridge.webhooks import handle_status_change

DEFAULT_DATA = Path(
    os.environ.get(
        "AI_BRIDGE_DATA_DIR",
        str(Path(__file__).resolve().parent.parent / "data"),
    )
)

app = FastAPI(
    title="ScooterCheck AI Bridge",
    version="0.1.0",
    description="Etappe 1–3 prototype: tasks + mock Cursor orchestrator",
)

_store = TaskStore(DEFAULT_DATA)
_orchestrator = TaskOrchestrator(
    _store,
    use_live=os.environ.get("AI_BRIDGE_USE_LIVE", "").lower() in ("1", "true", "yes"),
    auto_approve=os.environ.get("AI_BRIDGE_AUTO_APPROVE", "true").lower()
    not in ("0", "false", "no"),
)


class VerticalRunResponse(BaseModel):
    task_id: str
    status: str
    client_mode: Optional[str] = None
    CURSOR_API_LIVE_VERIFIED: bool = False
    report_path: Optional[str] = None
    awaiting_approval: bool = False
    detail: dict[str, Any] = Field(default_factory=dict)


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "live_api_key_present": live_api_available(),
        "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
        "client_mode": _orchestrator.client_mode,
    }


@app.post("/tasks")
def create_task(payload: TaskCreate) -> dict[str, Any]:
    task, created = _orchestrator.create_task(payload)
    return {"task": task.model_dump(mode="json"), "created": created}


@app.get("/tasks/{task_id}")
def get_task(task_id: str) -> dict[str, Any]:
    task = _store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    return task.model_dump(mode="json")


@app.post("/tasks/{task_id}/approve")
def approve_task(task_id: str) -> dict[str, Any]:
    try:
        task = _orchestrator.approve(task_id)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return task.model_dump(mode="json")


@app.post("/orchestrate")
def orchestrate(payload: TaskCreate) -> dict[str, Any]:
    try:
        return _orchestrator.run_vertical(payload)
    except OrchestratorError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.post("/webhooks/cursor/status-change")
def webhook_status_change(payload: dict[str, Any]) -> dict[str, Any]:
    event = handle_status_change(payload)
    return {"accepted": True, "event": event.model_dump(by_alias=True)}
