"""State machine transition tests."""

from __future__ import annotations

import pytest

from ai_bridge.models import Task, TaskCreate, TaskSource, TaskStatus
from ai_bridge.state_machine import (
    ALLOWED_TRANSITIONS,
    TERMINAL_STATUSES,
    InvalidTransition,
    can_transition,
    transition,
)


def _task(status: TaskStatus = TaskStatus.CREATED) -> Task:
    t = Task.from_create(
        TaskCreate(
            title="t",
            description="d",
            source=TaskSource.API,
            repository="https://github.com/example/repo",
            base_branch="main",
            idempotency_key="sm-1",
        )
    )
    if status != TaskStatus.CREATED:
        data = t.model_dump()
        data["status"] = status
        t = Task.model_validate(data)
    return t


def test_happy_path_edges():
    path = [
        TaskStatus.CREATED,
        TaskStatus.VALIDATING,
        TaskStatus.PLANNED,
        TaskStatus.QUEUED,
        TaskStatus.RUNNING,
        TaskStatus.TESTING,
        TaskStatus.REVIEW,
        TaskStatus.COMPLETED,
    ]
    for a, b in zip(path, path[1:]):
        assert can_transition(a, b)


def test_approval_branch():
    assert can_transition(TaskStatus.PLANNED, TaskStatus.WAITING_FOR_APPROVAL)
    assert can_transition(TaskStatus.WAITING_FOR_APPROVAL, TaskStatus.QUEUED)


def test_terminal_states_have_no_outbound():
    for status in TERMINAL_STATUSES:
        assert ALLOWED_TRANSITIONS[status] == frozenset()


def test_invalid_transition_raises():
    task = _task(TaskStatus.CREATED)
    with pytest.raises(InvalidTransition):
        transition(task, TaskStatus.RUNNING)


def test_transition_updates_timestamp_and_status():
    task = _task(TaskStatus.CREATED)
    updated = transition(task, TaskStatus.VALIDATING)
    assert updated.status == TaskStatus.VALIDATING
    assert updated.updated_at >= task.updated_at
    assert task.status == TaskStatus.CREATED


def test_same_status_is_allowed_noop():
    assert can_transition(TaskStatus.QUEUED, TaskStatus.QUEUED)


def test_blocked_and_failed_recovery():
    assert can_transition(TaskStatus.BLOCKED, TaskStatus.QUEUED)
    assert can_transition(TaskStatus.FAILED, TaskStatus.QUEUED)
    assert can_transition(TaskStatus.REVIEW, TaskStatus.QUEUED)


def test_cancel_from_many_states():
    for status in (
        TaskStatus.CREATED,
        TaskStatus.VALIDATING,
        TaskStatus.PLANNED,
        TaskStatus.QUEUED,
        TaskStatus.RUNNING,
    ):
        assert can_transition(status, TaskStatus.CANCELLED)
