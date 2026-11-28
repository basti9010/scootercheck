"""Orchestrator plan → approve → start_existing (mock client)."""

from __future__ import annotations

from pathlib import Path

from ai_bridge.models import TaskCreate, TaskPriority, TaskSource, TaskStatus
from ai_bridge.orchestrator import TaskOrchestrator
from ai_bridge.sqlite_store import SqliteTaskStore


def _payload(key: str) -> TaskCreate:
    return TaskCreate(
        title="Hub nav",
        description="Fix back animations in Investigation Hub",
        source=TaskSource.API,
        repository="https://github.com/basti9010/scootercheck",
        base_branch="cursor/ai-bridge-v2-b100",
        priority=TaskPriority.P2,
        idempotency_key=key,
        requested_by="owner",
        approval_required=True,
    )


def test_plan_approve_start_mock(tmp_path: Path) -> None:
    store = SqliteTaskStore(tmp_path / "t.sqlite3")
    orch = TaskOrchestrator(store, max_polls=5, poll_sleep_s=0)
    task, created = orch.create_task(_payload("orch-v2-1"))
    assert created
    task = orch.plan_task(task.task_id)
    assert task.status == TaskStatus.WAITING_FOR_APPROVAL
    assert task.plan
    task = orch.approve(task.task_id)
    assert task.status == TaskStatus.QUEUED
    report = orch.start_existing(task.task_id)
    assert report["status"] == "COMPLETED"
    assert report["client_mode"] == "mock"
    assert report["CURSOR_API_LIVE_VERIFIED"] is False
    again = store.get(task.task_id)
    assert again is not None
    assert again.cursor_agent_id
    assert again.cursor_agent_id.startswith("bc-mock-")


def test_cancel_created(tmp_path: Path) -> None:
    store = SqliteTaskStore(tmp_path / "c.sqlite3")
    orch = TaskOrchestrator(store)
    task, _ = orch.create_task(_payload("orch-v2-cancel"))
    cancelled = orch.cancel(task.task_id)
    assert cancelled.status == TaskStatus.CANCELLED
