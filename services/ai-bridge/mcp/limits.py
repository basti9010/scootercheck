"""Operational limits for MCP → Cursor agent starts (cost / abuse control)."""

from __future__ import annotations

import os
import threading
import time
from dataclasses import dataclass, field


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


@dataclass
class LimitConfig:
    max_concurrent_agents: int = field(default_factory=lambda: _int_env("AIBRIDGE_MAX_CONCURRENT_AGENTS", 2))
    max_tasks_per_subject: int = field(default_factory=lambda: _int_env("AIBRIDGE_MAX_TASKS_PER_SUBJECT", 50))
    max_starts_per_hour: int = field(default_factory=lambda: _int_env("AIBRIDGE_MAX_STARTS_PER_HOUR", 6))
    max_retries: int = field(default_factory=lambda: _int_env("AIBRIDGE_MAX_START_RETRIES", 1))


class LimitTracker:
    def __init__(self, cfg: LimitConfig | None = None) -> None:
        self.cfg = cfg or LimitConfig()
        self._lock = threading.Lock()
        self._active_agents: set[str] = set()
        self._starts: dict[str, list[float]] = {}

    def note_agent_started(self, agent_id: str) -> None:
        with self._lock:
            self._active_agents.add(agent_id)

    def note_agent_finished(self, agent_id: str) -> None:
        with self._lock:
            self._active_agents.discard(agent_id)

    def check_can_start(self, subject: str) -> tuple[bool, str | None]:
        with self._lock:
            if len(self._active_agents) >= self.cfg.max_concurrent_agents:
                return False, "max_concurrent_agents"
            now = time.time()
            window = [t for t in self._starts.get(subject, []) if now - t < 3600]
            self._starts[subject] = window
            if len(window) >= self.cfg.max_starts_per_hour:
                return False, "max_starts_per_hour"
            return True, None

    def record_start(self, subject: str) -> None:
        with self._lock:
            self._starts.setdefault(subject, []).append(time.time())


LIMITS = LimitTracker()
