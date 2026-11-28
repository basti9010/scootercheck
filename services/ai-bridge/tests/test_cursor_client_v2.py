"""RealCursorClient retry / cancel behaviour with httpx mock transport."""

from __future__ import annotations

import httpx
import pytest

from ai_bridge.cursor_client import (
    CursorAPIError,
    MockCursorClient,
    RealCursorClient,
)
from ai_bridge.models import CreateAgentRequest


def test_mock_cancel() -> None:
    client = MockCursorClient(finish_after_polls=5)
    agent, run = client.create_agent(CreateAgentRequest(prompt_text="x"))
    out = client.cancel_run(agent.id, run.id)
    assert out["cancelled"] is True


def test_real_client_retries_429(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] < 3:
            return httpx.Response(429, json={"error": "rate"})
        return httpx.Response(
            200,
            json={
                "agent": {"id": "bc-live-1", "name": "t", "status": "ACTIVE", "latestRunId": "run-1"},
                "run": {"id": "run-1", "agentId": "bc-live-1", "status": "CREATING"},
            },
        )

    transport = httpx.MockTransport(handler)

    class PatchedClient(httpx.Client):
        def __init__(self, *a, **k):
            k["transport"] = transport
            super().__init__(*a, **k)

    monkeypatch.setattr("ai_bridge.cursor_client.httpx.Client", PatchedClient)
    client = RealCursorClient("test-key", max_retries=4)
    agent, run = client.create_agent(CreateAgentRequest(prompt_text="hello"))
    assert agent.id == "bc-live-1"
    assert run.id == "run-1"
    assert calls["n"] == 3


def test_real_client_4xx_no_retry(monkeypatch: pytest.MonkeyPatch) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "nope"})

    transport = httpx.MockTransport(handler)

    class PatchedClient(httpx.Client):
        def __init__(self, *a, **k):
            k["transport"] = transport
            super().__init__(*a, **k)

    monkeypatch.setattr("ai_bridge.cursor_client.httpx.Client", PatchedClient)
    client = RealCursorClient("test-key", max_retries=2)
    with pytest.raises(CursorAPIError) as ei:
        client.get_agent("bc-x")
    assert ei.value.status_code == 401
