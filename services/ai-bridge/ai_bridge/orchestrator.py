"""Task Orchestrator — create → plan → (approval) → mock/live agent → report."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Optional

from ai_bridge.cursor_client import (
    CURSOR_API_LIVE_VERIFIED,
    RUN_TERMINAL,
    CursorClient,
    MockCursorClient,
    RealCursorClient,
    live_api_available,
)
from ai_bridge.models import (
    ApprovalStatus,
    CreateAgentRequest,
    Task,
    TaskCreate,
    TaskStatus,
    utc_now_iso,
)
from ai_bridge.planner import TaskPlanner
from ai_bridge.state_machine import InvalidTransition, can_transition
from ai_bridge.store import TaskStore


class OrchestratorError(Exception):
    pass


class TaskOrchestrator:
    def __init__(
        self,
        store: TaskStore,
        *,
        cursor: Optional[CursorClient] = None,
        planner: Optional[TaskPlanner] = None,
        reports_dir: Path | str | None = None,
        use_live: bool = False,
        poll_interval_s: float = 0.01,
        max_polls: int = 50,
        auto_approve: bool = True,
    ) -> None:
        self.store = store
        self.planner = planner or TaskPlanner()
        self.reports_dir = Path(reports_dir or (store.root / "reports"))
        self.reports_dir.mkdir(parents=True, exist_ok=True)
        self.poll_interval_s = poll_interval_s
        self.max_polls = max_polls
        self.auto_approve = auto_approve
        self.use_live = use_live

        if cursor is not None:
            self.cursor: CursorClient = cursor
            self.client_mode = "injected"
        elif use_live:
            real = RealCursorClient.from_env()
            if real is None:
                raise OrchestratorError(
                    "use_live=True but CURSOR_API_KEY is not set; refusing live call"
                )
            self.cursor = real
            self.client_mode = "live"
        else:
            self.cursor = MockCursorClient()
            self.client_mode = "mock"

    def create_task(self, payload: TaskCreate) -> tuple[Task, bool]:
        return self.store.create_task(payload)

    def approve(self, task_id: str) -> Task:
        task = self._require(task_id)
        if task.status != TaskStatus.WAITING_FOR_APPROVAL:
            raise OrchestratorError(
                f"Task {task_id} is {task.status.value}, expected WAITING_FOR_APPROVAL"
            )
        task.approval_status = ApprovalStatus.APPROVED
        task = self.store.patch(task)
        return self.store.update_status(task.task_id, TaskStatus.QUEUED)

    def run_vertical(
        self, payload: TaskCreate, *, skip_if_exists_completed: bool = True
    ) -> dict[str, Any]:
        task, created = self.create_task(payload)
        if (
            not created
            and skip_if_exists_completed
            and task.status == TaskStatus.COMPLETED
            and task.report_path
        ):
            return self._load_report_summary(task)

        try:
            task = self._advance(task, TaskStatus.VALIDATING)
            if not task.repository or not task.base_branch:
                task = self.store.update_status(
                    task.task_id,
                    TaskStatus.FAILED,
                    error_message="repository and base_branch are required",
                )
                return self._fail_report(task)

            plan = self.planner.plan(task)
            task.plan = plan
            if not task.assigned_agents:
                task.assigned_agents = list(plan.get("agents") or [])
            task = self.store.patch(task)
            task = self._advance(task, TaskStatus.PLANNED)

            if task.approval_required:
                task = self._advance(task, TaskStatus.WAITING_FOR_APPROVAL)
                if self.auto_approve:
                    task = self.approve(task.task_id)
                else:
                    return {
                        "task_id": task.task_id,
                        "status": task.status.value,
                        "created": created,
                        "client_mode": self.client_mode,
                        "awaiting_approval": True,
                        "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
                    }
            else:
                task = self._advance(task, TaskStatus.QUEUED)

            task = self._advance(task, TaskStatus.RUNNING)
            agent, run = self.cursor.create_agent(
                CreateAgentRequest(
                    prompt_text=plan["cursor_prompt"],
                    repository_url=task.repository if task.repository.startswith("http") else None,
                    starting_ref=task.base_branch,
                    name=task.title[:100],
                )
            )
            task.cursor_agent_id = agent.id
            task.cursor_run_id = run.id
            task = self.store.patch(task)

            final_run = self._poll_run(agent.id, run.id)
            if final_run.status == "FINISHED":
                task = self._advance(task, TaskStatus.TESTING)
                task = self._advance(task, TaskStatus.REVIEW)
                task = self._advance(task, TaskStatus.COMPLETED)
            elif final_run.status == "ERROR":
                task = self.store.update_status(
                    task.task_id,
                    TaskStatus.FAILED,
                    error_message=final_run.result or "Cursor run ERROR",
                )
            elif final_run.status == "CANCELLED":
                task = self._advance(task, TaskStatus.CANCELLED)
            else:
                task = self.store.update_status(
                    task.task_id,
                    TaskStatus.FAILED,
                    error_message=f"Unexpected terminal status: {final_run.status}",
                )

            report = self._write_report(task, final_run, created=created)
            task.report_path = str(report["report_path"])
            task = self.store.patch(task)
            return report

        except InvalidTransition as exc:
            task = self._require(task.task_id)
            task = self.store.update_status(task.task_id, TaskStatus.FAILED, error_message=str(exc))
            return self._fail_report(task)
        except Exception as exc:  # noqa: BLE001
            task = self._require(task.task_id)
            try:
                if task.status not in (
                    TaskStatus.FAILED,
                    TaskStatus.COMPLETED,
                    TaskStatus.CANCELLED,
                ):
                    if can_transition(task.status, TaskStatus.FAILED):
                        task = self.store.update_status(
                            task.task_id, TaskStatus.FAILED, error_message=str(exc)
                        )
                    else:
                        task.error_message = str(exc)
                        task = self.store.patch(task)
            except Exception:  # noqa: BLE001
                task.error_message = str(exc)
                task = self.store.patch(task)
            return self._fail_report(task)

    def _poll_run(self, agent_id: str, run_id: str):
        last = None
        for _ in range(self.max_polls):
            last = self.cursor.get_run(agent_id, run_id)
            if last.status in RUN_TERMINAL:
                return last
            time.sleep(self.poll_interval_s)
        raise OrchestratorError(
            f"Timed out polling run {run_id} after {self.max_polls} polls "
            f"(last={getattr(last, 'status', None)})"
        )

    def _advance(self, task: Task, target: TaskStatus) -> Task:
        if task.status == target:
            return task
        return self.store.update_status(task.task_id, target)

    def _require(self, task_id: str) -> Task:
        task = self.store.get(task_id)
        if task is None:
            raise OrchestratorError(f"Unknown task_id: {task_id}")
        return task

    def _write_report(self, task: Task, run, *, created: bool) -> dict[str, Any]:
        path = self.reports_dir / f"{task.task_id}.json"
        body = {
            "task_id": task.task_id,
            "title": task.title,
            "status": task.status.value,
            "created": created,
            "client_mode": self.client_mode,
            "live_api_key_present": live_api_available(),
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "cursor_agent_id": task.cursor_agent_id,
            "cursor_run_id": task.cursor_run_id,
            "run_status": run.status if run else None,
            "run_result": run.result if run else None,
            "run_git": run.git if run else None,
            "plan": task.plan,
            "error_message": task.error_message,
            "generated_at": utc_now_iso(),
            "report_path": str(path),
        }
        path.write_text(json.dumps(body, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return body

    def _fail_report(self, task: Task) -> dict[str, Any]:
        class _Empty:
            status = None
            result = None
            git = None

        report = self._write_report(task, _Empty(), created=False)
        task.report_path = str(report["report_path"])
        self.store.patch(task)
        return report

    def _load_report_summary(self, task: Task) -> dict[str, Any]:
        path = Path(task.report_path) if task.report_path else None
        if path and path.exists():
            with path.open("r", encoding="utf-8") as fh:
                data = json.load(fh)
            data["idempotent_replay"] = True
            return data
        return {
            "task_id": task.task_id,
            "status": task.status.value,
            "idempotent_replay": True,
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "report_path": task.report_path,
        }
