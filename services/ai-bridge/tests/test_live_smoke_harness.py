"""Unit tests for live smoke harness (no real Cursor API)."""

from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest

from ai_bridge import run_live_smoke as smoke
from ai_bridge.cursor_client import CursorAPIError, RealCursorClient
from ai_bridge.live_status import is_live_agent_id, is_mock_agent_id, map_cursor_run_to_report
from ai_bridge.models import AgentInfo, CreateAgentRequest, RunInfo


def test_status_mapping() -> None:
    assert map_cursor_run_to_report("CREATING") == "CREATED"
    assert map_cursor_run_to_report("RUNNING") == "RUNNING"
    assert map_cursor_run_to_report("FINISHED") == "COMPLETED"
    assert map_cursor_run_to_report("ERROR") == "FAILED"
    assert map_cursor_run_to_report("CANCELLED") == "CANCELLED"
    assert map_cursor_run_to_report("weird") == "UNKNOWN"
    assert map_cursor_run_to_report(None) == "UNKNOWN"


def test_mock_id_detection() -> None:
    assert is_mock_agent_id("bc-mock-abc")
    assert not is_live_agent_id("bc-mock-abc")
    assert is_live_agent_id("bc-a92fffc1-167e-537f-b321-324e6265a64a")


def test_redact_secrets() -> None:
    raw = "Authorization: Bearer super-secret-token CURSOR_API_KEY=abc123"
    out = smoke.redact(raw)
    assert "super-secret-token" not in out
    assert "abc123" not in out
    assert "[REDACTED]" in out


