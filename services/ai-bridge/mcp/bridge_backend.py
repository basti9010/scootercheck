"""Adapter: MCP tools → AI Bridge TaskOrchestrator + RealCursorClient path."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any
from uuid import uuid4

from ai_bridge.cursor_client import CURSOR_API_LIVE_VERIFIED, live_api_available
from ai_bridge.github_status import fetch_open_pulls, fetch_workflow_runs
from ai_bridge.models import TaskCreate, TaskPriority, TaskSource, TaskStatus
from ai_bridge.orchestrator import OrchestratorError, TaskOrchestrator
from ai_bridge.sqlite_store import SqliteTaskStore
from ai_bridge.store import TaskStore

from .limits import LIMITS


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
    """Production MCP surface — same orchestrator as HTTP API when configured."""

    def __init__(self, orch: TaskOrchestrator | None = None) -> None:
        self.orch = orch or build_orchestrator()

    def get_project_status(self) -> dict[str, Any]:
        pulls = fetch_open_pulls("basti9010", "scootercheck")
        ci = fetch_workflow_runs("basti9010", "scootercheck")
        tasks = self.orch.store.list_tasks(admin=True, limit=30)
        active = [
            t
            for t in tasks
            if t.status.value not in ("COMPLETED", "CANCELLED", "FAILED")
        ]
        agents = [
            {"task_id": t.task_id, "cursor_agent_id": t.cursor_agent_id, "status": t.status.value}
            for t in active
            if t.cursor_agent_id
        ]
        return {
            "service": "ai-bridge-mcp",
            "client_mode": self.orch.client_mode,
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "live_api_key_present": live_api_available(),
            "chatgpt_connection_verified": False,
            "persistence": "sqlite" if isinstance(self.orch.store, SqliteTaskStore) else "json",
            "active_tasks": [
                {"task_id": t.task_id, "title": t.title, "status": t.status.value}
                for t in active
            ],
            "active_cursor_agents": agents,
            "pull_requests": pulls,
            "ci": ci,
            "blocks": [
                b
                for b in [
                    None
                    if live_api_available()
                    else "CURSOR_API_KEY missing on this host",
                    "CHATGPT_CONNECTION_VERIFIED=false until owner registers MCP in ChatGPT",
                ]
                if b
            ],
        }

    def create_task(
        self, title: str, created_by: str, meta: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        meta = meta or {}
        listed = self.orch.store.list_tasks(owner_subject=created_by, admin=False, limit=200)
        if len(listed) >= LIMITS.cfg.max_tasks_per_subject:
            return {"ok": False, "error": "max_tasks_per_subject"}
        payload = TaskCreate(
            title=title[:200],
            description=str(meta.get("description") or title),
            source=TaskSource.MCP,
            repository=str(
                meta.get("repository") or "https://github.com/basti9010/scootercheck"
            ),
            base_branch=str(
                meta.get("base_branch")
                or os.environ.get("AI_BRIDGE_DEFAULT_BASE", "cursor/testflight-ci-133a")
            ),
            priority=TaskPriority(str(meta.get("priority") or "P2")),
            idempotency_key=str(
                meta.get("idempotency_key") or f"mcp-{created_by}-{uuid4()}"
            )[:200],
            requested_by=created_by,
            approval_required=bool(meta.get("approval_required", True)),
            requirements=list(meta.get("requirements") or []),
            acceptance_criteria=list(meta.get("acceptance_criteria") or []),
        )
        task, created = self.orch.create_task(payload)
        planned = None
        if created and task.status == TaskStatus.CREATED:
            try:
                planned = self.orch.plan_task(task.task_id)
            except OrchestratorError as exc:
                return {
                    "created": created,
                    "task": task.model_dump(mode="json"),
                    "plan_error": str(exc),
                }
        out_task = planned or task
        return {
            "created": created,
            "task_id": out_task.task_id,
            "status": out_task.status.value,
            "approval_status": getattr(out_task.approval_status, "value", out_task.approval_status),
            "plan": out_task.plan,
            "assigned_agents": out_task.assigned_agents,
            "task": out_task.model_dump(mode="json"),
        }

    def start_task(self, task_id: str, *, subject: str = "unknown") -> dict[str, Any]:
        ok, reason = LIMITS.check_can_start(subject)
        if not ok:
            return {"ok": False, "error": reason}
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        # Idempotency: already has live agent → sync only
        if task.cursor_agent_id and not str(task.cursor_agent_id).startswith("bc-mock-"):
            try:
                synced = self.orch.sync_agent(task_id)
                return {
                    "ok": True,
                    "idempotent": True,
                    "task_id": synced.task_id,
                    "cursor_agent_id": synced.cursor_agent_id,
                    "status": synced.status.value,
                }
            except OrchestratorError as exc:
                return {"ok": False, "error": str(exc)}
        try:
            # Ensure queued
            if task.status == TaskStatus.CREATED:
                task = self.orch.plan_task(task_id)
            if task.status == TaskStatus.WAITING_FOR_APPROVAL:
                return {"ok": False, "error": "awaiting_approval", "task_id": task_id}
            if task.status != TaskStatus.QUEUED:
                return {
                    "ok": False,
                    "error": f"unexpected_status:{task.status.value}",
                    "task_id": task_id,
                }
            LIMITS.record_start(subject)
            report = self.orch.start_existing(task_id)
            agent_id = report.get("cursor_agent_id")
            if agent_id:
                LIMITS.note_agent_started(str(agent_id))
                if report.get("status") in ("COMPLETED", "FAILED", "CANCELLED"):
                    LIMITS.note_agent_finished(str(agent_id))
            return {
                "ok": True,
                "task_id": task_id,
                "cursor_agent_id": agent_id,
                "cursor_run_id": report.get("cursor_run_id"),
                "status": report.get("status"),
                "client_mode": report.get("client_mode"),
                "CURSOR_API_LIVE_VERIFIED": report.get("CURSOR_API_LIVE_VERIFIED"),
                "report": report,
            }
        except OrchestratorError as exc:
            return {"ok": False, "error": str(exc)}

    def get_task_status(self, task_id: str) -> dict[str, Any]:
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        if task.cursor_agent_id and task.cursor_run_id:
            try:
                task = self.orch.sync_agent(task_id)
            except OrchestratorError:
                pass
        return {
            "task_id": task.task_id,
            "status": task.status.value,
            "cursor_agent_id": task.cursor_agent_id,
            "cursor_run_id": task.cursor_run_id,
            "last_sync_at": task.last_sync_at,
            "branch_name": task.branch_name,
            "github_pr_url": task.github_pr_url,
            "error_message": task.error_message,
            "title": task.title,
        }

    def get_task_report(self, task_id: str) -> dict[str, Any]:
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        if not task.report_path or not Path(task.report_path).is_file():
            return {"task_id": task_id, "report": None, "status": task.status.value}
        return {
            "task_id": task_id,
            "status": task.status.value,
            "report": json.loads(Path(task.report_path).read_text(encoding="utf-8")),
        }

    def review_task(self, task_id: str) -> dict[str, Any]:
        task = self.orch.store.get(task_id)
        if task is None:
            raise KeyError(f"unknown task: {task_id}")
        report = None
        if task.report_path and Path(task.report_path).is_file():
            report = json.loads(Path(task.report_path).read_text(encoding="utf-8"))
        ci = fetch_workflow_runs("basti9010", "scootercheck", branch=task.branch_name)
        implemented = task.status.value in ("COMPLETED", "FAILED", "CANCELLED") or bool(
            task.cursor_agent_id
        )
        tested = bool(report) or bool(ci.get("available"))
        deployed = False  # never claim deploy from MCP
        e2e = bool(
            report
            and report.get("CURSOR_API_LIVE_VERIFIED")
            and report.get("status") == "COMPLETED"
            and task.cursor_agent_id
            and not str(task.cursor_agent_id).startswith("bc-mock-")
        )
        return {
            "task_id": task_id,
            "IMPLEMENTED": implemented,
            "TESTED": tested,
            "DEPLOYED": deployed,
            "END_TO_END_VERIFIED": e2e,
            "status": task.status.value,
            "cursor_agent_id": task.cursor_agent_id,
            "github_pr_url": task.github_pr_url,
            "ci": ci,
            "notes": [
                "DEPLOYED remains false unless a separate GitHub Environment deploy is approved.",
                "END_TO_END_VERIFIED requires live Cursor completion evidence on this task.",
            ],
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
        if hasattr(self.orch.store, "audit"):
            self.orch.store.audit(
                task_id, approved_by, "prepare_fix", {"summary": summary[:500]}
            )
        return {
            "task_id": task_id,
            "summary": summary,
            "approved_by": approved_by,
            "deploy": False,
            "max_autofix_attempts": 2,
            "note": "Fix preparation recorded; production deploy requires GitHub Environment approval.",
        }

    def cancel_task(self, task_id: str) -> dict[str, Any]:
        try:
            task = self.orch.cancel(task_id)
            if task.cursor_agent_id:
                LIMITS.note_agent_finished(str(task.cursor_agent_id))
            return task.model_dump(mode="json")
        except OrchestratorError as exc:
            return {"ok": False, "error": str(exc)}
