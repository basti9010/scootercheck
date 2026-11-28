"""Map Cursor Cloud Agents run statuses → internal TaskStatus."""

from __future__ import annotations

from ai_bridge.models import TaskStatus

# Documented run statuses from Cloud Agents API v1.
CURSOR_RUN_TO_TASK: dict[str, TaskStatus] = {
    "CREATING": TaskStatus.QUEUED,
    "RUNNING": TaskStatus.RUNNING,
    "WAITING_FOR_BACKGROUND_WORK": TaskStatus.RUNNING,
    "FINISHED": TaskStatus.TESTING,  # orchestrator advances TESTING→REVIEW→COMPLETED
    "ERROR": TaskStatus.FAILED,
    "CANCELLED": TaskStatus.CANCELLED,
    "EXPIRED": TaskStatus.FAILED,
}


def map_cursor_run_status(run_status: str) -> TaskStatus:
    return CURSOR_RUN_TO_TASK.get(run_status.upper(), TaskStatus.BLOCKED)
