"""SQLite persistence + JSON migration + ownership listing."""

from __future__ import annotations

import json
from pathlib import Path

from ai_bridge.models import TaskCreate, TaskPriority, TaskSource, TaskStatus
from ai_bridge.sqlite_store import SqliteTaskStore
from ai_bridge.store import TaskStore


def _payload(key: str, owner: str = "alice") -> TaskCreate:
    return TaskCreate(
        title="SQLite sample",
        description="Persist tasks",
        source=TaskSource.API,
        repository="https://github.com/basti9010/scootercheck",
        base_branch="cursor/ai-bridge-v2-b100",
        priority=TaskPriority.P2,
        idempotency_key=key,
        requested_by=owner,
    )


def test_sqlite_idempotent_and_restart(tmp_path: Path) -> None:
    db = tmp_path / "t.sqlite3"
    store = SqliteTaskStore(db)
    t1, created = store.create_task(_payload("k1"))
    assert created is True
    t2, created2 = store.create_task(_payload("k1"))
    assert created2 is False
    assert t1.task_id == t2.task_id

    # "restart"
    store2 = SqliteTaskStore(db)
    found = store2.get(t1.task_id)
    assert found is not None
    assert found.title == "SQLite sample"


def test_owner_isolation(tmp_path: Path) -> None:
    store = SqliteTaskStore(tmp_path / "o.sqlite3")
    store.create_task(_payload("a", "alice"))
    store.create_task(_payload("b", "bob"))
    alice = store.list_tasks(owner_subject="alice", admin=False)
    assert len(alice) == 1
    assert alice[0].requested_by == "alice"
    admin = store.list_tasks(admin=True)
    assert len(admin) == 2


def test_migrate_from_json(tmp_path: Path) -> None:
    json_root = tmp_path / "json"
    js = TaskStore(json_root)
    task, _ = js.create_task(_payload("mig-1"))
    db = SqliteTaskStore(tmp_path / "m.sqlite3")
    n = db.migrate_from_json(json_root)
    assert n == 1
    assert db.get(task.task_id) is not None
    # sources untouched
    assert (json_root / "tasks" / f"{task.task_id}.json").is_file()


def test_status_update_persists(tmp_path: Path) -> None:
    store = SqliteTaskStore(tmp_path / "s.sqlite3")
    task, _ = store.create_task(_payload("st-1"))
    updated = store.update_status(task.task_id, TaskStatus.VALIDATING)
    assert updated.status == TaskStatus.VALIDATING
    assert store.get(task.task_id).status == TaskStatus.VALIDATING
