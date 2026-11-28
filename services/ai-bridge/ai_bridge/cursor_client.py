"""Cursor Cloud Agents API client — mock + production RealCursorClient (v1)."""

from __future__ import annotations

import hashlib
import logging
import os
import time
import uuid
from typing import Any, Optional, Protocol, runtime_checkable

import httpx

from ai_bridge.models import AgentInfo, CreateAgentRequest, RunInfo

API_BASE = "https://api.cursor.com"
RUN_ACTIVE = frozenset({"CREATING", "RUNNING", "WAITING_FOR_BACKGROUND_WORK"})
RUN_TERMINAL = frozenset({"FINISHED", "ERROR", "CANCELLED", "EXPIRED"})

logger = logging.getLogger(__name__)

# Flipped only by an explicit live smoke that recorded a real agent id.
CURSOR_API_LIVE_VERIFIED = False


@runtime_checkable
class CursorClient(Protocol):
    def create_agent(self, request: CreateAgentRequest) -> tuple[AgentInfo, RunInfo]: ...
    def get_agent(self, agent_id: str) -> AgentInfo: ...
    def get_run(self, agent_id: str, run_id: str) -> RunInfo: ...
    def list_agents(self, *, limit: int = 20) -> list[AgentInfo]: ...
    def cancel_run(self, agent_id: str, run_id: str) -> dict[str, Any]: ...


class CursorAPIKeyMissing(RuntimeError):
    pass


