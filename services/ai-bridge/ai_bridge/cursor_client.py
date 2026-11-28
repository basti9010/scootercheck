"""Cursor Cloud Agents API client — protocol, mock, and real skeleton (v1 shapes)."""

from __future__ import annotations

import hashlib
import os
import time
from typing import Optional, Protocol, runtime_checkable

import httpx

from ai_bridge.models import AgentInfo, CreateAgentRequest, RunInfo

API_BASE = "https://api.cursor.com"
RUN_ACTIVE = frozenset({"CREATING", "RUNNING", "WAITING_FOR_BACKGROUND_WORK"})
RUN_TERMINAL = frozenset({"FINISHED", "ERROR", "CANCELLED", "EXPIRED"})


@runtime_checkable
class CursorClient(Protocol):
    def create_agent(self, request: CreateAgentRequest) -> tuple[AgentInfo, RunInfo]: ...
    def get_agent(self, agent_id: str) -> AgentInfo: ...
    def get_run(self, agent_id: str, run_id: str) -> RunInfo: ...
    def list_agents(self, *, limit: int = 20) -> list[AgentInfo]: ...


class CursorAPIKeyMissing(RuntimeError):
    pass


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
            git = {"branches": [{"repoUrl": "github.com/example/repo", "branch": f"cursor/mock-{run_id[-8:]}"}]}
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


class RealCursorClient:
    """Live skeleton against https://api.cursor.com. Requires CURSOR_API_KEY."""

    def __init__(self, api_key: str, *, base_url: str = API_BASE, timeout: float = 60.0) -> None:
        if not api_key:
            raise CursorAPIKeyMissing("CURSOR_API_KEY is required for RealCursorClient")
        self._api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    @classmethod
    def from_env(cls) -> Optional["RealCursorClient"]:
        key = os.environ.get("CURSOR_API_KEY", "").strip()
        if not key:
            return None
        base = os.environ.get("CURSOR_API_BASE", API_BASE).strip() or API_BASE
        return cls(key, base_url=base)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def create_agent(self, request: CreateAgentRequest) -> tuple[AgentInfo, RunInfo]:
        body: dict = {"prompt": {"text": request.prompt_text}}
        if request.name:
            body["name"] = request.name
        if request.model_id:
            body["model"] = {"id": request.model_id}
        if request.repository_url:
            repo: dict = {"url": request.repository_url}
            if request.starting_ref:
                repo["startingRef"] = request.starting_ref
            body["repos"] = [repo]
        if request.auto_create_pr:
            body["autoCreatePR"] = True
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.post(f"{self.base_url}/v1/agents", headers=self._headers(), json=body)
            resp.raise_for_status()
            data = resp.json()
        agent_raw, run_raw = data["agent"], data["run"]
        agent = AgentInfo(
            id=agent_raw["id"],
            name=agent_raw.get("name", ""),
            status=agent_raw.get("status", "ACTIVE"),
            latest_run_id=agent_raw.get("latestRunId"),
            url=agent_raw.get("url"),
        )
        run = RunInfo(
            id=run_raw["id"],
            agent_id=run_raw.get("agentId", agent.id),
            status=run_raw.get("status", "CREATING"),
            result=run_raw.get("result"),
            duration_ms=run_raw.get("durationMs"),
            git=run_raw.get("git"),
        )
        return agent, run

    def get_agent(self, agent_id: str) -> AgentInfo:
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(f"{self.base_url}/v1/agents/{agent_id}", headers=self._headers())
            resp.raise_for_status()
            raw = resp.json()
        return AgentInfo(
            id=raw["id"],
            name=raw.get("name", ""),
            status=raw.get("status", ""),
            latest_run_id=raw.get("latestRunId"),
            url=raw.get("url"),
        )

    def get_run(self, agent_id: str, run_id: str) -> RunInfo:
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(
                f"{self.base_url}/v1/agents/{agent_id}/runs/{run_id}", headers=self._headers()
            )
            resp.raise_for_status()
            raw = resp.json()
        return RunInfo(
            id=raw["id"],
            agent_id=raw.get("agentId", agent_id),
            status=raw.get("status", ""),
            result=raw.get("result"),
            duration_ms=raw.get("durationMs"),
            git=raw.get("git"),
        )

    def list_agents(self, *, limit: int = 20) -> list[AgentInfo]:
        with httpx.Client(timeout=self.timeout) as client:
            resp = client.get(
                f"{self.base_url}/v1/agents", headers=self._headers(), params={"limit": limit}
            )
            resp.raise_for_status()
            data = resp.json()
        items = data.get("items") or data.get("agents") or []
        return [
            AgentInfo(
                id=item["id"],
                name=item.get("name", ""),
                status=item.get("status", ""),
                latest_run_id=item.get("latestRunId"),
                url=item.get("url"),
            )
            for item in items
        ]


def live_api_available() -> bool:
    return bool(os.environ.get("CURSOR_API_KEY", "").strip())


CURSOR_API_LIVE_VERIFIED = False
