"""Mock E2E vertical slice: create → plan → mock agent → report."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from ai_bridge.cursor_client import (
    CURSOR_API_LIVE_VERIFIED,
    MockCursorClient,
    RealCursorClient,
    live_api_available,
)
from ai_bridge.models import TaskCreate, TaskPriority, TaskSource, TaskStatus
from ai_bridge.orchestrator import OrchestratorError, TaskOrchestrator
from ai_bridge.schema_loader import load_task_schema, validate_task_dict
from ai_bridge.store import TaskStore
from ai_bridge.webhooks import handle_status_change


def _create(**overrides) -> TaskCreate:
    base = dict(
        title="Mock vertical slice",
        description="Exercise orchestrator with MockCursorClient",
        source=TaskSource.AUTOMATION,
        repository="https://github.com/basti9010/scootercheck",
        base_branch="cursor/development-automation-b100",
        priority=TaskPriority.P1,
        idempotency_key="e2e-mock-1",
        requirements=["Use mock client", "Write JSON report"],
        acceptance_criteria=["status COMPLETED", "CURSOR_API_LIVE_VERIFIED false"],
        affected_components=["services/ai-bridge"],
        approval_required=False,
    )
    base.update(overrides)
    return TaskCreate(**base)


def test_mock_e2e_vertical_slice(tmp_path: Path):
    store = TaskStore(tmp_path)
    orch = TaskOrchestrator(
        store, cursor=MockCursorClient(finish_after_polls=3), poll_interval_s=0, max_polls=10
    )
    report = orch.run_vertical(_create())
    assert report["status"] == TaskStatus.COMPLETED.value
    assert report["client_mode"] in ("injected", "mock")
    assert report["CURSOR_API_LIVE_VERIFIED"] is False
    assert CURSOR_API_LIVE_VERIFIED is False
    assert report["run_status"] == "FINISHED"
    assert report["cursor_agent_id"].startswith("bc-mock-")
    assert Path(report["report_path"]).is_file()
    task = store.get(report["task_id"])
    assert task is not None
    assert task.status == TaskStatus.COMPLETED
    assert task.plan is not None
    validate_task_dict(task.model_dump(mode="json"))


def test_mock_e2e_idempotent_rerun(tmp_path: Path):
    store = TaskStore(tmp_path)
    orch = TaskOrchestrator(
        store, cursor=MockCursorClient(finish_after_polls=2), poll_interval_s=0
    )
    r1 = orch.run_vertical(_create(idempotency_key="e2e-idem"))
    r2 = orch.run_vertical(_create(idempotency_key="e2e-idem"))
    assert r1["task_id"] == r2["task_id"]
    assert r2.get("idempotent_replay") is True


def test_approval_gate_without_auto_approve(tmp_path: Path):
    store = TaskStore(tmp_path)
    orch = TaskOrchestrator(
        store, cursor=MockCursorClient(), auto_approve=False, poll_interval_s=0
    )
    result = orch.run_vertical(_create(idempotency_key="needs-appr", approval_required=True))
    assert result["awaiting_approval"] is True
    assert result["status"] == TaskStatus.WAITING_FOR_APPROVAL.value
    approved = orch.approve(result["task_id"])
    assert approved.status == TaskStatus.QUEUED


def test_mock_client_deterministic_ids():
    from ai_bridge.models import CreateAgentRequest

    req = CreateAgentRequest(
        prompt_text="hello", repository_url="https://x/y", starting_ref="main"
    )
    a1, r1 = MockCursorClient().create_agent(req)
    a2, r2 = MockCursorClient().create_agent(req)
    assert a1.id == a2.id
    assert r1.id == r2.id


def test_real_client_skipped_without_key(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    assert RealCursorClient.from_env() is None
    assert live_api_available() is False
    with pytest.raises(OrchestratorError, match="CURSOR_API_KEY"):
        TaskOrchestrator(TaskStore(tmp_path), use_live=True)


def test_task_schema_loads():
    schema = load_task_schema()
    assert schema["title"] == "ScooterCheckDevelopmentTask"
    assert "CREATED" in schema["properties"]["status"]["enum"]


def test_webhook_stub_finished():
    event = handle_status_change(
        {"event": "statusChange", "agentId": "bc-1", "runId": "run-1", "status": "FINISHED"}
    )
    assert event.status == "FINISHED"
    assert event.agent_id == "bc-1"


def test_orchestrator_report_marks_live_unverified(tmp_path: Path):
    orch = TaskOrchestrator(TaskStore(tmp_path), poll_interval_s=0)
    report = orch.run_vertical(_create(idempotency_key="live-flag"))
    raw = json.loads(Path(report["report_path"]).read_text(encoding="utf-8"))
    assert raw["CURSOR_API_LIVE_VERIFIED"] is False
    assert raw["live_api_key_present"] is live_api_available()
