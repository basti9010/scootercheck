"""Adapter: MCP tools → AI Bridge TaskOrchestrator + Sqlite/JSON store.

Keeps ChatGPT/MCP clients on the same backend as the Mobile Development Center.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from ai_bridge.github_status import fetch_workflow_runs
from ai_bridge.models import TaskCreate, TaskPriority, TaskSource
from ai_bridge.orchestrator import OrchestratorError, TaskOrchestrator
from ai_bridge.sqlite_store import SqliteTaskStore
from ai_bridge.store import TaskStore


def build_orchestrator() -> TaskOrchestrator:
    data = Path(
        os.environ.get(
            "AI_BRIDGE_DATA_DIR",
            str(Path(__file__).resolve().parent.parent / "data"),
        )
    )
    use_sqlite = os.environ.get("AI_BRIDGE_USE_SQLITE", "1").lower() not in (
        "0",
        "false",
        "no",
    )
    if use_sqlite:
        db = Path(os.environ.get("AI_BRIDGE_DB_PATH", str(data / "ai_bridge.sqlite3")))
        store: Any = SqliteTaskStore(db)
    else:
        store = TaskStore(data)
    use_live = os.environ.get("AI_BRIDGE_USE_LIVE", "").lower() in ("1", "true", "yes")
    return TaskOrchestrator(store, use_live=use_live)


class BridgeBackend:
    """Production-oriented MCP orchestrator surface (replaces MockOrchestrator when wired)."""

    def __init__(self, orch: TaskOrchestrator | None = None) -> None:
        self.orch = orch or build_orchestrator()

    def get_project_status(self) -> dict[str, Any]:
        from ai_bridge.cursor_client import CURSOR_API_LIVE_VERIFIED, live_api_available

        return {
            "service": "ai-bridge",
            "client_mode": self.orch.client_mode,
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "live_api_key_present": live_api_available(),
            "chatgpt_connection_verified": False,
            "persistence": "sqlite" if isinstance(self.orch.store, SqliteTaskStore) else "json",
        }

    def create_task(
        self, title: str, created_by: str, meta: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        meta = meta or {}
        payload = TaskCreate(
            title=title[:200],
            description=str(meta.get("description") or title),
            source=TaskSource.MCP,
            repository=str(meta.get("repository") or "https://github.com/basti9010/scootercheck"),
            base_branch=str(meta.get("base_branch") or "cursor/ai-bridge-v2-b100"),
            priority=TaskPriority(str(meta.get("priority") or "P2")),
            idempotency_key=str(meta.get("idempotency_key") or f"mcp-{created_by}-{title}")[:200],
            requested_by=created_by,
            approval_required=bool(meta.get("approval_required", True)),
        )
        task, created = self.orch.create_task(payload)
        return {"created": created, "task": task.model_dump(mode="json")}

    def start_task(self, task_id: str) -> dict[str, Any]:
        try:
            return self.orch.start_existing(task_id)
        except OrchestratorError as exc:
            return {"ok": False, "error": str(exc)}

    def get_task_status(self, task_id: str) -> dict[str, Any]:
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        return task.model_dump(mode="json")

    def get_task_report(self, task_id: str) -> dict[str, Any]:
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        if not task.report_path or not Path(task.report_path).is_file():
            return {"task_id": task_id, "report": None, "status": task.status.value}
        import json

        return {
            "task_id": task_id,
            "status": task.status.value,
            "report": json.loads(Path(task.report_path).read_text(encoding="utf-8")),
        }

    def list_tasks(self) -> dict[str, Any]:
        tasks = self.orch.store.list_tasks(admin=True, limit=50)
        return {"tasks": [t.model_dump(mode="json") for t in tasks], "count": len(tasks)}

    def get_ci_status(self, ref: str | None = None) -> dict[str, Any]:
        data = fetch_workflow_runs("basti9010", "scootercheck", branch=ref)
        data["raw_log_excerpt"] = ""
        return data

    def prepare_fix(
        self, task_id: str, summary: str, approved_by: str
    ) -> dict[str, Any]:
        return {
            "task_id": task_id,
            "summary": summary,
            "approved_by": approved_by,
            "deploy": False,
            "note": "Fix preparation recorded; production deploy requires GitHub Environment approval.",
        }

    def cancel_task(self, task_id: str) -> dict[str, Any]:
        try:
            task = self.orch.cancel(task_id)
            return task.model_dump(mode="json")
        except OrchestratorError as exc:
            return {"ok": False, "error": str(exc)}