def test_missing_key_blocked(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("CURSOR_API_KEY", raising=False)
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    code = smoke.main()
    assert code == 2
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is False
    assert data["CURSOR_AGENT_COMPLETED"] is False
    assert data["block"] == "BLOCKED_MISSING_CREDENTIAL"


def test_mock_id_in_live_mode(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CURSOR_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_LIVE_MAX_POLLS", "1")
    monkeypatch.setenv("AI_BRIDGE_LIVE_POLL_INTERVAL_S", "0")

    class Fake:
        def create_agent(self, request: CreateAgentRequest):
            return (
                AgentInfo(id="bc-mock-deadbeef", name="m", status="ACTIVE", latest_run_id="run-1"),
                RunInfo(id="run-1", agent_id="bc-mock-deadbeef", status="CREATING"),
            )

        def get_run(self, agent_id: str, run_id: str):
            raise AssertionError("should not poll mock id")

    monkeypatch.setattr(smoke.RealCursorClient, "from_env", classmethod(lambda cls: Fake()))
    code = smoke.main()
    assert code == 1
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["block"] == "MOCK_ID_IN_LIVE_MODE"
    assert data["CURSOR_API_LIVE_VERIFIED"] is False


def test_successful_start_and_complete(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CURSOR_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_LIVE_MAX_POLLS", "5")
    monkeypatch.setenv("AI_BRIDGE_LIVE_POLL_INTERVAL_S", "0")
    monkeypatch.setenv("AI_BRIDGE_LIVE_IDEMPOTENCY_KEY", "test-idem-1")

    polls = {"n": 0}

    class Fake:
        def create_agent(self, request: CreateAgentRequest):
            assert "research/ai-bridge-live-smoke" in request.prompt_text
            return (
                AgentInfo(
                    id="bc-live-1111-2222-3333",
                    name="live",
                    status="ACTIVE",
                    latest_run_id="run-live-1",
                    url="https://cursor.com/agents/bc-live-1111-2222-3333",
                ),
                RunInfo(id="run-live-1", agent_id="bc-live-1111-2222-3333", status="CREATING"),
            )

        def get_run(self, agent_id: str, run_id: str):
            polls["n"] += 1
            if polls["n"] < 3:
                return RunInfo(id=run_id, agent_id=agent_id, status="RUNNING")
            return RunInfo(
                id=run_id,
                agent_id=agent_id,
                status="FINISHED",
                result="ok",
                git={"branches": [{"branch": "cursor/live-smoke-xyz"}], "pullRequestUrl": "https://github.com/basti9010/scootercheck/pull/999"},
            )

        def get_agent(self, agent_id: str):
            return AgentInfo(id=agent_id, name="live", status="IDLE", latest_run_id="run-live-1")

    monkeypatch.setattr(smoke.RealCursorClient, "from_env", classmethod(lambda cls: Fake()))
    code = smoke.main()
    assert code == 0
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is True
    assert data["CURSOR_AGENT_COMPLETED"] is True
    assert data["cursor_agent_id"] == "bc-live-1111-2222-3333"
    assert data["final_status"] == "COMPLETED"
    assert data["branch"] == "cursor/live-smoke-xyz"
    assert (tmp_path / "LIVE_RESULT.md").is_file()
    assert (tmp_path / "idempotency_state.json").is_file()


def test_timeout_keeps_agent_unknown(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CURSOR_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_LIVE_MAX_POLLS", "2")
    monkeypatch.setenv("AI_BRIDGE_LIVE_POLL_INTERVAL_S", "0")

    class Fake:
        def create_agent(self, request: CreateAgentRequest):
            return (
                AgentInfo(id="bc-live-timeout", name="t", status="ACTIVE", latest_run_id="run-t"),
                RunInfo(id="run-t", agent_id="bc-live-timeout", status="CREATING"),
            )

        def get_run(self, agent_id: str, run_id: str):
            return RunInfo(id=run_id, agent_id=agent_id, status="RUNNING")

    monkeypatch.setattr(smoke.RealCursorClient, "from_env", classmethod(lambda cls: Fake()))
    code = smoke.main()
    assert code == 0  # API verified even on timeout
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is True
    assert data["CURSOR_AGENT_COMPLETED"] is False
    assert data["final_status"] == "UNKNOWN"
    assert data["cursor_agent_id"] == "bc-live-timeout"


def test_status_fetch_error(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CURSOR_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_LIVE_POLL_INTERVAL_S", "0")

    class Fake:
        def create_agent(self, request: CreateAgentRequest):
            return (
                AgentInfo(id="bc-live-err", name="e", status="ACTIVE", latest_run_id="run-e"),
                RunInfo(id="run-e", agent_id="bc-live-err", status="CREATING"),
            )

        def get_run(self, agent_id: str, run_id: str):
            raise CursorAPIError("boom", status_code=500, correlation_id="c1")

    monkeypatch.setattr(smoke.RealCursorClient, "from_env", classmethod(lambda cls: Fake()))
    code = smoke.main()
    assert code == 1
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is False
    assert data["block"] == "CURSOR_API_ERROR"


def test_idempotent_resume_skips_create(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("CURSOR_API_KEY", "test-key-not-real")
    monkeypatch.setenv("AI_BRIDGE_LIVE_EVIDENCE_DIR", str(tmp_path))
    monkeypatch.setenv("AI_BRIDGE_LIVE_IDEMPOTENCY_KEY", "idem-resume")
    monkeypatch.setenv("AI_BRIDGE_LIVE_MAX_POLLS", "3")
    monkeypatch.setenv("AI_BRIDGE_LIVE_POLL_INTERVAL_S", "0")
    (tmp_path / "idempotency_state.json").write_text(
        json.dumps(
            {
                "idempotency_key": "idem-resume",
                "cursor_agent_id": "bc-live-resume",
                "cursor_run_id": "run-resume",
            }
        ),
        encoding="utf-8",
    )
    created = {"n": 0}
    polls = {"n": 0}

    class Fake:
        def create_agent(self, request: CreateAgentRequest):
            created["n"] += 1
            raise AssertionError("must not create again")

        def get_run(self, agent_id: str, run_id: str):
            polls["n"] += 1
            if polls["n"] < 2:
                return RunInfo(id=run_id, agent_id=agent_id, status="RUNNING")
            return RunInfo(id=run_id, agent_id=agent_id, status="FINISHED", result="done")

    monkeypatch.setattr(smoke.RealCursorClient, "from_env", classmethod(lambda cls: Fake()))
    assert smoke.main() == 0
    assert created["n"] == 0
    data = json.loads((tmp_path / "LIVE_RESULT.json").read_text(encoding="utf-8"))
    assert data["CURSOR_API_LIVE_VERIFIED"] is True
    assert data["test_results"]["created_this_run"] is False


def test_real_client_invalid_response_4xx(monkeypatch: pytest.MonkeyPatch) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "bad"})

    transport = httpx.MockTransport(handler)

    class Patched(httpx.Client):
        def __init__(self, *a, **k):
            k["transport"] = transport
            super().__init__(*a, **k)

    monkeypatch.setattr("ai_bridge.cursor_client.httpx.Client", Patched)
    client = RealCursorClient("k", max_retries=0)
    with pytest.raises(CursorAPIError) as ei:
        client.create_agent(CreateAgentRequest(prompt_text="x"))
    assert ei.value.status_code == 400
