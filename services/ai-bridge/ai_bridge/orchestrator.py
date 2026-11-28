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
from ai_bridge.state_machine import InvalidTransition
from ai_bridge.store import TaskStore


class OrchestratorError(Exception):
    """OrchestratorError"""


class TaskOrchestrator:
    """
    Vertical prototype for Etappe 1–3.

    Default path uses MockCursorClient (deterministic). When use_live=True and
    CURSOR_API_KEY is set, RealCursorClient is used — success still does not
    flip CURSOR_API_LIVE_VERIFIED in this package without an explicit gate.
    """

    def __init__(
        self,
        store: TaskStore,
        *,
        client: CursorClient | None = None,
        use_live: bool = False,
        max_polls: int = 20,
        poll_sleep_s: float = 0.0,
    ) -> None:
        self.store = store
        self.reports_dir = store.root / "reports"
        self.reports_dir.mkdir(parents=True, exist_ok=True)
        self.planner = TaskPlanner()
        self.max_polls = max_polls
        self.poll_sleep_s = poll_sleep_s
        if client is not None:
            self.client = client
            self.client_mode = (
                "mock" if isinstance(client, MockCursorClient) else "injected"
            )
        elif use_live:
            live = RealCursorClient.from_env()
            if live is None:
                raise OrchestratorError(
                    "use_live=True but CURSOR_API_KEY is not set; refusing live call"
                )
            self.client = live
            self.client_mode = "live"
        else:
            self.client = MockCursorClient()
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
        return self._advance(task, TaskStatus.QUEUED)

    def run_vertical(
        self,
        payload: TaskCreate,
        *,
        auto_approve: bool = True,
        skip_if_exists_completed: bool = True,
    ) -> dict[str, Any]:
        """
        Full slice: create → validate → plan → approval → start → poll → report.

        Idempotent on idempotency_key: if the same key already COMPLETED,
        returns the existing report summary without re-running (when
        skip_if_exists_completed).
        """
        if not payload.repository or not payload.base_branch:
            raise OrchestratorError("repository and base_branch are required")

        task, created = self.create_task(payload)
        if (
            skip_if_exists_completed
            and not created
            and task.status == TaskStatus.COMPLETED
            and task.report_path
        ):
            summary = self._load_report_summary(task)
            summary["idempotent_replay"] = True
            return summary

        try:
            task = self._advance(task, TaskStatus.VALIDATING)
            plan = self.planner.plan(task)
            task.plan = plan
            task.assigned_agents = list(plan.get("agents") or task.assigned_agents)
            task = self.store.patch(task)
            task = self._advance(task, TaskStatus.PLANNED)

            if task.approval_required:
                task = self._advance(task, TaskStatus.WAITING_FOR_APPROVAL)
                if not auto_approve:
                    return {
                        "task_id": task.task_id,
                        "status": task.status.value,
                        "awaiting_approval": True,
                    }
                task = self.approve(task.task_id)
            else:
                task = self._advance(task, TaskStatus.QUEUED)

            task = self._advance(task, TaskStatus.RUNNING)
            agent, run = self.client.create_agent(
                CreateAgentRequest(
                    prompt_text=str(plan.get("cursor_prompt") or task.description),
                    repository_url=task.repository,
                    starting_ref=task.base_branch,
                    name=task.title[:100],
                    auto_create_pr=False,
                )
            )
            task.cursor_agent_id = agent.id
            task.cursor_run_id = run.id
            task = self.store.patch(task)

            run = self._poll_run(agent.id, run.id)
            if run.status == "FINISHED":
                task = self._advance(task, TaskStatus.TESTING)
                task = self._advance(task, TaskStatus.REVIEW)
                task = self._advance(task, TaskStatus.COMPLETED)
                return self._write_report(task, run)
            if run.status == "ERROR":
                task = self._advance(task, TaskStatus.FAILED, error_message="Cursor run ERROR")
                return self._fail_report(task)
            if run.status == "CANCELLED":
                task = self._advance(task, TaskStatus.CANCELLED)
                return self._fail_report(task)
            task = self._advance(
                task,
                TaskStatus.FAILED,
                error_message=f"Unexpected terminal status: {run.status}",
            )
            return self._fail_report(task)
        except Exception as exc:  # noqa: BLE001 — surface into task failure
            try:
                if task.status not in {TaskStatus.COMPLETED, TaskStatus.CANCELLED}:
                    if task.status == TaskStatus.CREATED:
                        task = self._advance(task, TaskStatus.VALIDATING)
                    if task.status not in {
                        TaskStatus.FAILED,
                        TaskStatus.BLOCKED,
                        TaskStatus.CANCELLED,
                        TaskStatus.COMPLETED,
                    }:
                        # best-effort move toward FAILED when legal
                        from ai_bridge.state_machine import can_transition

                        if can_transition(task.status, TaskStatus.FAILED):
                            task = self._advance(task, TaskStatus.FAILED, error_message=str(exc))
                        elif can_transition(task.status, TaskStatus.BLOCKED):
                            task = self._advance(task, TaskStatus.BLOCKED, error_message=str(exc))
            except InvalidTransition:
                pass
            raise

    def _poll_run(self, agent_id: str, run_id: str):
        last = None
        for _ in range(self.max_polls):
            last = self.client.get_run(agent_id, run_id)
            if last.status in RUN_TERMINAL:
                return last
            if self.poll_sleep_s:
                time.sleep(self.poll_sleep_s)
        raise OrchestratorError(
            f"Timed out polling run {run_id} after {self.max_polls} polls "
            f"(last={getattr(last, 'status', None)})"
        )

    def _advance(self, task: Task, target: TaskStatus, *, error_message: str | None = None) -> Task:
        return self.store.update_status(task.task_id, target, error_message=error_message)

    def _require(self, task_id: str) -> Task:
        task = self.store.get(task_id)
        if task is None:
            raise OrchestratorError(f"Unknown task_id: {task_id}")
        return task

    def _write_report(self, task: Task, run) -> dict[str, Any]:
        path = self.reports_dir / f"{task.task_id}.json"
        report = {
            "task_id": task.task_id,
            "title": task.title,
            "status": task.status.value,
            "created": True,
            "client_mode": self.client_mode,
            "live_api_key_present": live_api_available(),
            "CURSOR_API_LIVE_VERIFIED": CURSOR_API_LIVE_VERIFIED,
            "cursor_agent_id": task.cursor_agent_id,
            "cursor_run_id": task.cursor_run_id,
            "run_status": run.status,
            "run_result": run.result,
            "run_git": run.git,
            "plan": task.plan,
            "error_message": task.error_message,
            "generated_at": utc_now_iso(),
            "report_path": str(path),
        }
        path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        task.report_path = str(path)
        self.store.patch(task)
        return report

    def _fail_report(self, task: Task) -> dict[str, Any]:
        class _Empty:
            status = None
            result = None
            git = None

        return self._write_report(task, _Empty())

    def _load_report_summary(self, task: Task) -> dict[str, Any]:
        with open(task.report_path, "r", encoding="utf-8") as fh:
            return json.load(fh)
