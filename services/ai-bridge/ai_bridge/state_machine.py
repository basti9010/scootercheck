"""Task status enum transitions for Development Automation 1.0."""

from __future__ import annotations

from ai_bridge.models import Task, TaskStatus, utc_now_iso


class TransitionError(Exception):
    pass


class InvalidTransition(TransitionError):
    def __init__(self, current: TaskStatus, target: TaskStatus) -> None:
        self.current = current
        self.target = target
        super().__init__(f"Invalid transition: {current.value} → {target.value}")


ALLOWED_TRANSITIONS: dict[TaskStatus, frozenset[TaskStatus]] = {
    TaskStatus.CREATED: frozenset({TaskStatus.VALIDATING, TaskStatus.CANCELLED}),
    TaskStatus.VALIDATING: frozenset(
        {TaskStatus.PLANNED, TaskStatus.FAILED, TaskStatus.BLOCKED, TaskStatus.CANCELLED}
    ),
    TaskStatus.PLANNED: frozenset(
        {TaskStatus.WAITING_FOR_APPROVAL, TaskStatus.QUEUED, TaskStatus.CANCELLED, TaskStatus.BLOCKED}
    ),
    TaskStatus.WAITING_FOR_APPROVAL: frozenset(
        {TaskStatus.QUEUED, TaskStatus.CANCELLED, TaskStatus.BLOCKED, TaskStatus.FAILED}
    ),
    TaskStatus.QUEUED: frozenset(
        {TaskStatus.RUNNING, TaskStatus.CANCELLED, TaskStatus.BLOCKED, TaskStatus.FAILED}
    ),
    TaskStatus.RUNNING: frozenset(
        {TaskStatus.TESTING, TaskStatus.FAILED, TaskStatus.BLOCKED, TaskStatus.CANCELLED}
    ),
    TaskStatus.TESTING: frozenset(
        {TaskStatus.REVIEW, TaskStatus.FAILED, TaskStatus.BLOCKED, TaskStatus.CANCELLED}
    ),
    TaskStatus.REVIEW: frozenset(
        {TaskStatus.COMPLETED, TaskStatus.FAILED, TaskStatus.BLOCKED, TaskStatus.QUEUED, TaskStatus.CANCELLED}
    ),
    TaskStatus.BLOCKED: frozenset({TaskStatus.QUEUED, TaskStatus.CANCELLED, TaskStatus.FAILED}),
    TaskStatus.FAILED: frozenset({TaskStatus.QUEUED, TaskStatus.CANCELLED}),
    TaskStatus.COMPLETED: frozenset(),
    TaskStatus.CANCELLED: frozenset(),
}

TERMINAL_STATUSES = frozenset({TaskStatus.COMPLETED, TaskStatus.CANCELLED})


def can_transition(current: TaskStatus, target: TaskStatus) -> bool:
    if current == target:
        return True
    return target in ALLOWED_TRANSITIONS.get(current, frozenset())


def assert_transition(current: TaskStatus, target: TaskStatus) -> None:
    if not can_transition(current, target):
        raise InvalidTransition(current, target)


def transition(task: Task, target: TaskStatus, *, error_message: str | None = None) -> Task:
    assert_transition(task.status, target)
    data = task.model_dump()
    data["status"] = target
    data["updated_at"] = utc_now_iso()
    if error_message is not None:
        data["error_message"] = error_message
    return Task.model_validate(data)