class CursorAPIError(RuntimeError):
    def __init__(self, message: str, *, status_code: int | None = None, correlation_id: str | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.correlation_id = correlation_id


class MockCursorClient:
    """Deterministic mock: same prompt → same ids; poll advances status."""

    def __init__(self, *, finish_after_polls: int = 3) -> None:
        self.finish_after_polls = max(1, finish_after_polls)
        self._agents: dict[str, AgentInfo] = {}
        self._runs: dict[str, RunInfo] = {}
        self._poll_counts: dict[str, int] = {}
        self._created_at = time.time()

    @staticmethod
    def _ids_for(prompt: str, repo: Optional[str], ref: Optional[str]) -> tuple[str, str]:
        digest = hashlib.sha256(f"{prompt}|{repo or ''}|{ref or ''}".encode("utf-8")).hexdigest()
        return f"bc-mock-{digest[:12]}", f"run-mock-{digest[12:24]}"

    def create_agent(self, request: CreateAgentRequest) -> tuple[AgentInfo, RunInfo]:
        agent_id, run_id = self._ids_for(
            request.prompt_text, request.repository_url, request.starting_ref
        )
        name = request.name or f"Mock: {request.prompt_text[:40]}"
        agent = AgentInfo(
            id=agent_id,
            name=name[:100],
            status="ACTIVE",
            latest_run_id=run_id,
            url=f"https://cursor.com/agents/{agent_id}",
        )
        run = RunInfo(id=run_id, agent_id=agent_id, status="CREATING")
        self._agents[agent_id] = agent
        self._runs[run_id] = run
        self._poll_counts[run_id] = 0
        return agent, run

    def get_agent(self, agent_id: str) -> AgentInfo:
        if agent_id not in self._agents:
            raise KeyError(f"Unknown mock agent: {agent_id}")
        return self._agents[agent_id]

    def get_run(self, agent_id: str, run_id: str) -> RunInfo:
        if run_id not in self._runs:
            raise KeyError(f"Unknown mock run: {run_id}")
        run = self._runs[run_id]
        if run.agent_id != agent_id:
            raise KeyError(f"Run {run_id} does not belong to agent {agent_id}")
        self._poll_counts[run_id] = self._poll_counts.get(run_id, 0) + 1
        n = self._poll_counts[run_id]
        if n >= self.finish_after_polls:
            status = "FINISHED"
            result = f"Mock agent completed work for run {run_id}. No live Cursor API call was made."
            duration_ms = int((time.time() - self._created_at) * 1000) % 100_000 + 1000
            git = {
                "branches": [
                    {"repoUrl": "github.com/example/repo", "branch": f"cursor/mock-{run_id[-8:]}"}
                ]
            }
            self._agents[agent_id] = self._agents[agent_id].model_copy(update={"status": "IDLE"})
        elif n == 1:
            status, result, duration_ms, git = "CREATING", None, None, None
        else:
            status, result, duration_ms, git = "RUNNING", None, None, None
        updated = run.model_copy(
            update={"status": status, "result": result, "duration_ms": duration_ms, "git": git}
        )
        self._runs[run_id] = updated
        return updated

    def list_agents(self, *, limit: int = 20) -> list[AgentInfo]:
        return list(self._agents.values())[:limit]

    def cancel_run(self, agent_id: str, run_id: str) -> dict[str, Any]:
        run = self.get_run(agent_id, run_id)
        if run.status in RUN_TERMINAL:
            return {"cancelled": False, "status": run.status, "reason": "already_terminal"}
        updated = run.model_copy(update={"status": "CANCELLED"})
        self._runs[run_id] = updated
        return {"cancelled": True, "status": "CANCELLED"}


class RealCursorClient:
    """Production client for https://api.cursor.com (Cloud Agents API v1).

    Never logs the API key. Retries on 429/5xx with exponential backoff.
    """

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = API_BASE,
        timeout: float = 60.0,
        max_retries: int = 4,
    ) -> None:
        if not api_key:
            raise CursorAPIKeyMissing("CURSOR_API_KEY is required for RealCursorClient")
        self._api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.max_retries = max_retries

    @classmethod
    def from_env(cls) -> Optional["RealCursorClient"]:
        key = os.environ.get("CURSOR_API_KEY", "").strip()
        if not key:
            return None
        base = os.environ.get("CURSOR_API_BASE", API_BASE).strip() or API_BASE
        return cls(key, base_url=base)

    def _headers(self, correlation_id: str) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Request-ID": correlation_id,
        }

    def _request(
        self,
        method: str,
        path: str,
        *,
        json_body: dict | None = None,
        params: dict | None = None,
        correlation_id: str | None = None,
    ) -> dict[str, Any]:
        cid = correlation_id or str(uuid.uuid4())
        url = f"{self.base_url}{path}"
        delay = 0.5
        last_exc: Exception | None = None
        for attempt in range(self.max_retries + 1):
            try:
                with httpx.Client(timeout=self.timeout) as client:
                    resp = client.request(
                        method,
                        url,
                        headers=self._headers(cid),
                        json=json_body,
                        params=params,
                    )
                if resp.status_code == 429 or resp.status_code >= 500:
                    logger.warning(
                        "cursor_api_retry status=%s attempt=%s correlation_id=%s path=%s",
                        resp.status_code,
                        attempt,
                        cid,
                        path,
                    )
                    if attempt >= self.max_retries:
                        raise CursorAPIError(
                            f"Cursor API HTTP {resp.status_code}",
                            status_code=resp.status_code,
                            correlation_id=cid,
                        )
                    time.sleep(delay)
                    delay = min(delay * 2, 8.0)
                    continue
                if resp.status_code >= 400:
                    # Never include response body if it might echo auth — truncate safely
                    raise CursorAPIError(
                        f"Cursor API HTTP {resp.status_code}",
                        status_code=resp.status_code,
                        correlation_id=cid,
                    )
                if not resp.content:
                    return {}
                return resp.json()
            except (httpx.TimeoutException, httpx.TransportError) as exc:
                last_exc = exc
                logger.warning(
                    "cursor_api_transport attempt=%s correlation_id=%s path=%s",
                    attempt,
                    cid,
                    path,
                )
                if attempt >= self.max_retries:
                    raise CursorAPIError(
                        f"Cursor API transport error: {type(exc).__name__}",
                        correlation_id=cid,
                    ) from exc
                time.sleep(delay)
                delay = min(delay * 2, 8.0)
        raise CursorAPIError(f"Cursor API failed: {last_exc}", correlation_id=cid)

    def create_agent(self, request: CreateAgentRequest) -> tuple[AgentInfo, RunInfo]:
        body: dict[str, Any] = {"prompt": {"text": request.prompt_text}}
        if request.name:
            body["name"] = request.name
        if request.model_id:
            body["model"] = {"id": request.model_id}
        if request.repository_url:
            repo: dict[str, Any] = {"url": request.repository_url}
            if request.starting_ref:
                repo["startingRef"] = request.starting_ref
            body["repos"] = [repo]
        if request.auto_create_pr:
            body["autoCreatePR"] = True
        data = self._request("POST", "/v1/agents", json_body=body)
        agent_raw = data.get("agent") or data
        run_raw = data.get("run") or {}
        agent = AgentInfo(
            id=str(agent_raw.get("id") or ""),
            name=str(agent_raw.get("name") or ""),
            status=str(agent_raw.get("status") or "ACTIVE"),
            latest_run_id=run_raw.get("id") or agent_raw.get("latestRunId"),
            url=agent_raw.get("url"),
        )
        run = RunInfo(
            id=str(run_raw.get("id") or agent.latest_run_id or ""),
            agent_id=str(run_raw.get("agentId") or agent.id),
            status=str(run_raw.get("status") or "CREATING"),
            result=run_raw.get("result"),
            duration_ms=run_raw.get("durationMs"),
            git=run_raw.get("git"),
        )
        return agent, run

    def get_agent(self, agent_id: str) -> AgentInfo:
        raw = self._request("GET", f"/v1/agents/{agent_id}")
        return AgentInfo(
            id=str(raw.get("id") or agent_id),
            name=str(raw.get("name") or ""),
            status=str(raw.get("status") or ""),
            latest_run_id=raw.get("latestRunId"),
            url=raw.get("url"),
        )

    def get_run(self, agent_id: str, run_id: str) -> RunInfo:
        raw = self._request("GET", f"/v1/agents/{agent_id}/runs/{run_id}")
        return RunInfo(
            id=str(raw.get("id") or run_id),
            agent_id=str(raw.get("agentId") or agent_id),
            status=str(raw.get("status") or ""),
            result=raw.get("result"),
            duration_ms=raw.get("durationMs"),
            git=raw.get("git"),
        )

    def list_agents(self, *, limit: int = 20) -> list[AgentInfo]:
        data = self._request("GET", "/v1/agents", params={"limit": limit})
        items = data.get("items") or data.get("agents") or []
        return [
            AgentInfo(
                id=str(item.get("id") or ""),
                name=str(item.get("name") or ""),
                status=str(item.get("status") or ""),
                latest_run_id=item.get("latestRunId"),
                url=item.get("url"),
            )
            for item in items
        ]

    def cancel_run(self, agent_id: str, run_id: str) -> dict[str, Any]:
        """POST /v1/agents/{id}/runs/{runId}/cancel — documented v1 endpoint."""
        try:
            data = self._request("POST", f"/v1/agents/{agent_id}/runs/{run_id}/cancel")
            return {"cancelled": True, "raw_keys": sorted(data.keys()) if isinstance(data, dict) else []}
        except CursorAPIError as exc:
            if exc.status_code == 409:
                return {"cancelled": False, "reason": "run_not_cancellable", "status_code": 409}
            raise


def live_api_available() -> bool:
    return bool(os.environ.get("CURSOR_API_KEY", "").strip())


def set_live_verified(value: bool) -> None:
    """Only call from the live smoke harness after a real agent id is observed."""
    global CURSOR_API_LIVE_VERIFIED
    CURSOR_API_LIVE_VERIFIED = bool(value)
