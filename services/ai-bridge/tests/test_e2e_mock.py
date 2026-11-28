"""Mock E2E vertical slice: create → plan → mock agent → report."""

from __future__ import annotations

import json
from pathlib import Path

from ai_bridge.cursor_client import (
    CURSOR_API_LIVE_VERIFIED,
    MockCursorClient,
    RealCursorClient,
    live_api_available,
)
from ai_bridge.models import CreateAgentRequest, TaskCreate, TaskPriority, TaskSource, TaskStatus
from ai_bridge.orchestrator import TaskOrchestrator
from ai_bridge.schema_loader import load_task_schema
from ai_bridge.store import TaskStore
from ai_bridge.webhooks import handle_status_change


def _create(**overrides) -> TaskCreate:
    data = dict(
        title="Mock vertical slice",
        description="Exercise orchestrator with MockCursorClient",
        source=TaskSource.API,
        repository="https://github.com/basti9010/scootercheck",
        base_branch="cursor/development-automation-b100",
        priority=TaskPriority.P2,
        requirements=["Use mock client", "Write JSON report"],
        acceptance_criteria=["status COMPLETED", "CURSOR_API_LIVE_VERIFIED false"],
        idempotency_key="e2e-mock-1",
        affected_components=["services/ai-bridge"],
    )
    data.update(overrides)
    return TaskCreate(**data)


def test_mock_e2e_vertical_slice(tmp_path: Path) -> None:
    orch = TaskOrchestrator(TaskStore(tmp_path), client=MockCursorClient())
    report = orch.run_vertical(_create())
    assert report["status"] == TaskStatus.COMPLETED.value
    assert report["client_mode"] == "mock"
    assert report["CURSOR_API_LIVE_VERIFIED"] is False
    assert report["run_status"] == "FINISHED"
    assert str(report["cursor_agent_id"]).startswith("bc-mock-")
    assert Path(report["report_path"]).is_file()
    task = orch.store.get(report["task_id"])
    assert task is not None
    assert task.status == TaskStatus.COMPLETED
    assert task.plan is not None
    assert "cursor_prompt" in task.plan


def test_mock_e2e_idempotent_rerun(tmp_path: Path) -> None:
    orch = TaskOrchestrator(TaskStore(tmp_path), client=MockCursorClient())
    r1 = orch.run_vertical(_create(idempotency_key="e2e-idem"))
    r2 = orch.run_vertical(_create(idempotency_key="e2e-idem"))
    assert r1["task_id"] == r2["task_id"]
    assert r2.get("idempotent_replay") is True
    assert r2["status"] == TaskStatus.COMPLETED.value


def test_approval_gate_without_auto_approve(tmp_path: Path) -> None:
    orch = TaskOrchestrator(TaskStore(tmp_path), client=MockCursorClient())
    report = orch.run_vertical(
        _create(idempotency_key="needs-appr", approval_required=True),
        auto_approve=False,
    )
    assert report.get("awaiting_approval") is True
    assert report["status"] == TaskStatus.WAITING_FOR_APPROVAL.value
    approved = orch.approve(report["task_id"])
    assert approved.status == TaskStatus.QUEUED


def test_mock_client_deterministic_ids() -> None:
    client = MockCursorClient()
    req = CreateAgentRequest(prompt_text="hello", repository_url="https://x/y", starting_ref="main")
    a1, r1 = client.create_agent(req)
    a2, r2 = client.create_agent(req)
    assert a1.id == a2.id
    assert r1.id == r2.id


def test_real_client_skipped_without_key(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    assert RealCursorClient.from_env() is None
    assert live_api_available() is False


def test_task_schema_loads() -> None:
    schema = load_task_schema()
    assert schema["title"] == "ScooterCheckDevelopmentTask"
    assert "CREATED" in schema["properties"]["status"]["enum"]


def test_webhook_stub_finished() -> None:
    event = handle_status_change(
        {"event": "statusChange", "agentId": "bc-1", "runId": "run-1", "status": "FINISHED"}
    )
    assert event.event == "statusChange"


def test_orchestrator_report_marks_live_unverified(tmp_path: Path) -> None:
    orch = TaskOrchestrator(TaskStore(tmp_path), client=MockCursorClient())
    report = orch.run_vertical(_create(idempotency_key="live-flag"))
    data = json.loads(Path(report["report_path"]).read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is False
    assert data["live_api_key_present"] == live_api_available()
