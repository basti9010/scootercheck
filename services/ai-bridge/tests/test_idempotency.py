"""Idempotent create_task tests."""

from __future__ import annotations

from pathlib import Path

from ai_bridge.models import TaskCreate, TaskPriority, TaskSource
from ai_bridge.store import TaskStore


def _payload(key: str = "idem-abc") -> TaskCreate:
    return TaskCreate(
        title="Idempotent sample",
        description="Ensure create_task is idempotent",
        source=TaskSource.CLI,
        repository="owner/scootercheck",
        base_branch="cursor/development-automation-b100",
        priority=TaskPriority.P2,
        idempotency_key=key,
        requirements=["no secrets in logs"],
        acceptance_criteria=["same key → same task_id"],
    )


def test_create_task_idempotent(tmp_path: Path):
    store = TaskStore(tmp_path)
    t1, created1 = store.create_task(_payload())
    t2, created2 = store.create_task(_payload())
    assert created1 is True
    assert created2 is False
    assert t1.task_id == t2.task_id


def test_different_keys_create_distinct_tasks(tmp_path: Path):
    store = TaskStore(tmp_path)
    a, _ = store.create_task(_payload("key-a"))
    b, _ = store.create_task(_payload("key-b"))
    assert a.task_id != b.task_id


def test_get_by_idempotency_key(tmp_path: Path):
    store = TaskStore(tmp_path)
    created, _ = store.create_task(_payload("lookup-1"))
    found = store.get_by_idempotency_key("lookup-1")
    assert found is not None
    assert found.task_id == created.task_id
    assert store.get_by_idempotency_key("missing") is None
