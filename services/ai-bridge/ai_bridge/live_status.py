"""Map Cursor Cloud Agents API run statuses → live-smoke report statuses.

Internal report statuses (documented for operators):
  CREATED, STARTED, RUNNING, COMPLETED, FAILED, CANCELLED, TIMEOUT, UNKNOWN

Only values that map from documented Cursor API run statuses are used for
terminal success/failure. TIMEOUT means we stopped polling; the agent may
still be running remotely.
"""

from __future__ import annotations

# Documented Cursor run statuses (Cloud Agents API v1).
CURSOR_ACTIVE = frozenset({"CREATING", "RUNNING", "WAITING_FOR_BACKGROUND_WORK"})
CURSOR_TERMINAL = frozenset({"FINISHED", "ERROR", "CANCELLED", "EXPIRED"})

CURSOR_RUN_TO_REPORT: dict[str, str] = {
    "CREATING": "CREATED",
    "RUNNING": "RUNNING",
    "WAITING_FOR_BACKGROUND_WORK": "RUNNING",
    "FINISHED": "COMPLETED",
    "ERROR": "FAILED",
    "CANCELLED": "CANCELLED",
    "EXPIRED": "FAILED",
}


def map_cursor_run_to_report(run_status: str | None) -> str:
    if not run_status:
        return "UNKNOWN"
    return CURSOR_RUN_TO_REPORT.get(str(run_status).upper(), "UNKNOWN")


def is_mock_agent_id(agent_id: str | None) -> bool:
    return bool(agent_id) and str(agent_id).startswith("bc-mock-")


def is_live_agent_id(agent_id: str | None) -> bool:
    return bool(agent_id) and not is_mock_agent_id(agent_id)
