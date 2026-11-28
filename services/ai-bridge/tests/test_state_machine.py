"""State machine transition tests."""

from __future__ import annotations

import pytest

from ai_bridge.models import Task, TaskPriority, TaskSource, TaskStatus, utc_now_iso
from ai_bridge.state_machine import (
    ALLOWED_TRANSITIONS,
    InvalidTransition,
    TERMINAL_STATUSES,
    can_transition,
    transition,
)


def _task(status: TaskStatus = TaskStatus.CREATED) -> Task:
    now = utc_now_iso()
    return Task(
        task_id="t",
        title="t",
        description="d",
        source=TaskSource.API,
        repository="https://github.com/example/repo",
        base_branch="main",
        priority=TaskPriority.P2,
        status=status,
        created_at=now,
        updated_at=now,
        idempotency_key="sm-1",
    )


def test_happy_path_edges() -> None:
    path = [
        (TaskStatus.CREATED, TaskStatus.VALIDATING),
        (TaskStatus.VALIDATING, TaskStatus.PLANNED),
        (TaskStatus.PLANNED, TaskStatus.QUEUED),
        (TaskStatus.QUEUED, TaskStatus.RUNNING),
        (TaskStatus.RUNNING, TaskStatus.TESTING),
        (TaskStatus.TESTING, TaskStatus.REVIEW),
        (TaskStatus.REVIEW, TaskStatus.COMPLETED),
    ]
    for a, b in path:
        assert can_transition(a, b)


def test_approval_branch() -> None:
    assert can_transition(TaskStatus.PLANNED, TaskStatus.WAITING_FOR_APPROVAL)
    assert can_transition(TaskStatus.WAITING_FOR_APPROVAL, TaskStatus.QUEUED)


def test_terminal_states_have_no_outbound() -> None:
    for status in TERMINAL_STATUSES:
        assert ALLOWED_TRANSITIONS[status] == frozenset()


def test_invalid_transition_raises() -> None:
    with pytest.raises(InvalidTransition):
        transition(_task(TaskStatus.CREATED), TaskStatus.RUNNING)


def test_transition_updates_timestamp_and_status() -> None:
    task = _task(TaskStatus.CREATED)
    updated = transition(task, TaskStatus.VALIDATING)
    assert updated.status == TaskStatus.VALIDATING
    assert updated.updated_at >= task.updated_at


def test_same_status_is_allowed_noop() -> None:
    assert can_transition(TaskStatus.QUEUED, TaskStatus.QUEUED)


def test_blocked_and_failed_recovery() -> None:
    assert can_transition(TaskStatus.BLOCKED, TaskStatus.QUEUED)
    assert can_transition(TaskStatus.FAILED, TaskStatus.QUEUED)
    assert can_transition(TaskStatus.REVIEW, TaskStatus.QUEUED)


def test_cancel_from_many_states() -> None:
    for status in [
        TaskStatus.CREATED,
        TaskStatus.VALIDATING,
        TaskStatus.PLANNED,
        TaskStatus.WAITING_FOR_APPROVAL,
        TaskStatus.QUEUED,
        TaskStatus.RUNNING,
        TaskStatus.TESTING,
        TaskStatus.REVIEW,
        TaskStatus.BLOCKED,
        TaskStatus.FAILED,
    ]:
        assert can_transition(status, TaskStatus.CANCELLED)
